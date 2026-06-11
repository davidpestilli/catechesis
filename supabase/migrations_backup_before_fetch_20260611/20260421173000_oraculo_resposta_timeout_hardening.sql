-- =========================================================================
-- Hardening: oraculo_gerar_resposta_sob_demanda (timeout + payload control)
-- =========================================================================
-- Problemas corrigidos:
-- 1) timeout intermitente ao gerar resposta sob demanda
-- 2) payload excessivo para IA (fontes muito longas)
--
-- Estrategia:
-- - limita tamanho de cada fonte e do contexto agregado
-- - reduz p_max_tokens para resposta mais rapida
-- - define statement_timeout local da funcao
-- - trata query_canceled retornando erro controlado (sem 500 generico)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.oraculo_gerar_resposta_sob_demanda(
  p_ticket_id UUID,
  p_ticket_ids UUID[] DEFAULT '{}',
  p_script_ids UUID[] DEFAULT '{}'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_descricao TEXT;
  v_gse TEXT;
  v_email TEXT;
  v_fontes_texto TEXT := '';
  v_tickets_texto TEXT := '';
  v_scripts_texto TEXT := '';
  v_count_tickets INT := 0;
  v_count_scripts INT := 0;
  v_messages JSONB;
  v_resposta_raw JSONB;
  v_resposta TEXT;
  v_html TEXT;
  v_inicio TIMESTAMPTZ := clock_timestamp();
  v_duracao_ms INT;
BEGIN
  -- Timeout local apenas para esta execucao.
  PERFORM set_config('statement_timeout', '90s', true);

  SELECT t.descricao, t.gse, t.email
    INTO v_descricao, v_gse, v_email
    FROM public.tickets t
   WHERE t.id = p_ticket_id;

  IF v_descricao IS NULL THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Ticket nao encontrado: ' || p_ticket_id::text
    );
  END IF;

  IF (cardinality(p_ticket_ids) = 0 AND cardinality(p_script_ids) = 0) THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Selecione ao menos uma fonte (ticket ou script).'
    );
  END IF;

  IF cardinality(p_ticket_ids) > 0 THEN
    SELECT
      COALESCE(
        string_agg(
          E'\n--- TICKET RELACIONADO #' || t.numero_chamado || E' ---\n'
          || 'PERGUNTA:' || E'\n' || LEFT(COALESCE(t.descricao, '(sem descricao)'), 1600) || E'\n\n'
          || 'RESPOSTA APLICADA:' || E'\n' || LEFT(COALESCE(t.resposta_ia, '(sem resposta)'), 2200),
          E'\n\n'
        ),
        ''
      ),
      count(*)
      INTO v_tickets_texto, v_count_tickets
      FROM public.tickets t
     WHERE t.id = ANY(p_ticket_ids);
  END IF;

  IF cardinality(p_script_ids) > 0 THEN
    SELECT
      COALESCE(
        string_agg(
          E'\n--- SCRIPT: ' || s.nome || E' ---\n'
          || LEFT(COALESCE(NULLIF(s.conteudo_atendente, ''), s.conteudo_bruto, '(sem conteudo)'), 2800),
          E'\n\n'
        ),
        ''
      ),
      count(*)
      INTO v_scripts_texto, v_count_scripts
      FROM public.scripts_customizados s
     WHERE s.id = ANY(p_script_ids);
  END IF;

  v_fontes_texto := LEFT(COALESCE(v_tickets_texto, '') || E'\n\n' || COALESCE(v_scripts_texto, ''), 24000);

  IF btrim(v_fontes_texto) = '' THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Nao foi possivel montar contexto com as fontes selecionadas.'
    );
  END IF;

  v_messages := jsonb_build_array(
    jsonb_build_object(
      'role', 'system',
      'content',
      'Voce e um assistente especializado em redigir respostas claras e objetivas para chamados de suporte tecnico do TJSC. ' ||
      'Use APENAS as fontes fornecidas (tickets resolvidos similares e scripts de procedimento) como base. ' ||
      'A resposta deve ser em HTML simples (use <p>, <ul>, <li>, <strong>, <br>). ' ||
      'NAO inclua saudacoes como "Prezado"; comece direto pelo conteudo. ' ||
      'NAO mencione que esta usando fontes; apenas redija a resposta final como se fosse o atendente. ' ||
      'Seja conciso, profissional e pratico.'
    ),
    jsonb_build_object(
      'role', 'user',
      'content',
      'CHAMADO ATUAL (GSE: ' || COALESCE(v_gse, 'N/A') || '):' || E'\n'
      || LEFT(COALESCE(v_descricao, '(sem descricao)'), 4000) || E'\n\n'
      || '=== FONTES DE REFERENCIA ===' || E'\n'
      || v_fontes_texto || E'\n\n'
      || '=== TAREFA ===' || E'\n'
      || 'Redija a resposta final ao usuario em HTML, usando as fontes acima como base. '
      || 'A resposta deve ser direta, profissional e resolver o problema descrito no chamado atual.'
    )
  );

  BEGIN
    v_resposta_raw := public.chamar_deepseek(
      p_messages := v_messages,
      p_model := 'deepseek-chat',
      p_temperature := 0.3,
      p_max_tokens := 1400
    );
  EXCEPTION
    WHEN query_canceled THEN
      RETURN jsonb_build_object(
        'sucesso', false,
        'erro', 'Tempo limite excedido ao gerar resposta. Tente com menos fontes selecionadas.'
      );
    WHEN OTHERS THEN
      RETURN jsonb_build_object(
        'sucesso', false,
        'erro', 'Falha ao chamar DeepSeek: ' || SQLERRM
      );
  END;

  v_resposta := v_resposta_raw -> 'choices' -> 0 -> 'message' ->> 'content';

  IF v_resposta IS NULL OR length(v_resposta) = 0 THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'DeepSeek retornou resposta vazia',
      'raw', v_resposta_raw
    );
  END IF;

  v_html := regexp_replace(v_resposta, '^```(html)?\s*', '', 'i');
  v_html := regexp_replace(v_html, '\s*```\s*$', '');
  v_html := trim(v_html);

  v_duracao_ms := EXTRACT(MILLISECONDS FROM (clock_timestamp() - v_inicio))::INT;

  RETURN jsonb_build_object(
    'sucesso', true,
    'resposta_html', v_html,
    'duracao_ms', v_duracao_ms,
    'fontes_usadas', jsonb_build_object(
      'tickets', v_count_tickets,
      'scripts', v_count_scripts
    )
  );

EXCEPTION
  WHEN query_canceled THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Tempo limite excedido ao gerar resposta. Tente novamente.'
    );
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Erro interno ao gerar resposta: ' || SQLERRM
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.oraculo_gerar_resposta_sob_demanda(UUID, UUID[], UUID[]) TO authenticated, service_role;
COMMENT ON FUNCTION public.oraculo_gerar_resposta_sob_demanda(UUID, UUID[], UUID[]) IS
'Hardening de timeout e payload: limita contexto, ajusta max_tokens e retorna erro controlado em query_canceled.';

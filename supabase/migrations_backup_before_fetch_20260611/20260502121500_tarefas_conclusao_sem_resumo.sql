-- =====================================================================
-- Migração: Conclusão de tarefa sem resumo obrigatório
-- Data: 2026-05-02
--
-- Objetivo:
--   Remover a obrigatoriedade do campo de resumo ao concluir tarefas,
--   preservando compatibilidade com histórico e coluna resumo_conclusao.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.alterar_estado_tarefa(
  p_tarefa_id UUID,
  p_novo_estado TEXT,
  p_justificativa TEXT DEFAULT NULL::TEXT,
  p_resumo TEXT DEFAULT NULL::TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_nome TEXT;
  v_tarefa RECORD;
  v_tipo_evento TEXT;
  v_participantes UUID[];
  v_resumo_normalizado TEXT;
BEGIN
  IF p_novo_estado NOT IN ('em_andamento', 'pausada', 'concluida', 'cancelada') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Estado inválido');
  END IF;

  SELECT COALESCE(nome, email) INTO v_user_nome
  FROM public.users
  WHERE id = v_user_id;

  SELECT * INTO v_tarefa
  FROM public.tarefas
  WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa não encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsável pode alterar o estado');
  END IF;

  v_resumo_normalizado := NULLIF(TRIM(COALESCE(p_resumo, '')), '');

  IF p_novo_estado = 'pausada' THEN
    IF p_justificativa IS NULL OR TRIM(p_justificativa) = '' THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'Justificativa obrigatória para pausar');
    END IF;
    v_tipo_evento := 'estado_pausada';

  ELSIF p_novo_estado = 'cancelada' THEN
    IF p_justificativa IS NULL OR TRIM(p_justificativa) = '' THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'Justificativa obrigatória para cancelar');
    END IF;
    v_tipo_evento := 'estado_cancelada';

  ELSIF p_novo_estado = 'concluida' THEN
    v_tipo_evento := 'estado_concluida';

  ELSIF p_novo_estado = 'em_andamento' THEN
    IF v_tarefa.estado IN ('pausada', 'cancelada') THEN
      IF p_justificativa IS NULL OR TRIM(p_justificativa) = '' THEN
        RETURN jsonb_build_object('sucesso', false, 'erro', 'Justificativa obrigatória para reativar');
      END IF;
      v_tipo_evento := 'estado_reativada';
    ELSE
      v_tipo_evento := 'estado_em_andamento';
    END IF;
  END IF;

  UPDATE public.tarefas
  SET
    estado = p_novo_estado,
    resumo_conclusao = CASE WHEN p_novo_estado = 'concluida' THEN v_resumo_normalizado ELSE resumo_conclusao END,
    atualizado_em = NOW()
  WHERE id = p_tarefa_id;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados, justificativa, resumo)
  VALUES (
    p_tarefa_id,
    v_user_id,
    v_tipo_evento,
    jsonb_build_object('estado_anterior', v_tarefa.estado, 'estado_novo', p_novo_estado),
    p_justificativa,
    CASE WHEN p_novo_estado = 'concluida' THEN v_resumo_normalizado ELSE NULL END
  );

  SELECT ARRAY_AGG(DISTINCT autor_id) INTO v_participantes
  FROM public.tarefa_threads
  WHERE tarefa_id = p_tarefa_id AND autor_id != v_user_id;

  IF v_participantes IS NOT NULL THEN
    INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
    SELECT
      p_tarefa_id,
      unnest(v_participantes),
      v_user_id,
      'tarefa_estado_alterado',
      jsonb_build_object(
        'estado_anterior', v_tarefa.estado,
        'estado_novo', p_novo_estado,
        'tarefa_titulo', v_tarefa.titulo,
        'remetente_nome', v_user_nome
      );
  END IF;

  RETURN jsonb_build_object(
    'sucesso', true,
    'estado', p_novo_estado,
    'mensagem', 'Estado alterado para ' || p_novo_estado
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Erro ao alterar estado da tarefa. Tente novamente.'
    );
END;
$$;
CREATE OR REPLACE FUNCTION public.concluir_tarefa_com_servico(
  p_tarefa_id UUID,
  p_resumo TEXT,
  p_quantidade INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_tarefa RECORD;
  v_tipo_servico TEXT;
  v_usuario_nome TEXT;
  v_finalizador_nome TEXT;
  v_descricao_servico TEXT;
  v_servico_id UUID;
  v_estado_resultado JSONB;
  v_supervisores_notificados INTEGER := 0;
  v_resumo_normalizado TEXT;
BEGIN
  IF p_quantidade IS NULL OR p_quantidade < 1 THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Quantidade deve ser um número inteiro maior ou igual a 1');
  END IF;

  v_resumo_normalizado := NULLIF(TRIM(COALESCE(p_resumo, '')), '');

  SELECT COALESCE(nome, email, 'Usuário') INTO v_finalizador_nome
  FROM public.users
  WHERE id = v_user_id;

  IF v_finalizador_nome IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário autenticado não encontrado');
  END IF;

  SELECT * INTO v_tarefa
  FROM public.tarefas
  WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa não encontrada');
  END IF;

  IF v_tarefa.estado != 'em_andamento' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas tarefas em andamento podem ser concluídas por este fluxo');
  END IF;

  IF v_tarefa.tipo IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Defina um tipo para a tarefa antes de concluir');
  END IF;

  IF v_tarefa.equipe_id IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'A tarefa precisa estar vinculada a uma equipe para gerar serviço');
  END IF;

  v_tipo_servico := CASE v_tarefa.tipo
    WHEN 'ouvidoria' THEN 'ouvidoria'
    WHEN 'cpa' THEN 'cpa'
    WHEN 'email' THEN 'email'
    WHEN 'aplicacao' THEN 'dev_aplicacao'
    WHEN 'chamado_complexo' THEN 'resp_chamado_complexo'
    WHEN 'homologacao' THEN 'homologacao'
    WHEN 'rejeites' THEN 'analise_rejeites'
    WHEN 'chamados_antigos' THEN 'analise_chamados_antigos'
    ELSE NULL
  END;

  IF v_tipo_servico IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa sem serviço equivalente');
  END IF;

  SELECT COALESCE(nome, email, 'Usuário') INTO v_usuario_nome
  FROM public.users
  WHERE id = v_tarefa.dono_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Responsável da tarefa não encontrado');
  END IF;

  v_descricao_servico := concat_ws(
    ' - ',
    NULLIF(TRIM(COALESCE(v_tarefa.titulo, '')), ''),
    NULLIF(TRIM(COALESCE(v_tarefa.descricao, '')), '')
  );

  v_estado_resultado := public.alterar_estado_tarefa(p_tarefa_id, 'concluida', NULL, v_resumo_normalizado);

  IF COALESCE((v_estado_resultado->>'sucesso')::BOOLEAN, false) IS NOT TRUE THEN
    RETURN v_estado_resultado;
  END IF;

  INSERT INTO public.servicos (tipo, quantidade, usuario_id, usuario_nome, equipe_id, observacao, data_execucao, descricao)
  VALUES (v_tipo_servico, p_quantidade, v_tarefa.dono_id, v_usuario_nome, v_tarefa.equipe_id, NULL, NOW(), v_descricao_servico)
  RETURNING id INTO v_servico_id;

  WITH supervisores AS (
    SELECT DISTINCT u.id
    FROM public.users u
    WHERE u.ativo IS DISTINCT FROM FALSE
      AND u.id IS DISTINCT FROM v_user_id
      AND (
        (u.role = 'supervisor' AND u.equipe_id = v_tarefa.equipe_id)
        OR EXISTS (
          SELECT 1
          FROM public.usuario_funcoes_equipe ufe
          WHERE ufe.user_id = u.id
            AND ufe.equipe_id = v_tarefa.equipe_id
            AND ufe.funcao = 'supervisor'
            AND ufe.ativo = TRUE
        )
      )
  )
  INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
  SELECT
    p_tarefa_id,
    supervisores.id,
    v_user_id,
    'tarefa_concluida',
    jsonb_build_object(
      'tarefa_titulo', v_tarefa.titulo,
      'remetente_nome', v_finalizador_nome,
      'estado_novo', 'concluida',
      'servico_id', v_servico_id,
      'tipo_servico', v_tipo_servico,
      'quantidade', p_quantidade
    )
  FROM supervisores;

  GET DIAGNOSTICS v_supervisores_notificados = ROW_COUNT;

  RETURN jsonb_build_object(
    'sucesso', true,
    'estado', 'concluida',
    'servico_id', v_servico_id,
    'tipo_servico', v_tipo_servico,
    'supervisores_notificados', v_supervisores_notificados,
    'mensagem', 'Tarefa concluída e serviço registrado com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados inválidos: verifique tipo de serviço, notificação e quantidade.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao concluir tarefa e registrar serviço: ' || SQLERRM);
END;
$$;
GRANT EXECUTE ON FUNCTION public.alterar_estado_tarefa(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.concluir_tarefa_com_servico(UUID, TEXT, INTEGER) TO authenticated;
COMMENT ON FUNCTION public.concluir_tarefa_com_servico(UUID, TEXT, INTEGER) IS
  'Conclui tarefa, cria serviço equivalente e notifica supervisores da equipe da tarefa. O resumo é opcional.';

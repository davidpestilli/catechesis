-- =====================================================================
-- Migration: Busca semantica em "Buscar Titulos" + RPCs do card Dev/Admin
-- Data: 2026-04-25
--
-- 1) Nova RPC `buscar_scripts_por_embedding_texto`
--    Recebe um vetor de query (2000 dims) gerado no frontend (OpenAI
--    text-embedding-3-large) e retorna os scripts mais similares dentro
--    da equipe do usuario, respeitando a regra de dominio do pipeline
--    existente (ver `buscar_scripts_similares_por_embedding_ticket`).
--
-- 2) RPCs de manutencao para o card Dev/Admin (modo desenvolvimento)
--    - dev_contar_pendentes_embeddings()
--    - dev_listar_scripts_sem_embedding(p_limit)
--    - dev_upsert_script_embedding(p_script_id, p_embedding, ...)
--    - dev_listar_tickets_sem_embedding(p_limit)
--    - dev_upsert_ticket_embedding(p_ticket_id, p_embedding, ...)
--
--    Todas exigem `is_admin() = true`. O processamento (chamada OpenAI)
--    e' feito localmente no navegador (modo dev) usando a chave
--    VITE_OPENAI_API_KEY ja' presente no .env.
-- =====================================================================

SET search_path = public, extensions;
-- ---------------------------------------------------------------------
-- 1) Busca semantica para o filtro "Buscar Titulos" (ScriptsModal)
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.buscar_scripts_por_embedding_texto(
  p_query_embedding vector(2000),
  p_equipe_id_referencia uuid DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_min_similarity double precision DEFAULT 0.20
)
RETURNS TABLE(
  script_id uuid,
  similarity double precision
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_equipe uuid := p_equipe_id_referencia;
BEGIN
  IF p_query_embedding IS NULL THEN
    RETURN;
  END IF;

  -- Se nao informou equipe, tenta deduzir do usuario logado.
  IF v_equipe IS NULL THEN
    SELECT u.equipe_id INTO v_equipe
    FROM public.users u
    WHERE u.id = auth.uid()
    LIMIT 1;
  END IF;

  RETURN QUERY
  SELECT
    se.script_id,
    1 - (se.embedding <=> p_query_embedding) AS similarity
  FROM public.script_embeddings se
  JOIN public.scripts_customizados s ON s.id = se.script_id
  WHERE public.is_script_embedding_target(s.equipe_id, s.habilitado_smith, s.deletado)
    AND (
      v_equipe IS NULL  -- admin sem equipe selecionada ve' tudo
      OR (
        -- Mesma regra do RPC por ticket: 232 ve' externo da 232; 231 ve' 231
        (v_equipe = '11111111-1111-1111-1111-111111111111'::uuid
          AND s.equipe_id = '11111111-1111-1111-1111-111111111111'::uuid
          AND se.dominio = 'externo')
        OR
        (v_equipe = '22222222-2222-2222-2222-222222222222'::uuid
          AND s.equipe_id = '22222222-2222-2222-2222-222222222222'::uuid)
      )
    )
    AND (1 - (se.embedding <=> p_query_embedding)) >= p_min_similarity
  ORDER BY se.embedding <=> p_query_embedding
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
END;
$$;
GRANT EXECUTE ON FUNCTION public.buscar_scripts_por_embedding_texto(vector, uuid, integer, double precision) TO authenticated;
COMMENT ON FUNCTION public.buscar_scripts_por_embedding_texto IS
  'Busca semantica de scripts usada no campo "Buscar Titulos" do ScriptsModal. '
  'Recebe vetor (2000d) gerado no frontend pela OpenAI text-embedding-3-large.';
-- ---------------------------------------------------------------------
-- 2) RPCs do card Dev/Admin
-- ---------------------------------------------------------------------

-- 2.1) Contagem de pendentes (scripts e tickets)
CREATE OR REPLACE FUNCTION public.dev_contar_pendentes_embeddings()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_scripts_alvo bigint;
  v_scripts_com bigint;
  v_scripts_pend bigint;
  v_scripts_fila bigint;
  v_tickets_alvo bigint;
  v_tickets_com bigint;
  v_tickets_pend bigint;
  v_tickets_fila bigint;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: requer perfil admin.' USING ERRCODE = '42501';
  END IF;

  SELECT count(*) INTO v_scripts_alvo
  FROM public.scripts_customizados s
  WHERE public.is_script_embedding_target(s.equipe_id, s.habilitado_smith, s.deletado);

  SELECT count(*) INTO v_scripts_com
  FROM public.script_embeddings se
  JOIN public.scripts_customizados s ON s.id = se.script_id
  WHERE public.is_script_embedding_target(s.equipe_id, s.habilitado_smith, s.deletado);

  v_scripts_pend := GREATEST(0, v_scripts_alvo - v_scripts_com);

  SELECT count(*) INTO v_scripts_fila FROM public.script_embeddings_queue;

  SELECT count(*) INTO v_tickets_alvo
  FROM public.tickets t
  WHERE t.descricao IS NOT NULL
    AND public.is_ticket_embedding_target(t.gse, t.status);

  SELECT count(*) INTO v_tickets_com
  FROM public.ticket_embeddings te
  JOIN public.tickets t ON t.id = te.ticket_id
  WHERE public.is_ticket_embedding_target(t.gse, t.status);

  v_tickets_pend := GREATEST(0, v_tickets_alvo - v_tickets_com);

  SELECT count(*) INTO v_tickets_fila FROM public.ticket_embeddings_queue;

  RETURN jsonb_build_object(
    'scripts', jsonb_build_object(
      'alvo', v_scripts_alvo,
      'com_embedding', v_scripts_com,
      'pendentes', v_scripts_pend,
      'na_fila', v_scripts_fila
    ),
    'tickets', jsonb_build_object(
      'alvo', v_tickets_alvo,
      'com_embedding', v_tickets_com,
      'pendentes', v_tickets_pend,
      'na_fila', v_tickets_fila
    )
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.dev_contar_pendentes_embeddings() TO authenticated;
-- 2.2) Listar scripts sem embedding com payload pronto p/ enviar a' OpenAI
CREATE OR REPLACE FUNCTION public.dev_listar_scripts_sem_embedding(
  p_limit integer DEFAULT 20
)
RETURNS TABLE(
  script_id uuid,
  equipe_id uuid,
  pasta_id uuid,
  dominio text,
  tipo_requisitante text,
  nome text,
  pergunta text,
  conteudo_bruto text,
  conteudo_atendente text,
  grupo_nome text,
  subpasta_nome text,
  script_updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: requer perfil admin.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    s.id AS script_id,
    s.equipe_id,
    s.pasta_id,
    COALESCE(s.dominio, public.determinar_dominio_script(s.equipe_id, s.pasta_id)) AS dominio,
    s.tipo_requisitante,
    s.nome,
    s.pergunta,
    s.conteudo_bruto,
    s.conteudo_atendente,
    COALESCE(grupo.nome, pasta.nome) AS grupo_nome,
    CASE WHEN pasta.pasta_pai_id IS NOT NULL THEN pasta.nome ELSE NULL END AS subpasta_nome,
    s.criado_em AS script_updated_at
  FROM public.scripts_customizados s
  LEFT JOIN public.script_embeddings se ON se.script_id = s.id
  LEFT JOIN public.pastas_scripts pasta ON s.pasta_id = pasta.id
  LEFT JOIN public.pastas_scripts grupo ON pasta.pasta_pai_id = grupo.id
  WHERE se.script_id IS NULL
    AND public.is_script_embedding_target(s.equipe_id, s.habilitado_smith, s.deletado)
    AND COALESCE(s.dominio, public.determinar_dominio_script(s.equipe_id, s.pasta_id)) IS NOT NULL
  ORDER BY s.criado_em DESC NULLS LAST
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 200));
END;
$$;
GRANT EXECUTE ON FUNCTION public.dev_listar_scripts_sem_embedding(integer) TO authenticated;
-- 2.3) Upsert do embedding de script (gerado localmente no browser)
CREATE OR REPLACE FUNCTION public.dev_upsert_script_embedding(
  p_script_id uuid,
  p_embedding vector(2000),
  p_conteudo_hash text,
  p_model text DEFAULT 'text-embedding-3-large',
  p_dim integer DEFAULT 2000
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_equipe uuid;
  v_pasta uuid;
  v_dominio text;
  v_tipo_req text;
  v_titulo text;
  v_pergunta text;
  v_bruto text;
  v_atendente text;
  v_updated timestamptz;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: requer perfil admin.' USING ERRCODE = '42501';
  END IF;

  IF p_embedding IS NULL OR p_script_id IS NULL THEN
    RAISE EXCEPTION 'Parametros obrigatorios ausentes.' USING ERRCODE = '22023';
  END IF;

  SELECT
    s.equipe_id,
    s.pasta_id,
    COALESCE(s.dominio, public.determinar_dominio_script(s.equipe_id, s.pasta_id)),
    s.tipo_requisitante,
    s.nome,
    s.pergunta,
    s.conteudo_bruto,
    s.conteudo_atendente,
    s.criado_em
  INTO v_equipe, v_pasta, v_dominio, v_tipo_req, v_titulo, v_pergunta, v_bruto, v_atendente, v_updated
  FROM public.scripts_customizados s
  WHERE s.id = p_script_id;

  IF v_equipe IS NULL THEN
    RAISE EXCEPTION 'Script % nao encontrado.', p_script_id USING ERRCODE = 'P0002';
  END IF;

  INSERT INTO public.script_embeddings (
    script_id, equipe_id, pasta_id, dominio, tipo_requisitante,
    titulo, pergunta, conteudo_bruto, conteudo_atendente,
    conteudo_hash, embedding, embedding_model, embedding_dim,
    script_updated_at, updated_at
  ) VALUES (
    p_script_id, v_equipe, v_pasta, v_dominio, v_tipo_req,
    v_titulo, v_pergunta, v_bruto, v_atendente,
    p_conteudo_hash, p_embedding, p_model, p_dim,
    v_updated, now()
  )
  ON CONFLICT (script_id) DO UPDATE SET
    equipe_id = EXCLUDED.equipe_id,
    pasta_id = EXCLUDED.pasta_id,
    dominio = EXCLUDED.dominio,
    tipo_requisitante = EXCLUDED.tipo_requisitante,
    titulo = EXCLUDED.titulo,
    pergunta = EXCLUDED.pergunta,
    conteudo_bruto = EXCLUDED.conteudo_bruto,
    conteudo_atendente = EXCLUDED.conteudo_atendente,
    conteudo_hash = EXCLUDED.conteudo_hash,
    embedding = EXCLUDED.embedding,
    embedding_model = EXCLUDED.embedding_model,
    embedding_dim = EXCLUDED.embedding_dim,
    script_updated_at = EXCLUDED.script_updated_at,
    updated_at = now();

  -- Limpa job da fila (se existir)
  DELETE FROM public.script_embeddings_queue WHERE script_id = p_script_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.dev_upsert_script_embedding(uuid, vector, text, text, integer) TO authenticated;
-- 2.4) Listar tickets sem embedding (para processamento local)
CREATE OR REPLACE FUNCTION public.dev_listar_tickets_sem_embedding(
  p_limit integer DEFAULT 20
)
RETURNS TABLE(
  ticket_id uuid,
  numero_chamado text,
  gse text,
  equipe_id uuid,
  status text,
  descricao text,
  ticket_updated_at timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: requer perfil admin.' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    t.id AS ticket_id,
    t.numero_chamado,
    t.gse,
    public.get_ticket_equipe_id(t.gse) AS equipe_id,
    t.status,
    t.descricao,
    COALESCE(t.updated_at, t.created_at)::timestamptz AS ticket_updated_at
  FROM public.tickets t
  LEFT JOIN public.ticket_embeddings te ON te.ticket_id = t.id
  WHERE te.ticket_id IS NULL
    AND t.descricao IS NOT NULL
    AND public.is_ticket_embedding_target(t.gse, t.status)
    AND public.get_ticket_equipe_id(t.gse) IS NOT NULL
  ORDER BY COALESCE(t.updated_at, t.created_at) DESC NULLS LAST
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 20), 500));
END;
$$;
GRANT EXECUTE ON FUNCTION public.dev_listar_tickets_sem_embedding(integer) TO authenticated;
-- 2.5) Upsert do embedding de ticket
CREATE OR REPLACE FUNCTION public.dev_upsert_ticket_embedding(
  p_ticket_id uuid,
  p_embedding vector(2000),
  p_descricao_hash text,
  p_model text DEFAULT 'text-embedding-3-large',
  p_dim integer DEFAULT 2000
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_numero text;
  v_gse text;
  v_equipe uuid;
  v_status text;
  v_updated timestamptz;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'Acesso negado: requer perfil admin.' USING ERRCODE = '42501';
  END IF;

  IF p_embedding IS NULL OR p_ticket_id IS NULL THEN
    RAISE EXCEPTION 'Parametros obrigatorios ausentes.' USING ERRCODE = '22023';
  END IF;

  SELECT
    t.numero_chamado,
    t.gse,
    public.get_ticket_equipe_id(t.gse),
    t.status,
    COALESCE(t.updated_at, t.created_at)::timestamptz
  INTO v_numero, v_gse, v_equipe, v_status, v_updated
  FROM public.tickets t
  WHERE t.id = p_ticket_id;

  IF v_numero IS NULL THEN
    RAISE EXCEPTION 'Ticket % nao encontrado.', p_ticket_id USING ERRCODE = 'P0002';
  END IF;

  IF v_equipe IS NULL THEN
    RAISE EXCEPTION 'Ticket % sem equipe mapeada para o GSE %.', p_ticket_id, v_gse USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.ticket_embeddings (
    ticket_id, numero_chamado, gse, equipe_id, status,
    descricao_hash, embedding, embedding_model, embedding_dim,
    ticket_updated_at, updated_at
  ) VALUES (
    p_ticket_id, v_numero, v_gse, v_equipe, v_status,
    p_descricao_hash, p_embedding, p_model, p_dim,
    v_updated, now()
  )
  ON CONFLICT (ticket_id) DO UPDATE SET
    numero_chamado = EXCLUDED.numero_chamado,
    gse = EXCLUDED.gse,
    equipe_id = EXCLUDED.equipe_id,
    status = EXCLUDED.status,
    descricao_hash = EXCLUDED.descricao_hash,
    embedding = EXCLUDED.embedding,
    embedding_model = EXCLUDED.embedding_model,
    embedding_dim = EXCLUDED.embedding_dim,
    ticket_updated_at = EXCLUDED.ticket_updated_at,
    updated_at = now();

  DELETE FROM public.ticket_embeddings_queue WHERE ticket_id = p_ticket_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.dev_upsert_ticket_embedding(uuid, vector, text, text, integer) TO authenticated;
COMMENT ON FUNCTION public.dev_contar_pendentes_embeddings IS 'Card Dev/Admin: contagens de embeddings pendentes (scripts/tickets).';
COMMENT ON FUNCTION public.dev_listar_scripts_sem_embedding IS 'Card Dev/Admin: lista scripts sem embedding com payload pronto.';
COMMENT ON FUNCTION public.dev_upsert_script_embedding IS 'Card Dev/Admin: persiste embedding de script gerado localmente (browser+OpenAI).';
COMMENT ON FUNCTION public.dev_listar_tickets_sem_embedding IS 'Card Dev/Admin: lista tickets sem embedding com descricao.';
COMMENT ON FUNCTION public.dev_upsert_ticket_embedding IS 'Card Dev/Admin: persiste embedding de ticket gerado localmente (browser+OpenAI).';

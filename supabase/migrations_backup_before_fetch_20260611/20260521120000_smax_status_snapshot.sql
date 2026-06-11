-- =====================================================
-- SMAX Situacao Snapshot
-- Cruza tickets N3 ativos e tickets suspensos do Distribuidor
-- com o estado atual no SMAX, destacando Feito e Validacao.
-- =====================================================

BEGIN;
INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem) VALUES
  (
    'admin.smax_status',
    'Acessar SMAX Situacao',
    'Visualizacao dos tickets N3 ativos e suspensos que aparecem como Feito ou Validacao no SMAX.',
    'admin',
    'src/pages/Home.tsx; src/components/PastelariaModal.tsx'
  ),
  (
    'distribuidor.smax_status_robo_dev',
    'Robo SMAX Situacao (Dev)',
    'Card dev para pesquisar no SMAX a situacao de tickets N3 ativos e tickets suspensos do Distribuidor.',
    'distribuidor',
    'src/pages/Home.tsx'
  )
ON CONFLICT (codigo) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  categoria = EXCLUDED.categoria,
  origem = EXCLUDED.origem,
  updated_at = now();
INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id) VALUES
  ('admin.smax_status', 'role', 'user'),
  ('admin.smax_status', 'role', 'supervisor'),
  ('admin.smax_status', 'role', 'coordenador'),
  ('distribuidor.smax_status_robo_dev', 'role', 'user'),
  ('distribuidor.smax_status_robo_dev', 'role', 'supervisor'),
  ('distribuidor.smax_status_robo_dev', 'role', 'coordenador')
ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS public.smax_status_snapshot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipe_id uuid NOT NULL REFERENCES public.equipes(id) ON DELETE CASCADE,
  ticket_numero text NOT NULL,
  estado_match text NOT NULL,
  smax_status_codigo text,
  smax_status_label text,
  phase_id text,
  phase_label text,
  ultima_atualizacao_smax timestamptz,
  smax_url text NOT NULL,
  fonte_n3 boolean NOT NULL DEFAULT false,
  fonte_suspenso boolean NOT NULL DEFAULT false,
  escalacao_n3_id uuid REFERENCES public.escalacoes_n3(id) ON DELETE SET NULL,
  ticket_id uuid REFERENCES public.tickets(id) ON DELETE SET NULL,
  local_tramitacao text,
  assunto text,
  motivo_envio text,
  causa_suspensao text,
  gse text,
  origem text,
  tempo_espera_origem timestamptz,
  origens jsonb NOT NULL DEFAULT '[]'::jsonb,
  raw_smax jsonb NOT NULL DEFAULT '{}'::jsonb,
  capturado_em timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT smax_status_snapshot_unique_ticket UNIQUE (equipe_id, ticket_numero),
  CONSTRAINT smax_status_snapshot_estado_check CHECK (estado_match IN ('feito', 'validacao')),
  CONSTRAINT smax_status_snapshot_fonte_check CHECK (fonte_n3 = true OR fonte_suspenso = true)
);
CREATE INDEX IF NOT EXISTS idx_smax_status_snapshot_equipe_estado
  ON public.smax_status_snapshot(equipe_id, estado_match, ultima_atualizacao_smax DESC NULLS LAST);
CREATE INDEX IF NOT EXISTS idx_smax_status_snapshot_equipe_ticket
  ON public.smax_status_snapshot(equipe_id, ticket_numero);
CREATE INDEX IF NOT EXISTS idx_smax_status_snapshot_n3
  ON public.smax_status_snapshot(escalacao_n3_id)
  WHERE escalacao_n3_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_smax_status_snapshot_ticket_id
  ON public.smax_status_snapshot(ticket_id)
  WHERE ticket_id IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.smax_status_snapshot_meta (
  equipe_id uuid PRIMARY KEY REFERENCES public.equipes(id) ON DELETE CASCADE,
  pesquisado_em timestamptz NOT NULL,
  total_candidatos integer NOT NULL DEFAULT 0,
  total_extraido integer NOT NULL DEFAULT 0,
  total_matches integer NOT NULL DEFAULT 0,
  total_feito integer NOT NULL DEFAULT 0,
  total_validacao integer NOT NULL DEFAULT 0,
  total_ignorado integer NOT NULL DEFAULT 0,
  total_n3 integer NOT NULL DEFAULT 0,
  total_suspensos integer NOT NULL DEFAULT 0,
  executado_por uuid REFERENCES public.users(id) ON DELETE SET NULL,
  avisos jsonb NOT NULL DEFAULT '[]'::jsonb,
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.smax_status_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.smax_status_snapshot_meta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS smax_status_snapshot_select_equipe ON public.smax_status_snapshot;
CREATE POLICY smax_status_snapshot_select_equipe
  ON public.smax_status_snapshot FOR SELECT
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
DROP POLICY IF EXISTS smax_status_snapshot_delete_equipe ON public.smax_status_snapshot;
CREATE POLICY smax_status_snapshot_delete_equipe
  ON public.smax_status_snapshot FOR DELETE
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
DROP POLICY IF EXISTS smax_status_snapshot_meta_select_equipe ON public.smax_status_snapshot_meta;
CREATE POLICY smax_status_snapshot_meta_select_equipe
  ON public.smax_status_snapshot_meta FOR SELECT
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
GRANT SELECT, DELETE ON public.smax_status_snapshot TO authenticated;
GRANT SELECT ON public.smax_status_snapshot_meta TO authenticated;
CREATE OR REPLACE FUNCTION public.smax_status_obter_candidatos(
  p_equipe_id uuid DEFAULT NULL,
  p_origem text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_equipe_id uuid;
  v_candidatos jsonb := '[]'::jsonb;
  v_total_n3 integer := 0;
  v_total_suspensos integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  v_equipe_id := COALESCE(p_equipe_id, v_user_equipe_id);

  IF v_equipe_id IS NULL THEN
    RETURN jsonb_build_object(
      'candidatos', '[]'::jsonb,
      'total', 0,
      'total_n3', 0,
      'total_suspensos', 0,
      'total_ambas_fontes', 0
    );
  END IF;

  IF v_equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para consultar esta equipe';
  END IF;

  WITH fontes AS (
    SELECT
      regexp_replace(COALESCE(e.numero_ticket, ''), '[^0-9]', '', 'g') AS ticket_numero,
      'n3'::text AS fonte,
      e.id AS escalacao_n3_id,
      NULL::uuid AS ticket_id,
      e.local_tramitacao,
      e.assunto,
      e.motivo_envio,
      NULL::text AS causa_suspensao,
      NULL::text AS gse,
      NULL::text AS origem,
      NULL::timestamptz AS tempo_espera_origem,
      e.created_at,
      jsonb_build_object(
        'tipo', 'n3',
        'escalacao_n3_id', e.id,
        'local_tramitacao', e.local_tramitacao,
        'assunto', e.assunto,
        'motivo_envio', e.motivo_envio,
        'data_envio', e.data_envio,
        'created_at', e.created_at
      ) AS origem_detalhe
    FROM public.escalacoes_n3 e
    WHERE e.equipe_id = v_equipe_id
      AND e.status = 'ativo'
      AND regexp_replace(COALESCE(e.numero_ticket, ''), '[^0-9]', '', 'g') <> ''

    UNION ALL

    SELECT
      regexp_replace(COALESCE(t.numero_chamado, ''), '[^0-9]', '', 'g') AS ticket_numero,
      'suspenso'::text AS fonte,
      NULL::uuid AS escalacao_n3_id,
      t.id AS ticket_id,
      NULL::text AS local_tramitacao,
      NULL::text AS assunto,
      NULL::text AS motivo_envio,
      t.causa_suspensao,
      t.gse,
      t.origem,
      t.tempo_espera_origem,
      t.created_at,
      jsonb_build_object(
        'tipo', 'suspenso',
        'ticket_id', t.id,
        'gse', t.gse,
        'origem', t.origem,
        'causa_suspensao', t.causa_suspensao,
        'tempo_espera_origem', t.tempo_espera_origem,
        'created_at', t.created_at
      ) AS origem_detalhe
    FROM public.tickets t
    WHERE t.status = 'aguardando'
      AND COALESCE(t.suspenso, false) = true
      AND t.usuario_atual IS NULL
      AND regexp_replace(COALESCE(t.numero_chamado, ''), '[^0-9]', '', 'g') <> ''
      AND (p_origem IS NULL OR t.origem = p_origem)
      AND EXISTS (
        SELECT 1
        FROM public.gse_equipes ge
        WHERE ge.equipe_id = v_equipe_id
          AND ge.gse = t.gse
      )
  ), agregados AS (
    SELECT
      f.ticket_numero,
      bool_or(f.fonte = 'n3') AS fonte_n3,
      bool_or(f.fonte = 'suspenso') AS fonte_suspenso,
      (array_agg(f.escalacao_n3_id ORDER BY f.created_at DESC) FILTER (WHERE f.escalacao_n3_id IS NOT NULL))[1] AS escalacao_n3_id,
      (array_agg(f.ticket_id ORDER BY f.created_at DESC) FILTER (WHERE f.ticket_id IS NOT NULL))[1] AS ticket_id,
      (array_agg(f.local_tramitacao ORDER BY f.created_at DESC) FILTER (WHERE f.local_tramitacao IS NOT NULL))[1] AS local_tramitacao,
      (array_agg(f.assunto ORDER BY f.created_at DESC) FILTER (WHERE f.assunto IS NOT NULL))[1] AS assunto,
      (array_agg(f.motivo_envio ORDER BY f.created_at DESC) FILTER (WHERE f.motivo_envio IS NOT NULL))[1] AS motivo_envio,
      (array_agg(f.causa_suspensao ORDER BY f.created_at DESC) FILTER (WHERE f.causa_suspensao IS NOT NULL))[1] AS causa_suspensao,
      (array_agg(f.gse ORDER BY f.created_at DESC) FILTER (WHERE f.gse IS NOT NULL))[1] AS gse,
      (array_agg(f.origem ORDER BY f.created_at DESC) FILTER (WHERE f.origem IS NOT NULL))[1] AS origem,
      (array_agg(f.tempo_espera_origem ORDER BY f.created_at DESC) FILTER (WHERE f.tempo_espera_origem IS NOT NULL))[1] AS tempo_espera_origem,
      jsonb_agg(f.origem_detalhe ORDER BY f.fonte, f.created_at DESC) AS origens
    FROM fontes f
    GROUP BY f.ticket_numero
  ), payload AS (
    SELECT
      jsonb_build_object(
        'ticket_numero', a.ticket_numero,
        'smax_url', 'https://suporte.tjsp.jus.br/saw/Request/' || a.ticket_numero || '/general',
        'fonte_n3', a.fonte_n3,
        'fonte_suspenso', a.fonte_suspenso,
        'escalacao_n3_id', a.escalacao_n3_id,
        'ticket_id', a.ticket_id,
        'local_tramitacao', a.local_tramitacao,
        'assunto', a.assunto,
        'motivo_envio', a.motivo_envio,
        'causa_suspensao', a.causa_suspensao,
        'gse', a.gse,
        'origem', a.origem,
        'tempo_espera_origem', a.tempo_espera_origem,
        'origens', a.origens
      ) AS item,
      a.fonte_n3,
      a.fonte_suspenso,
      a.ticket_numero
    FROM agregados a
  )
  SELECT
    COALESCE(jsonb_agg(p.item ORDER BY p.ticket_numero), '[]'::jsonb),
    count(*) FILTER (WHERE p.fonte_n3)::integer,
    count(*) FILTER (WHERE p.fonte_suspenso)::integer
    INTO v_candidatos, v_total_n3, v_total_suspensos
  FROM payload p;

  RETURN jsonb_build_object(
    'candidatos', v_candidatos,
    'total', jsonb_array_length(v_candidatos),
    'total_n3', COALESCE(v_total_n3, 0),
    'total_suspensos', COALESCE(v_total_suspensos, 0),
    'total_ambas_fontes', COALESCE((
      SELECT count(*)::integer
      FROM jsonb_array_elements(v_candidatos) item
      WHERE COALESCE((item->>'fonte_n3')::boolean, false)
        AND COALESCE((item->>'fonte_suspenso')::boolean, false)
    ), 0)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_status_salvar_snapshot(
  p_equipe_id uuid,
  p_registros jsonb,
  p_pesquisado_em timestamptz DEFAULT now(),
  p_avisos jsonb DEFAULT '[]'::jsonb,
  p_detalhes jsonb DEFAULT '{}'::jsonb
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_total_extraido integer := 0;
  v_total_salvo integer := 0;
  v_total_feito integer := 0;
  v_total_validacao integer := 0;
  v_total_n3 integer := 0;
  v_total_suspensos integer := 0;
  v_total_candidatos integer := 0;
  v_total_ignorado integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Equipe obrigatoria';
  END IF;

  IF p_registros IS NULL OR jsonb_typeof(p_registros) <> 'array' THEN
    RAISE EXCEPTION 'Registros devem ser um array JSON';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  IF v_user_equipe_id IS DISTINCT FROM p_equipe_id THEN
    RAISE EXCEPTION 'Equipe informada nao corresponde a equipe do usuario';
  END IF;

  IF NOT public.tem_permissao('distribuidor.smax_status_robo_dev') THEN
    RAISE EXCEPTION 'Usuario sem permissao para executar o robo SMAX Situacao';
  END IF;

  v_total_extraido := jsonb_array_length(p_registros);
  v_total_candidatos := COALESCE(NULLIF(p_detalhes->>'totalCandidatos', '')::integer, v_total_extraido);

  DELETE FROM public.smax_status_snapshot s
  WHERE s.equipe_id = p_equipe_id;

  WITH entrada_raw AS (
    SELECT item
    FROM jsonb_array_elements(p_registros) AS raw(item)
  ), entrada AS (
    SELECT DISTINCT ON (ticket_numero)
      regexp_replace(COALESCE(item->>'ticket_numero', item->>'ticketNumero', item->>'id', ''), '[^0-9]', '', 'g') AS ticket_numero,
      CASE
        WHEN translate(lower(trim(COALESCE(item->>'estado_match', item->>'estadoMatch', item->>'match', ''))), 'áàâãéêíóôõúç', 'aaaaeeiooouc') IN ('feito', 'done') THEN 'feito'
        WHEN translate(lower(trim(COALESCE(item->>'estado_match', item->>'estadoMatch', item->>'match', ''))), 'áàâãéêíóôõúç', 'aaaaeeiooouc') IN ('validacao', 'validacao usuario', 'validation') THEN 'validacao'
        ELSE NULL
      END AS estado_match,
      NULLIF(trim(COALESCE(item->>'smax_status_codigo', item->>'smaxStatusCodigo', item->>'statusCodigo', item->>'status', '')), '') AS smax_status_codigo,
      NULLIF(trim(COALESCE(item->>'smax_status_label', item->>'smaxStatusLabel', item->>'statusLabel', item->>'status_label', '')), '') AS smax_status_label,
      NULLIF(trim(COALESCE(item->>'phase_id', item->>'phaseId', item->>'PhaseId', '')), '') AS phase_id,
      NULLIF(trim(COALESCE(item->>'phase_label', item->>'phaseLabel', item->>'phase', '')), '') AS phase_label,
      NULLIF(trim(COALESCE(item->>'ultima_atualizacao_smax', item->>'ultimaAtualizacaoSmax', item->>'ultima_atualizacao', item->>'lastUpdateTime', '')), '')::timestamptz AS ultima_atualizacao_smax,
      NULLIF(trim(COALESCE(item->>'smax_url', item->>'smaxUrl', '')), '') AS smax_url,
      COALESCE(NULLIF(item->>'fonte_n3', '')::boolean, NULLIF(item->>'fonteN3', '')::boolean, false) AS fonte_n3,
      COALESCE(NULLIF(item->>'fonte_suspenso', '')::boolean, NULLIF(item->>'fonteSuspenso', '')::boolean, false) AS fonte_suspenso,
      NULLIF(trim(COALESCE(item->>'escalacao_n3_id', item->>'escalacaoN3Id', '')), '')::uuid AS escalacao_n3_id,
      NULLIF(trim(COALESCE(item->>'ticket_id', item->>'ticketId', '')), '')::uuid AS ticket_id,
      NULLIF(trim(COALESCE(item->>'local_tramitacao', item->>'localTramitacao', '')), '') AS local_tramitacao,
      NULLIF(trim(COALESCE(item->>'assunto', '')), '') AS assunto,
      NULLIF(trim(COALESCE(item->>'motivo_envio', item->>'motivoEnvio', '')), '') AS motivo_envio,
      NULLIF(trim(COALESCE(item->>'causa_suspensao', item->>'causaSuspensao', '')), '') AS causa_suspensao,
      NULLIF(trim(COALESCE(item->>'gse', '')), '') AS gse,
      NULLIF(trim(COALESCE(item->>'origem', '')), '') AS origem,
      NULLIF(trim(COALESCE(item->>'tempo_espera_origem', item->>'tempoEsperaOrigem', '')), '')::timestamptz AS tempo_espera_origem,
      CASE WHEN jsonb_typeof(item->'origens') = 'array' THEN item->'origens' ELSE '[]'::jsonb END AS origens,
      CASE WHEN jsonb_typeof(item->'raw_smax') = 'object' THEN item->'raw_smax'
           WHEN jsonb_typeof(item->'rawSmax') = 'object' THEN item->'rawSmax'
           ELSE '{}'::jsonb END AS raw_smax
    FROM entrada_raw
    ORDER BY ticket_numero, NULLIF(trim(COALESCE(item->>'ultima_atualizacao_smax', item->>'ultimaAtualizacaoSmax', item->>'ultima_atualizacao', item->>'lastUpdateTime', '')), '')::timestamptz DESC NULLS LAST
  ), validos AS (
    SELECT *
    FROM entrada
    WHERE ticket_numero <> ''
      AND estado_match IN ('feito', 'validacao')
      AND (fonte_n3 = true OR fonte_suspenso = true)
  ), inseridos AS (
    INSERT INTO public.smax_status_snapshot (
      equipe_id,
      ticket_numero,
      estado_match,
      smax_status_codigo,
      smax_status_label,
      phase_id,
      phase_label,
      ultima_atualizacao_smax,
      smax_url,
      fonte_n3,
      fonte_suspenso,
      escalacao_n3_id,
      ticket_id,
      local_tramitacao,
      assunto,
      motivo_envio,
      causa_suspensao,
      gse,
      origem,
      tempo_espera_origem,
      origens,
      raw_smax,
      capturado_em,
      updated_at
    )
    SELECT
      p_equipe_id,
      v.ticket_numero,
      v.estado_match,
      v.smax_status_codigo,
      v.smax_status_label,
      v.phase_id,
      v.phase_label,
      v.ultima_atualizacao_smax,
      COALESCE(v.smax_url, 'https://suporte.tjsp.jus.br/saw/Request/' || v.ticket_numero || '/general'),
      v.fonte_n3,
      v.fonte_suspenso,
      v.escalacao_n3_id,
      v.ticket_id,
      v.local_tramitacao,
      v.assunto,
      v.motivo_envio,
      v.causa_suspensao,
      v.gse,
      v.origem,
      v.tempo_espera_origem,
      v.origens,
      v.raw_smax,
      COALESCE(p_pesquisado_em, now()),
      now()
    FROM validos v
    ON CONFLICT (equipe_id, ticket_numero) DO UPDATE
    SET estado_match = EXCLUDED.estado_match,
        smax_status_codigo = EXCLUDED.smax_status_codigo,
        smax_status_label = EXCLUDED.smax_status_label,
        phase_id = EXCLUDED.phase_id,
        phase_label = EXCLUDED.phase_label,
        ultima_atualizacao_smax = EXCLUDED.ultima_atualizacao_smax,
        smax_url = EXCLUDED.smax_url,
        fonte_n3 = EXCLUDED.fonte_n3,
        fonte_suspenso = EXCLUDED.fonte_suspenso,
        escalacao_n3_id = EXCLUDED.escalacao_n3_id,
        ticket_id = EXCLUDED.ticket_id,
        local_tramitacao = EXCLUDED.local_tramitacao,
        assunto = EXCLUDED.assunto,
        motivo_envio = EXCLUDED.motivo_envio,
        causa_suspensao = EXCLUDED.causa_suspensao,
        gse = EXCLUDED.gse,
        origem = EXCLUDED.origem,
        tempo_espera_origem = EXCLUDED.tempo_espera_origem,
        origens = EXCLUDED.origens,
        raw_smax = EXCLUDED.raw_smax,
        capturado_em = EXCLUDED.capturado_em,
        updated_at = now()
    RETURNING estado_match, fonte_n3, fonte_suspenso
  )
  SELECT
    count(*)::integer,
    count(*) FILTER (WHERE estado_match = 'feito')::integer,
    count(*) FILTER (WHERE estado_match = 'validacao')::integer,
    count(*) FILTER (WHERE fonte_n3)::integer,
    count(*) FILTER (WHERE fonte_suspenso)::integer
    INTO v_total_salvo, v_total_feito, v_total_validacao, v_total_n3, v_total_suspensos
  FROM inseridos;

  v_total_ignorado := GREATEST(COALESCE(v_total_extraido, 0) - COALESCE(v_total_salvo, 0), 0);

  INSERT INTO public.smax_status_snapshot_meta (
    equipe_id,
    pesquisado_em,
    total_candidatos,
    total_extraido,
    total_matches,
    total_feito,
    total_validacao,
    total_ignorado,
    total_n3,
    total_suspensos,
    executado_por,
    avisos,
    detalhes,
    updated_at
  )
  VALUES (
    p_equipe_id,
    COALESCE(p_pesquisado_em, now()),
    COALESCE(v_total_candidatos, 0),
    COALESCE(v_total_extraido, 0),
    COALESCE(v_total_salvo, 0),
    COALESCE(v_total_feito, 0),
    COALESCE(v_total_validacao, 0),
    COALESCE(v_total_ignorado, 0),
    COALESCE(v_total_n3, 0),
    COALESCE(v_total_suspensos, 0),
    v_user_id,
    COALESCE(p_avisos, '[]'::jsonb),
    COALESCE(p_detalhes, '{}'::jsonb),
    now()
  )
  ON CONFLICT (equipe_id) DO UPDATE
  SET pesquisado_em = EXCLUDED.pesquisado_em,
      total_candidatos = EXCLUDED.total_candidatos,
      total_extraido = EXCLUDED.total_extraido,
      total_matches = EXCLUDED.total_matches,
      total_feito = EXCLUDED.total_feito,
      total_validacao = EXCLUDED.total_validacao,
      total_ignorado = EXCLUDED.total_ignorado,
      total_n3 = EXCLUDED.total_n3,
      total_suspensos = EXCLUDED.total_suspensos,
      executado_por = EXCLUDED.executado_por,
      avisos = EXCLUDED.avisos,
      detalhes = EXCLUDED.detalhes,
      updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'equipe_id', p_equipe_id,
    'pesquisado_em', COALESCE(p_pesquisado_em, now()),
    'total_candidatos', COALESCE(v_total_candidatos, 0),
    'total_extraido', COALESCE(v_total_extraido, 0),
    'total_salvo', COALESCE(v_total_salvo, 0),
    'total_matches', COALESCE(v_total_salvo, 0),
    'total_feito', COALESCE(v_total_feito, 0),
    'total_validacao', COALESCE(v_total_validacao, 0),
    'total_ignorado', COALESCE(v_total_ignorado, 0),
    'total_n3', COALESCE(v_total_n3, 0),
    'total_suspensos', COALESCE(v_total_suspensos, 0)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_status_listar(p_equipe_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_equipe_id uuid;
  v_meta jsonb := NULL;
  v_registros jsonb := '[]'::jsonb;
  v_por_estado jsonb := '[]'::jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  v_equipe_id := COALESCE(p_equipe_id, v_user_equipe_id);

  IF v_equipe_id IS NULL THEN
    RETURN jsonb_build_object('meta', NULL, 'registros', '[]'::jsonb, 'por_estado', '[]'::jsonb);
  END IF;

  IF v_equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para consultar esta equipe';
  END IF;

  SELECT to_jsonb(m)
    INTO v_meta
  FROM public.smax_status_snapshot_meta m
  WHERE m.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'equipe_id', s.equipe_id,
      'ticket_numero', s.ticket_numero,
      'estado_match', s.estado_match,
      'smax_status_codigo', s.smax_status_codigo,
      'smax_status_label', s.smax_status_label,
      'phase_id', s.phase_id,
      'phase_label', s.phase_label,
      'ultima_atualizacao_smax', s.ultima_atualizacao_smax,
      'smax_url', s.smax_url,
      'fonte_n3', s.fonte_n3,
      'fonte_suspenso', s.fonte_suspenso,
      'escalacao_n3_id', s.escalacao_n3_id,
      'ticket_id', s.ticket_id,
      'local_tramitacao', s.local_tramitacao,
      'assunto', s.assunto,
      'motivo_envio', s.motivo_envio,
      'causa_suspensao', s.causa_suspensao,
      'gse', s.gse,
      'origem', s.origem,
      'tempo_espera_origem', s.tempo_espera_origem,
      'origens', s.origens,
      'raw_smax', s.raw_smax,
      'capturado_em', s.capturado_em,
      'created_at', s.created_at,
      'updated_at', s.updated_at
    )
    ORDER BY s.estado_match, s.ultima_atualizacao_smax DESC NULLS LAST, s.ticket_numero
  ), '[]'::jsonb)
    INTO v_registros
  FROM public.smax_status_snapshot s
  WHERE s.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'estado_match', grouped.estado_match,
      'total', grouped.total,
      'total_n3', grouped.total_n3,
      'total_suspensos', grouped.total_suspensos
    )
    ORDER BY grouped.estado_match
  ), '[]'::jsonb)
    INTO v_por_estado
  FROM (
    SELECT
      s.estado_match,
      count(*)::integer AS total,
      count(*) FILTER (WHERE s.fonte_n3)::integer AS total_n3,
      count(*) FILTER (WHERE s.fonte_suspenso)::integer AS total_suspensos
    FROM public.smax_status_snapshot s
    WHERE s.equipe_id = v_equipe_id
    GROUP BY s.estado_match
  ) grouped;

  RETURN jsonb_build_object(
    'meta', v_meta,
    'registros', v_registros,
    'por_estado', v_por_estado
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_status_excluir(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_ticket record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  SELECT s.id, s.equipe_id, s.ticket_numero
    INTO v_ticket
  FROM public.smax_status_snapshot s
  WHERE s.id = p_id;

  IF v_ticket.id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'reason', 'not_found');
  END IF;

  IF v_ticket.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para excluir este registro';
  END IF;

  DELETE FROM public.smax_status_snapshot s
  WHERE s.id = p_id;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_ticket.id,
    'ticket_numero', v_ticket.ticket_numero
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_status_excluir_lote(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_total_solicitado integer := 0;
  v_ids_excluidos uuid[] := ARRAY[]::uuid[];
  v_tickets_excluidos text[] := ARRAY[]::text[];
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_ids IS NULL THEN
    p_ids := ARRAY[]::uuid[];
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  SELECT count(*)::integer
    INTO v_total_solicitado
  FROM unnest(p_ids) requested(id);

  WITH deletados AS (
    DELETE FROM public.smax_status_snapshot s
    USING unnest(p_ids) requested(id)
    WHERE s.id = requested.id
      AND s.equipe_id = v_user_equipe_id
    RETURNING s.id, s.ticket_numero
  )
  SELECT
    COALESCE(array_agg(d.id), ARRAY[]::uuid[]),
    COALESCE(array_agg(d.ticket_numero), ARRAY[]::text[])
    INTO v_ids_excluidos, v_tickets_excluidos
  FROM deletados d;

  RETURN jsonb_build_object(
    'success', true,
    'total_solicitado', COALESCE(v_total_solicitado, 0),
    'total_excluido', COALESCE(array_length(v_ids_excluidos, 1), 0),
    'total_ignorado', GREATEST(COALESCE(v_total_solicitado, 0) - COALESCE(array_length(v_ids_excluidos, 1), 0), 0),
    'ids_excluidos', COALESCE(to_jsonb(v_ids_excluidos), '[]'::jsonb),
    'tickets_excluidos', COALESCE(to_jsonb(v_tickets_excluidos), '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_status_obter_candidatos(uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_status_salvar_snapshot(uuid, jsonb, timestamptz, jsonb, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_status_listar(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_status_excluir(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_status_excluir_lote(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_status_obter_candidatos(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_status_salvar_snapshot(uuid, jsonb, timestamptz, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_status_listar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_status_excluir(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_status_excluir_lote(uuid[]) TO authenticated;
ALTER TABLE public.smax_status_snapshot REPLICA IDENTITY FULL;
ALTER TABLE public.smax_status_snapshot_meta REPLICA IDENTITY FULL;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'smax_status_snapshot'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.smax_status_snapshot;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'smax_status_snapshot_meta'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.smax_status_snapshot_meta;
  END IF;
END $$;
COMMIT;

-- =====================================================
-- SMAX Tickets Antigos Snapshot
-- Snapshot de tickets no SMAX aguardando solucao criados
-- ha mais de 10 dias, com alerta por solicitante repetido.
-- =====================================================

BEGIN;
INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem) VALUES
  (
    'admin.tickets_antigos',
    'Acessar Tickets Antigos',
    'Visualizacao e acesso ao card/modal Tickets Antigos em Chamados & Outros Servicos.',
    'admin',
    'src/pages/Home.tsx; src/components/PastelariaModal.tsx'
  ),
  (
    'distribuidor.smax_tickets_antigos_robo_dev',
    'Robo SMAX Tickets Antigos (Dev)',
    'Card dev para extrair tickets aguardando solucao ha mais de 10 dias no SMAX e salvar no dashboard Tickets Antigos.',
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
  ('admin.tickets_antigos', 'role', 'user'),
  ('admin.tickets_antigos', 'role', 'supervisor'),
  ('admin.tickets_antigos', 'role', 'coordenador'),
  ('distribuidor.smax_tickets_antigos_robo_dev', 'role', 'user'),
  ('distribuidor.smax_tickets_antigos_robo_dev', 'role', 'supervisor'),
  ('distribuidor.smax_tickets_antigos_robo_dev', 'role', 'coordenador')
ON CONFLICT DO NOTHING;
CREATE TABLE IF NOT EXISTS public.smax_tickets_antigos_snapshot (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipe_id uuid NOT NULL REFERENCES public.equipes(id) ON DELETE CASCADE,
  user_id uuid REFERENCES public.users(id) ON DELETE SET NULL,
  map_id uuid REFERENCES public.smax_rejeites_usuarios_map(id) ON DELETE SET NULL,
  smax_nome text NOT NULL,
  smax_nome_key text NOT NULL,
  smax_nome_original text,
  ticket_numero text NOT NULL,
  hora_criacao timestamptz NOT NULL,
  ultima_atualizacao timestamptz NOT NULL,
  solicitante_email text,
  total_mesmo_solicitante integer NOT NULL DEFAULT 1,
  smax_url text NOT NULL,
  capturado_em timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  mapeado boolean NOT NULL DEFAULT true,
  grupo_rejeite text NOT NULL DEFAULT 'usuario_mapeado',
  mantido_por uuid REFERENCES public.users(id) ON DELETE SET NULL,
  mantido_at timestamptz,
  respondendo_por uuid REFERENCES public.users(id) ON DELETE SET NULL,
  respondendo_at timestamptz,
  CONSTRAINT smax_tickets_antigos_snapshot_unique_ticket UNIQUE (equipe_id, ticket_numero),
  CONSTRAINT smax_tickets_antigos_snapshot_grupo_check CHECK (grupo_rejeite IN ('usuario_mapeado', 'externo_ou_sem_usuario')),
  CONSTRAINT smax_tickets_antigos_snapshot_respondendo_check CHECK (respondendo_por IS NULL OR respondendo_por = mantido_por),
  CONSTRAINT smax_tickets_antigos_snapshot_total_solicitante_check CHECK (total_mesmo_solicitante >= 1)
);
CREATE INDEX IF NOT EXISTS idx_smax_tickets_antigos_snapshot_equipe_criacao
  ON public.smax_tickets_antigos_snapshot(equipe_id, hora_criacao DESC);
CREATE INDEX IF NOT EXISTS idx_smax_tickets_antigos_snapshot_user_criacao
  ON public.smax_tickets_antigos_snapshot(user_id, hora_criacao DESC);
CREATE INDEX IF NOT EXISTS idx_smax_tickets_antigos_snapshot_equipe_grupo_criacao
  ON public.smax_tickets_antigos_snapshot(equipe_id, grupo_rejeite, hora_criacao DESC);
CREATE INDEX IF NOT EXISTS idx_smax_tickets_antigos_snapshot_equipe_mantido
  ON public.smax_tickets_antigos_snapshot(equipe_id, mantido_por, mantido_at DESC);
CREATE INDEX IF NOT EXISTS idx_smax_tickets_antigos_snapshot_equipe_respondendo
  ON public.smax_tickets_antigos_snapshot(equipe_id, respondendo_por, respondendo_at DESC)
  WHERE respondendo_por IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_smax_tickets_antigos_snapshot_solicitante
  ON public.smax_tickets_antigos_snapshot(equipe_id, solicitante_email)
  WHERE solicitante_email IS NOT NULL;
CREATE TABLE IF NOT EXISTS public.smax_tickets_antigos_snapshot_meta (
  equipe_id uuid PRIMARY KEY REFERENCES public.equipes(id) ON DELETE CASCADE,
  pesquisado_em timestamptz NOT NULL,
  total_extraido integer NOT NULL DEFAULT 0,
  total_mapeado integer NOT NULL DEFAULT 0,
  total_externo_sem_usuario integer NOT NULL DEFAULT 0,
  total_duplicados_solicitante integer NOT NULL DEFAULT 0,
  total_ignorado integer NOT NULL DEFAULT 0,
  executado_por uuid REFERENCES public.users(id) ON DELETE SET NULL,
  avisos jsonb NOT NULL DEFAULT '[]'::jsonb,
  detalhes jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.smax_tickets_antigos_snapshot ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.smax_tickets_antigos_snapshot_meta ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS smax_tickets_antigos_snapshot_select_equipe ON public.smax_tickets_antigos_snapshot;
CREATE POLICY smax_tickets_antigos_snapshot_select_equipe
  ON public.smax_tickets_antigos_snapshot FOR SELECT
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
DROP POLICY IF EXISTS smax_tickets_antigos_snapshot_delete_equipe ON public.smax_tickets_antigos_snapshot;
CREATE POLICY smax_tickets_antigos_snapshot_delete_equipe
  ON public.smax_tickets_antigos_snapshot FOR DELETE
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
DROP POLICY IF EXISTS smax_tickets_antigos_snapshot_meta_select_equipe ON public.smax_tickets_antigos_snapshot_meta;
CREATE POLICY smax_tickets_antigos_snapshot_meta_select_equipe
  ON public.smax_tickets_antigos_snapshot_meta FOR SELECT
  TO authenticated
  USING (equipe_id IN (SELECT u.equipe_id FROM public.users u WHERE u.id = auth.uid()));
GRANT SELECT, DELETE ON public.smax_tickets_antigos_snapshot TO authenticated;
GRANT SELECT ON public.smax_tickets_antigos_snapshot_meta TO authenticated;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_salvar_snapshot(
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
  v_total_processado integer := 0;
  v_total_salvo integer := 0;
  v_total_mapeado integer := 0;
  v_total_externo_sem_usuario integer := 0;
  v_total_duplicados_solicitante integer := 0;
  v_total_ignorado integer := 0;
  v_total_preservado_mantido integer := 0;
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

  IF NOT public.tem_permissao('distribuidor.smax_tickets_antigos_robo_dev') THEN
    RAISE EXCEPTION 'Usuario sem permissao para executar o robo SMAX Tickets Antigos';
  END IF;

  DROP TABLE IF EXISTS pg_temp.smax_tickets_antigos_hold_cache;
  CREATE TEMP TABLE smax_tickets_antigos_hold_cache ON COMMIT DROP AS
  SELECT s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         s.respondendo_por,
         s.respondendo_at
  FROM public.smax_tickets_antigos_snapshot s
  WHERE s.equipe_id = p_equipe_id
    AND (
      s.mantido_por IS NOT NULL
      OR s.respondendo_por IS NOT NULL
    );

  SELECT count(*)::integer
    INTO v_total_preservado_mantido
  FROM public.smax_tickets_antigos_snapshot s
  WHERE s.equipe_id = p_equipe_id
    AND s.mantido_por IS NOT NULL;

  DELETE FROM public.smax_tickets_antigos_snapshot s
  WHERE s.equipe_id = p_equipe_id
    AND s.mantido_por IS NULL;

  WITH entrada_raw AS (
    SELECT item
    FROM jsonb_array_elements(p_registros) AS raw(item)
  ), entrada AS (
    SELECT DISTINCT ON (ticket_numero)
      regexp_replace(COALESCE(item->>'ticket_numero', item->>'ticketNumero', item->>'id', ''), '[^0-9]', '', 'g') AS ticket_numero,
      NULLIF(trim(COALESCE(
        item->>'smax_nome_original',
        item->>'smaxNomeOriginal',
        item->>'smax_nome',
        item->>'smaxNome',
        item->>'designado_especialista',
        item->>'designadoEspecialista',
        ''
      )), '') AS smax_nome_original,
      public.smax_rejeites_normalizar_nome(COALESCE(
        item->>'smax_nome_original',
        item->>'smaxNomeOriginal',
        item->>'smax_nome',
        item->>'smaxNome',
        item->>'designado_especialista',
        item->>'designadoEspecialista',
        ''
      )) AS smax_nome_key,
      NULLIF(trim(COALESCE(item->>'smax_person_id', item->>'smaxPersonId', '')), '') AS smax_person_id,
      NULLIF(trim(COALESCE(item->>'hora_criacao', item->>'horaCriacao', item->>'createTime', '')), '')::timestamptz AS hora_criacao,
      COALESCE(
        NULLIF(trim(COALESCE(item->>'ultima_atualizacao', item->>'ultimaAtualizacao', item->>'lastUpdateTime', '')), '')::timestamptz,
        NULLIF(trim(COALESCE(item->>'hora_criacao', item->>'horaCriacao', item->>'createTime', '')), '')::timestamptz
      ) AS ultima_atualizacao,
      NULLIF(lower(trim(COALESCE(item->>'solicitante_email', item->>'solicitanteEmail', item->>'requesterEmail', item->>'requestedByEmail', ''))), '') AS solicitante_email,
      NULLIF(trim(COALESCE(item->>'smax_url', item->>'smaxUrl', '')), '') AS smax_url
    FROM entrada_raw
    ORDER BY ticket_numero, NULLIF(trim(COALESCE(item->>'hora_criacao', item->>'horaCriacao', item->>'createTime', '')), '')::timestamptz DESC NULLS LAST
  ), validos_base AS (
    SELECT
      ticket_numero,
      smax_nome_original,
      smax_nome_key,
      smax_person_id,
      hora_criacao,
      ultima_atualizacao,
      solicitante_email,
      COALESCE(smax_url, 'https://suporte.tjsp.jus.br/saw/Request/' || ticket_numero) AS smax_url
    FROM entrada
    WHERE ticket_numero <> ''
      AND hora_criacao IS NOT NULL
      AND hora_criacao < COALESCE(p_pesquisado_em, now()) - interval '10 days'
  ), validos AS (
    SELECT
      v.*,
      CASE
        WHEN v.solicitante_email IS NULL THEN 1
        ELSE count(*) OVER (PARTITION BY v.solicitante_email)::integer
      END AS total_mesmo_solicitante
    FROM validos_base v
  ), resolvidos AS (
    SELECT DISTINCT ON (v.ticket_numero)
      v.ticket_numero,
      v.hora_criacao,
      v.ultima_atualizacao,
      v.solicitante_email,
      v.total_mesmo_solicitante,
      v.smax_url,
      v.smax_nome_original,
      m.id AS map_id,
      m.user_id,
      CASE
        WHEN m.id IS NOT NULL THEN m.smax_nome
        ELSE COALESCE(v.smax_nome_original, 'Sem usuario designado')
      END AS smax_nome,
      CASE
        WHEN m.id IS NOT NULL THEN m.smax_nome_key
        ELSE COALESCE(v.smax_nome_key, 'SEM USUARIO DESIGNADO')
      END AS smax_nome_key,
      (m.id IS NOT NULL) AS mapeado,
      CASE
        WHEN m.id IS NOT NULL THEN 'usuario_mapeado'
        ELSE 'externo_ou_sem_usuario'
      END AS grupo_rejeite
    FROM validos v
    LEFT JOIN public.smax_rejeites_usuarios_map m
      ON m.equipe_id = p_equipe_id
     AND m.ativo = true
     AND (
       (v.smax_nome_key IS NOT NULL AND m.smax_nome_key = v.smax_nome_key)
       OR (
         v.smax_person_id IS NOT NULL
         AND m.smax_person_id IS NOT NULL
         AND m.smax_person_id = v.smax_person_id
       )
     )
    ORDER BY v.ticket_numero, (m.id IS NULL), m.user_id NULLS LAST
  ), inseridos AS (
    INSERT INTO public.smax_tickets_antigos_snapshot (
      equipe_id,
      user_id,
      map_id,
      smax_nome,
      smax_nome_key,
      smax_nome_original,
      ticket_numero,
      hora_criacao,
      ultima_atualizacao,
      solicitante_email,
      total_mesmo_solicitante,
      smax_url,
      capturado_em,
      mapeado,
      grupo_rejeite,
      mantido_por,
      mantido_at,
      respondendo_por,
      respondendo_at
    )
    SELECT
      p_equipe_id,
      r.user_id,
      r.map_id,
      r.smax_nome,
      r.smax_nome_key,
      COALESCE(r.smax_nome_original, r.smax_nome),
      r.ticket_numero,
      r.hora_criacao,
      r.ultima_atualizacao,
      r.solicitante_email,
      GREATEST(COALESCE(r.total_mesmo_solicitante, 1), 1),
      r.smax_url,
      COALESCE(p_pesquisado_em, now()),
      r.mapeado,
      r.grupo_rejeite,
      h.mantido_por,
      h.mantido_at,
      CASE WHEN h.mantido_por IS NOT NULL AND h.respondendo_por = h.mantido_por THEN h.respondendo_por ELSE NULL END,
      CASE WHEN h.mantido_por IS NOT NULL AND h.respondendo_por = h.mantido_por THEN h.respondendo_at ELSE NULL END
    FROM resolvidos r
    LEFT JOIN pg_temp.smax_tickets_antigos_hold_cache h
      ON h.ticket_numero = r.ticket_numero
    ON CONFLICT (equipe_id, ticket_numero) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        map_id = EXCLUDED.map_id,
        smax_nome = EXCLUDED.smax_nome,
        smax_nome_key = EXCLUDED.smax_nome_key,
        smax_nome_original = EXCLUDED.smax_nome_original,
        hora_criacao = EXCLUDED.hora_criacao,
        ultima_atualizacao = EXCLUDED.ultima_atualizacao,
        solicitante_email = EXCLUDED.solicitante_email,
        total_mesmo_solicitante = EXCLUDED.total_mesmo_solicitante,
        smax_url = EXCLUDED.smax_url,
        capturado_em = EXCLUDED.capturado_em,
        mapeado = EXCLUDED.mapeado,
        grupo_rejeite = EXCLUDED.grupo_rejeite,
        mantido_por = EXCLUDED.mantido_por,
        mantido_at = EXCLUDED.mantido_at,
        respondendo_por = EXCLUDED.respondendo_por,
        respondendo_at = EXCLUDED.respondendo_at
    RETURNING id
  )
  SELECT
    (SELECT count(*)::integer FROM validos),
    (SELECT count(*)::integer FROM inseridos)
    INTO v_total_extraido, v_total_processado;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE s.mapeado = true)::integer,
         count(*) FILTER (WHERE s.mapeado = false)::integer,
         count(*) FILTER (WHERE s.total_mesmo_solicitante > 1)::integer
    INTO v_total_salvo,
         v_total_mapeado,
         v_total_externo_sem_usuario,
         v_total_duplicados_solicitante
  FROM public.smax_tickets_antigos_snapshot s
  WHERE s.equipe_id = p_equipe_id;

  v_total_ignorado := GREATEST(COALESCE(v_total_extraido, 0) - COALESCE(v_total_processado, 0), 0);

  INSERT INTO public.smax_tickets_antigos_snapshot_meta (
    equipe_id,
    pesquisado_em,
    total_extraido,
    total_mapeado,
    total_externo_sem_usuario,
    total_duplicados_solicitante,
    total_ignorado,
    executado_por,
    avisos,
    detalhes,
    updated_at
  )
  VALUES (
    p_equipe_id,
    COALESCE(p_pesquisado_em, now()),
    COALESCE(v_total_extraido, 0),
    COALESCE(v_total_mapeado, 0),
    COALESCE(v_total_externo_sem_usuario, 0),
    COALESCE(v_total_duplicados_solicitante, 0),
    COALESCE(v_total_ignorado, 0),
    v_user_id,
    COALESCE(p_avisos, '[]'::jsonb),
    COALESCE(p_detalhes, '{}'::jsonb),
    now()
  )
  ON CONFLICT (equipe_id) DO UPDATE
  SET pesquisado_em = EXCLUDED.pesquisado_em,
      total_extraido = EXCLUDED.total_extraido,
      total_mapeado = EXCLUDED.total_mapeado,
      total_externo_sem_usuario = EXCLUDED.total_externo_sem_usuario,
      total_duplicados_solicitante = EXCLUDED.total_duplicados_solicitante,
      total_ignorado = EXCLUDED.total_ignorado,
      executado_por = EXCLUDED.executado_por,
      avisos = EXCLUDED.avisos,
      detalhes = EXCLUDED.detalhes,
      updated_at = now();

  RETURN jsonb_build_object(
    'success', true,
    'equipe_id', p_equipe_id,
    'pesquisado_em', COALESCE(p_pesquisado_em, now()),
    'total_extraido', COALESCE(v_total_extraido, 0),
    'total_salvo', COALESCE(v_total_salvo, 0),
    'total_mapeado', COALESCE(v_total_mapeado, 0),
    'total_externo_sem_usuario', COALESCE(v_total_externo_sem_usuario, 0),
    'total_duplicados_solicitante', COALESCE(v_total_duplicados_solicitante, 0),
    'total_ignorado', COALESCE(v_total_ignorado, 0),
    'total_preservado_mantido', COALESCE(v_total_preservado_mantido, 0)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_listar(p_equipe_id uuid DEFAULT NULL)
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
  v_por_usuario jsonb := '[]'::jsonb;
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
    RETURN jsonb_build_object('meta', NULL, 'registros', '[]'::jsonb, 'por_usuario', '[]'::jsonb);
  END IF;

  IF v_equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para consultar esta equipe';
  END IF;

  SELECT to_jsonb(m)
    INTO v_meta
  FROM public.smax_tickets_antigos_snapshot_meta m
  WHERE m.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'equipe_id', s.equipe_id,
      'user_id', s.user_id,
      'usuario_nome', CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE COALESCE(u.nome, s.smax_nome)
      END,
      'usuario_email', u.email,
      'smax_nome', s.smax_nome,
      'smax_nome_original', s.smax_nome_original,
      'ticket_numero', s.ticket_numero,
      'hora_criacao', s.hora_criacao,
      'ultima_atualizacao', s.ultima_atualizacao,
      'solicitante_email', s.solicitante_email,
      'total_mesmo_solicitante', s.total_mesmo_solicitante,
      'smax_url', s.smax_url,
      'capturado_em', s.capturado_em,
      'mapeado', s.mapeado,
      'grupo_rejeite', s.grupo_rejeite,
      'mantido_por', s.mantido_por,
      'mantido_at', s.mantido_at,
      'mantido_por_nome', mantenedor.nome,
      'mantido_por_email', mantenedor.email,
      'respondendo_por', s.respondendo_por,
      'respondendo_at', s.respondendo_at,
      'respondendo_por_nome', respondente.nome,
      'respondendo_por_email', respondente.email
    )
    ORDER BY s.hora_criacao DESC, s.ticket_numero
  ), '[]'::jsonb)
    INTO v_registros
  FROM public.smax_tickets_antigos_snapshot s
  LEFT JOIN public.users u ON u.id = s.user_id
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  LEFT JOIN public.users respondente ON respondente.id = s.respondendo_por
  WHERE s.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'user_id', grouped.user_id,
      'usuario_nome', grouped.usuario_nome,
      'smax_nome', grouped.smax_nome,
      'total', grouped.total,
      'hora_criacao', grouped.hora_criacao,
      'ultima_atualizacao', grouped.hora_criacao,
      'mapeado', grouped.mapeado,
      'grupo_rejeite', grouped.grupo_rejeite
    )
    ORDER BY grouped.usuario_nome, grouped.hora_criacao DESC
  ), '[]'::jsonb)
    INTO v_por_usuario
  FROM (
    SELECT
      CASE WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN NULL ELSE s.user_id END AS user_id,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE COALESCE(u.nome, s.smax_nome)
      END AS usuario_nome,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE s.smax_nome
      END AS smax_nome,
      count(*)::integer AS total,
      max(s.hora_criacao) AS hora_criacao,
      bool_and(s.mapeado) AS mapeado,
      s.grupo_rejeite
    FROM public.smax_tickets_antigos_snapshot s
    LEFT JOIN public.users u ON u.id = s.user_id
    WHERE s.equipe_id = v_equipe_id
    GROUP BY
      CASE WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN NULL ELSE s.user_id END,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE COALESCE(u.nome, s.smax_nome)
      END,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE s.smax_nome
      END,
      s.grupo_rejeite
  ) grouped;

  RETURN jsonb_build_object(
    'meta', v_meta,
    'registros', v_registros,
    'por_usuario', v_por_usuario
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_manter(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_now timestamptz := now();
  v_ticket record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Ticket obrigatorio';
  END IF;

  SELECT u.equipe_id INTO v_user_equipe_id FROM public.users u WHERE u.id = v_user_id;

  SELECT s.id,
         s.equipe_id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome AS mantido_por_nome,
         mantenedor.email AS mantido_por_email
    INTO v_ticket
  FROM public.smax_tickets_antigos_snapshot s
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.id = p_id
  FOR UPDATE OF s;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'Ticket nao encontrado';
  END IF;

  IF v_ticket.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para manter este ticket';
  END IF;

  IF v_ticket.mantido_por IS NULL THEN
    UPDATE public.smax_tickets_antigos_snapshot s
       SET mantido_por = v_user_id,
           mantido_at = v_now
     WHERE s.id = p_id
    RETURNING s.id, s.ticket_numero, s.mantido_por, s.mantido_at
      INTO v_ticket;

    RETURN jsonb_build_object(
      'success', true,
      'id', v_ticket.id,
      'ticket_numero', v_ticket.ticket_numero,
      'mantido_por', v_ticket.mantido_por,
      'mantido_at', v_ticket.mantido_at
    );
  END IF;

  IF v_ticket.mantido_por = v_user_id THEN
    RETURN jsonb_build_object(
      'success', true,
      'id', v_ticket.id,
      'ticket_numero', v_ticket.ticket_numero,
      'mantido_por', v_ticket.mantido_por,
      'mantido_at', v_ticket.mantido_at,
      'ja_mantido', true
    );
  END IF;

  RETURN jsonb_build_object(
    'success', false,
    'reason', 'mantido_por_outro',
    'id', v_ticket.id,
    'ticket_numero', v_ticket.ticket_numero,
    'mantido_por', v_ticket.mantido_por,
    'mantido_at', v_ticket.mantido_at,
    'mantido_por_nome', v_ticket.mantido_por_nome,
    'mantido_por_email', v_ticket.mantido_por_email
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_liberar(p_id uuid)
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

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Ticket obrigatorio';
  END IF;

  SELECT u.equipe_id INTO v_user_equipe_id FROM public.users u WHERE u.id = v_user_id;

  UPDATE public.smax_tickets_antigos_snapshot s
     SET mantido_por = NULL,
         mantido_at = NULL,
         respondendo_por = NULL,
         respondendo_at = NULL
   WHERE s.id = p_id
     AND s.equipe_id = v_user_equipe_id
  RETURNING s.id, s.ticket_numero
    INTO v_ticket;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'Ticket nao encontrado';
  END IF;

  RETURN jsonb_build_object('success', true, 'id', v_ticket.id, 'ticket_numero', v_ticket.ticket_numero);
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_manter_lote(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_total_solicitado integer := 0;
  v_total_alterado integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object('success', true, 'total_solicitado', 0, 'total_alterado', 0, 'total_ignorado', 0);
  END IF;

  SELECT u.equipe_id INTO v_user_equipe_id FROM public.users u WHERE u.id = v_user_id;

  WITH ids AS (
    SELECT DISTINCT unnest(p_ids) AS id
  ), solicitados AS (
    SELECT s.id
    FROM public.smax_tickets_antigos_snapshot s
    JOIN ids ON ids.id = s.id
    WHERE s.equipe_id = v_user_equipe_id
  ), alterados AS (
    UPDATE public.smax_tickets_antigos_snapshot s
       SET mantido_por = v_user_id,
           mantido_at = now()
      FROM solicitados
     WHERE s.id = solicitados.id
       AND s.mantido_por IS NULL
    RETURNING s.id
  )
  SELECT
    (SELECT count(*)::integer FROM solicitados),
    (SELECT count(*)::integer FROM alterados)
    INTO v_total_solicitado, v_total_alterado;

  RETURN jsonb_build_object(
    'success', true,
    'total_solicitado', COALESCE(v_total_solicitado, 0),
    'total_alterado', COALESCE(v_total_alterado, 0),
    'total_ignorado', GREATEST(COALESCE(v_total_solicitado, 0) - COALESCE(v_total_alterado, 0), 0)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_liberar_lote(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_total_solicitado integer := 0;
  v_total_alterado integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object('success', true, 'total_solicitado', 0, 'total_alterado', 0, 'total_ignorado', 0);
  END IF;

  SELECT u.equipe_id INTO v_user_equipe_id FROM public.users u WHERE u.id = v_user_id;

  WITH ids AS (
    SELECT DISTINCT unnest(p_ids) AS id
  ), solicitados AS (
    SELECT s.id
    FROM public.smax_tickets_antigos_snapshot s
    JOIN ids ON ids.id = s.id
    WHERE s.equipe_id = v_user_equipe_id
  ), alterados AS (
    UPDATE public.smax_tickets_antigos_snapshot s
       SET mantido_por = NULL,
           mantido_at = NULL,
           respondendo_por = NULL,
           respondendo_at = NULL
      FROM solicitados
     WHERE s.id = solicitados.id
       AND s.mantido_por IS NOT NULL
    RETURNING s.id
  )
  SELECT
    (SELECT count(*)::integer FROM solicitados),
    (SELECT count(*)::integer FROM alterados)
    INTO v_total_solicitado, v_total_alterado;

  RETURN jsonb_build_object(
    'success', true,
    'total_solicitado', COALESCE(v_total_solicitado, 0),
    'total_alterado', COALESCE(v_total_alterado, 0),
    'total_ignorado', GREATEST(COALESCE(v_total_solicitado, 0) - COALESCE(v_total_alterado, 0), 0)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_excluir(p_id uuid)
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

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Ticket obrigatorio';
  END IF;

  SELECT u.equipe_id INTO v_user_equipe_id FROM public.users u WHERE u.id = v_user_id;

  SELECT s.id,
         s.equipe_id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome AS mantido_por_nome,
         mantenedor.email AS mantido_por_email
    INTO v_ticket
  FROM public.smax_tickets_antigos_snapshot s
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.id = p_id
  FOR UPDATE OF s;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'Ticket nao encontrado';
  END IF;

  IF v_ticket.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para excluir este ticket';
  END IF;

  IF v_ticket.mantido_por IS NOT NULL AND v_ticket.mantido_por IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'mantido_por_outro',
      'id', v_ticket.id,
      'ticket_numero', v_ticket.ticket_numero,
      'mantido_por', v_ticket.mantido_por,
      'mantido_at', v_ticket.mantido_at,
      'mantido_por_nome', v_ticket.mantido_por_nome,
      'mantido_por_email', v_ticket.mantido_por_email
    );
  END IF;

  DELETE FROM public.smax_tickets_antigos_snapshot s WHERE s.id = v_ticket.id;

  RETURN jsonb_build_object('success', true, 'id', v_ticket.id, 'ticket_numero', v_ticket.ticket_numero);
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_registrar_e_excluir(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_usuario_nome text;
  v_now timestamptz := now();
  v_descricao text;
  v_servico_id uuid;
  v_ticket record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Ticket obrigatorio';
  END IF;

  SELECT u.equipe_id, COALESCE(u.nome, u.email, 'Usuario')
    INTO v_user_equipe_id, v_usuario_nome
  FROM public.users u
  WHERE u.id = v_user_id;

  SELECT s.id,
         s.equipe_id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome AS mantido_por_nome,
         mantenedor.email AS mantido_por_email
    INTO v_ticket
  FROM public.smax_tickets_antigos_snapshot s
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.id = p_id
  FOR UPDATE OF s;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'Ticket nao encontrado';
  END IF;

  IF v_ticket.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para registrar este ticket';
  END IF;

  IF v_ticket.mantido_por IS NOT NULL AND v_ticket.mantido_por IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'mantido_por_outro',
      'id', v_ticket.id,
      'ticket_numero', v_ticket.ticket_numero,
      'mantido_por', v_ticket.mantido_por,
      'mantido_at', v_ticket.mantido_at,
      'mantido_por_nome', v_ticket.mantido_por_nome,
      'mantido_por_email', v_ticket.mantido_por_email
    );
  END IF;

  v_descricao := 'Respondi ao ticket ' || v_ticket.ticket_numero;

  INSERT INTO public.servicos (
    tipo,
    quantidade,
    usuario_id,
    usuario_nome,
    equipe_id,
    observacao,
    data_execucao,
    descricao
  ) VALUES (
    'analise_chamados_antigos',
    1,
    v_user_id,
    v_usuario_nome,
    v_user_equipe_id,
    NULL,
    v_now,
    v_descricao
  )
  RETURNING id INTO v_servico_id;

  DELETE FROM public.smax_tickets_antigos_snapshot s WHERE s.id = v_ticket.id;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_ticket.id,
    'ticket_numero', v_ticket.ticket_numero,
    'servico_id', v_servico_id,
    'descricao', v_descricao,
    'data_execucao', v_now
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_excluir_lote(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_total_solicitado integer := 0;
  v_total_excluido integer := 0;
  v_total_bloqueado integer := 0;
  v_ids_excluidos jsonb := '[]'::jsonb;
  v_tickets_excluidos jsonb := '[]'::jsonb;
  v_tickets_bloqueados jsonb := '[]'::jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object('success', true, 'total_solicitado', 0, 'total_excluido', 0, 'total_bloqueado', 0, 'ids_excluidos', '[]'::jsonb, 'tickets_excluidos', '[]'::jsonb, 'tickets_bloqueados', '[]'::jsonb);
  END IF;

  SELECT u.equipe_id INTO v_user_equipe_id FROM public.users u WHERE u.id = v_user_id;

  DROP TABLE IF EXISTS pg_temp.smax_tickets_antigos_lote_solicitados;
  CREATE TEMP TABLE smax_tickets_antigos_lote_solicitados (
    id uuid PRIMARY KEY,
    ticket_numero text NOT NULL,
    mantido_por uuid,
    mantido_at timestamptz,
    mantido_por_nome text,
    mantido_por_email text
  ) ON COMMIT DROP;

  INSERT INTO pg_temp.smax_tickets_antigos_lote_solicitados (id, ticket_numero, mantido_por, mantido_at, mantido_por_nome, mantido_por_email)
  SELECT s.id, s.ticket_numero, s.mantido_por, s.mantido_at, mantenedor.nome, mantenedor.email
  FROM public.smax_tickets_antigos_snapshot s
  JOIN (
    SELECT DISTINCT input.id
    FROM unnest(p_ids) AS input(id)
    WHERE input.id IS NOT NULL
  ) ids ON ids.id = s.id
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.equipe_id = v_user_equipe_id
  FOR UPDATE OF s;

  SELECT count(*)::integer INTO v_total_solicitado FROM pg_temp.smax_tickets_antigos_lote_solicitados;

  SELECT count(*)::integer,
         COALESCE(jsonb_agg(jsonb_build_object('id', id, 'ticket_numero', ticket_numero, 'mantido_por', mantido_por, 'mantido_at', mantido_at, 'mantido_por_nome', mantido_por_nome, 'mantido_por_email', mantido_por_email) ORDER BY ticket_numero), '[]'::jsonb)
    INTO v_total_bloqueado, v_tickets_bloqueados
  FROM pg_temp.smax_tickets_antigos_lote_solicitados
  WHERE mantido_por IS NOT NULL
    AND mantido_por IS DISTINCT FROM v_user_id;

  WITH excluidos AS (
    DELETE FROM public.smax_tickets_antigos_snapshot s
    USING pg_temp.smax_tickets_antigos_lote_solicitados solicitados
    WHERE s.id = solicitados.id
      AND (solicitados.mantido_por IS NULL OR solicitados.mantido_por = v_user_id)
    RETURNING s.id, s.ticket_numero
  )
  SELECT count(*)::integer,
         COALESCE(jsonb_agg(id ORDER BY ticket_numero), '[]'::jsonb),
         COALESCE(jsonb_agg(ticket_numero ORDER BY ticket_numero), '[]'::jsonb)
    INTO v_total_excluido, v_ids_excluidos, v_tickets_excluidos
  FROM excluidos;

  RETURN jsonb_build_object(
    'success', true,
    'total_solicitado', COALESCE(v_total_solicitado, 0),
    'total_excluido', COALESCE(v_total_excluido, 0),
    'total_bloqueado', COALESCE(v_total_bloqueado, 0),
    'ids_excluidos', COALESCE(v_ids_excluidos, '[]'::jsonb),
    'tickets_excluidos', COALESCE(v_tickets_excluidos, '[]'::jsonb),
    'tickets_bloqueados', COALESCE(v_tickets_bloqueados, '[]'::jsonb)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_registrar_e_excluir_lote(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_usuario_nome text;
  v_now timestamptz := now();
  v_total_solicitado integer := 0;
  v_total_processado integer := 0;
  v_total_bloqueado integer := 0;
  v_total_deletado integer := 0;
  v_ids_processados jsonb := '[]'::jsonb;
  v_tickets_processados jsonb := '[]'::jsonb;
  v_tickets_bloqueados jsonb := '[]'::jsonb;
  v_tickets_texto text;
  v_descricao text;
  v_servico_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object('success', true, 'total_solicitado', 0, 'total_processado', 0, 'total_bloqueado', 0, 'servico_id', NULL, 'ids_processados', '[]'::jsonb, 'tickets_processados', '[]'::jsonb, 'descricao', NULL, 'data_execucao', NULL, 'tickets_bloqueados', '[]'::jsonb);
  END IF;

  SELECT u.equipe_id, COALESCE(u.nome, u.email, 'Usuario')
    INTO v_user_equipe_id, v_usuario_nome
  FROM public.users u
  WHERE u.id = v_user_id;

  DROP TABLE IF EXISTS pg_temp.smax_tickets_antigos_registrar_lote_solicitados;
  CREATE TEMP TABLE smax_tickets_antigos_registrar_lote_solicitados (
    id uuid PRIMARY KEY,
    ticket_numero text NOT NULL,
    mantido_por uuid,
    mantido_at timestamptz,
    mantido_por_nome text,
    mantido_por_email text
  ) ON COMMIT DROP;

  INSERT INTO pg_temp.smax_tickets_antigos_registrar_lote_solicitados (id, ticket_numero, mantido_por, mantido_at, mantido_por_nome, mantido_por_email)
  SELECT s.id, s.ticket_numero, s.mantido_por, s.mantido_at, mantenedor.nome, mantenedor.email
  FROM public.smax_tickets_antigos_snapshot s
  JOIN (
    SELECT DISTINCT input.id
    FROM unnest(p_ids) AS input(id)
    WHERE input.id IS NOT NULL
  ) ids ON ids.id = s.id
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.equipe_id = v_user_equipe_id
  FOR UPDATE OF s;

  SELECT count(*)::integer INTO v_total_solicitado FROM pg_temp.smax_tickets_antigos_registrar_lote_solicitados;

  SELECT count(*)::integer,
         COALESCE(jsonb_agg(jsonb_build_object('id', id, 'ticket_numero', ticket_numero, 'mantido_por', mantido_por, 'mantido_at', mantido_at, 'mantido_por_nome', mantido_por_nome, 'mantido_por_email', mantido_por_email) ORDER BY ticket_numero), '[]'::jsonb)
    INTO v_total_bloqueado, v_tickets_bloqueados
  FROM pg_temp.smax_tickets_antigos_registrar_lote_solicitados
  WHERE mantido_por IS NOT NULL
    AND mantido_por IS DISTINCT FROM v_user_id;

  SELECT count(*)::integer,
         COALESCE(jsonb_agg(id ORDER BY ticket_numero), '[]'::jsonb),
         COALESCE(jsonb_agg(ticket_numero ORDER BY ticket_numero), '[]'::jsonb),
         string_agg(ticket_numero, ', ' ORDER BY ticket_numero)
    INTO v_total_processado, v_ids_processados, v_tickets_processados, v_tickets_texto
  FROM pg_temp.smax_tickets_antigos_registrar_lote_solicitados
  WHERE mantido_por IS NULL
     OR mantido_por = v_user_id;

  IF COALESCE(v_total_processado, 0) > 0 THEN
    v_descricao := CASE
      WHEN v_total_processado = 1 THEN 'Respondi ao ticket ' || v_tickets_texto
      ELSE 'Respondi aos tickets ' || v_tickets_texto
    END;

    INSERT INTO public.servicos (tipo, quantidade, usuario_id, usuario_nome, equipe_id, observacao, data_execucao, descricao)
    VALUES ('analise_chamados_antigos', v_total_processado, v_user_id, v_usuario_nome, v_user_equipe_id, NULL, v_now, v_descricao)
    RETURNING id INTO v_servico_id;

    DELETE FROM public.smax_tickets_antigos_snapshot s
    USING pg_temp.smax_tickets_antigos_registrar_lote_solicitados solicitados
    WHERE s.id = solicitados.id
      AND (solicitados.mantido_por IS NULL OR solicitados.mantido_por = v_user_id);

    GET DIAGNOSTICS v_total_deletado = ROW_COUNT;

    IF v_total_deletado IS DISTINCT FROM v_total_processado THEN
      RAISE EXCEPTION 'Falha ao excluir todos os tickets registrados';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'total_solicitado', COALESCE(v_total_solicitado, 0),
    'total_processado', COALESCE(v_total_processado, 0),
    'total_bloqueado', COALESCE(v_total_bloqueado, 0),
    'servico_id', v_servico_id,
    'ids_processados', COALESCE(v_ids_processados, '[]'::jsonb),
    'tickets_processados', COALESCE(v_tickets_processados, '[]'::jsonb),
    'descricao', v_descricao,
    'data_execucao', CASE WHEN v_servico_id IS NULL THEN NULL ELSE v_now END,
    'tickets_bloqueados', COALESCE(v_tickets_bloqueados, '[]'::jsonb)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_marcar_respondendo(
  p_id uuid,
  p_ativo boolean DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_now timestamptz := now();
  v_ticket record;
  v_next_ativo boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Ticket obrigatorio';
  END IF;

  SELECT u.equipe_id INTO v_user_equipe_id FROM public.users u WHERE u.id = v_user_id;

  SELECT s.id,
         s.equipe_id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome AS mantido_por_nome,
         mantenedor.email AS mantido_por_email,
         s.respondendo_por,
         s.respondendo_at
    INTO v_ticket
  FROM public.smax_tickets_antigos_snapshot s
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.id = p_id
  FOR UPDATE OF s;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'Ticket nao encontrado';
  END IF;

  IF v_ticket.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para alterar este ticket';
  END IF;

  IF v_ticket.mantido_por IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'nao_mantido_pelo_usuario',
      'id', v_ticket.id,
      'ticket_numero', v_ticket.ticket_numero,
      'ativo', false,
      'mantido_por', v_ticket.mantido_por,
      'mantido_at', v_ticket.mantido_at,
      'mantido_por_nome', v_ticket.mantido_por_nome,
      'mantido_por_email', v_ticket.mantido_por_email,
      'respondendo_por', v_ticket.respondendo_por,
      'respondendo_at', v_ticket.respondendo_at
    );
  END IF;

  v_next_ativo := COALESCE(p_ativo, v_ticket.respondendo_por IS DISTINCT FROM v_user_id);

  UPDATE public.smax_tickets_antigos_snapshot s
     SET respondendo_por = CASE WHEN v_next_ativo THEN v_user_id ELSE NULL END,
         respondendo_at = CASE WHEN v_next_ativo THEN v_now ELSE NULL END
   WHERE s.id = v_ticket.id
  RETURNING s.id, s.ticket_numero, s.respondendo_por, s.respondendo_at
    INTO v_ticket;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_ticket.id,
    'ticket_numero', v_ticket.ticket_numero,
    'ativo', v_next_ativo,
    'respondendo_por', v_ticket.respondendo_por,
    'respondendo_at', v_ticket.respondendo_at
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_salvar_snapshot(uuid, jsonb, timestamptz, jsonb, jsonb) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_listar(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_manter(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_liberar(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_manter_lote(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_liberar_lote(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_excluir(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_registrar_e_excluir(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_excluir_lote(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_registrar_e_excluir_lote(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_marcar_respondendo(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_salvar_snapshot(uuid, jsonb, timestamptz, jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_listar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_manter(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_liberar(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_manter_lote(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_liberar_lote(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_excluir(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_registrar_e_excluir(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_excluir_lote(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_registrar_e_excluir_lote(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_marcar_respondendo(uuid, boolean) TO authenticated;
ALTER TABLE public.smax_tickets_antigos_snapshot REPLICA IDENTITY FULL;
ALTER TABLE public.smax_tickets_antigos_snapshot_meta REPLICA IDENTITY FULL;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.smax_tickets_antigos_snapshot;
EXCEPTION WHEN duplicate_object OR undefined_object THEN
  NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.smax_tickets_antigos_snapshot_meta;
EXCEPTION WHEN duplicate_object OR undefined_object THEN
  NULL;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;

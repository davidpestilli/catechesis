-- =====================================================================
-- SMAX Rejeites - Marcador persistente de ticket em resposta
-- Adiciona um estado por ticket para indicar qual chamado o usuario esta
-- respondendo apos abrir o SMAX. O marcador so pode ser ativado quando o
-- ticket esta mantido pelo proprio usuario.
-- =====================================================================

BEGIN;
ALTER TABLE public.smax_rejeites_snapshot
  ADD COLUMN IF NOT EXISTS respondendo_por uuid REFERENCES public.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS respondendo_at timestamptz;
UPDATE public.smax_rejeites_snapshot
   SET respondendo_por = NULL,
       respondendo_at = NULL
 WHERE respondendo_por IS NOT NULL
   AND (
     mantido_por IS NULL
     OR respondendo_por IS DISTINCT FROM mantido_por
   );
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'smax_rejeites_snapshot_respondendo_mantido_check'
      AND conrelid = 'public.smax_rejeites_snapshot'::regclass
  ) THEN
    ALTER TABLE public.smax_rejeites_snapshot
      ADD CONSTRAINT smax_rejeites_snapshot_respondendo_mantido_check
      CHECK (respondendo_por IS NULL OR respondendo_por = mantido_por);
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_smax_rejeites_snapshot_equipe_respondendo
  ON public.smax_rejeites_snapshot(equipe_id, respondendo_por, respondendo_at DESC)
  WHERE respondendo_por IS NOT NULL;
CREATE OR REPLACE FUNCTION public.smax_rejeites_salvar_snapshot(
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
  v_total_mapeado integer := 0;
  v_total_externo_sem_usuario integer := 0;
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

  IF NOT public.tem_permissao('distribuidor.smax_rejeites_robo_dev') THEN
    RAISE EXCEPTION 'Usuario sem permissao para executar o robo SMAX Rejeites';
  END IF;

  DROP TABLE IF EXISTS pg_temp.smax_rejeites_hold_cache;
  CREATE TEMP TABLE smax_rejeites_hold_cache ON COMMIT DROP AS
  SELECT s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         s.respondendo_por,
         s.respondendo_at
  FROM public.smax_rejeites_snapshot s
  WHERE s.equipe_id = p_equipe_id
    AND (
      s.mantido_por IS NOT NULL
      OR s.respondendo_por IS NOT NULL
    );

  DELETE FROM public.smax_rejeites_snapshot s
  WHERE s.equipe_id = p_equipe_id;

  WITH entrada_raw AS (
    SELECT item
    FROM jsonb_array_elements(p_registros) AS raw(item)
  ), entrada AS (
    SELECT DISTINCT ON (ticket_numero)
      regexp_replace(COALESCE(
        item->>'ticket_numero',
        item->>'ticketNumero',
        item->>'id',
        ''
      ), '[^0-9]', '', 'g') AS ticket_numero,
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
      NULLIF(trim(COALESCE(item->>'ultima_atualizacao', item->>'ultimaAtualizacao', '')), '')::timestamptz AS ultima_atualizacao,
      NULLIF(trim(COALESCE(item->>'smax_url', item->>'smaxUrl', '')), '') AS smax_url
    FROM entrada_raw
    ORDER BY ticket_numero, NULLIF(trim(COALESCE(item->>'ultima_atualizacao', item->>'ultimaAtualizacao', '')), '')::timestamptz DESC NULLS LAST
  ), validos AS (
    SELECT
      ticket_numero,
      smax_nome_original,
      smax_nome_key,
      smax_person_id,
      ultima_atualizacao,
      COALESCE(smax_url, 'https://suporte.tjsp.jus.br/saw/Request/' || ticket_numero) AS smax_url
    FROM entrada
    WHERE ticket_numero <> ''
      AND ultima_atualizacao IS NOT NULL
  ), resolvidos AS (
    SELECT DISTINCT ON (v.ticket_numero)
      v.ticket_numero,
      v.ultima_atualizacao,
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
       (
         v.smax_nome_key IS NOT NULL
         AND m.smax_nome_key = v.smax_nome_key
       )
       OR (
         v.smax_person_id IS NOT NULL
         AND m.smax_person_id IS NOT NULL
         AND m.smax_person_id = v.smax_person_id
       )
     )
    ORDER BY v.ticket_numero, (m.id IS NULL), m.user_id NULLS LAST
  ), inseridos AS (
    INSERT INTO public.smax_rejeites_snapshot (
      equipe_id,
      user_id,
      map_id,
      smax_nome,
      smax_nome_key,
      smax_nome_original,
      ticket_numero,
      ultima_atualizacao,
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
      r.ultima_atualizacao,
      r.smax_url,
      COALESCE(p_pesquisado_em, now()),
      r.mapeado,
      r.grupo_rejeite,
      h.mantido_por,
      h.mantido_at,
      CASE
        WHEN h.mantido_por IS NOT NULL
         AND h.respondendo_por = h.mantido_por
        THEN h.respondendo_por
        ELSE NULL
      END,
      CASE
        WHEN h.mantido_por IS NOT NULL
         AND h.respondendo_por = h.mantido_por
        THEN h.respondendo_at
        ELSE NULL
      END
    FROM resolvidos r
    LEFT JOIN pg_temp.smax_rejeites_hold_cache h
      ON h.ticket_numero = r.ticket_numero
    ON CONFLICT (equipe_id, ticket_numero) DO UPDATE
    SET user_id = EXCLUDED.user_id,
        map_id = EXCLUDED.map_id,
        smax_nome = EXCLUDED.smax_nome,
        smax_nome_key = EXCLUDED.smax_nome_key,
        smax_nome_original = EXCLUDED.smax_nome_original,
        ultima_atualizacao = EXCLUDED.ultima_atualizacao,
        smax_url = EXCLUDED.smax_url,
        capturado_em = EXCLUDED.capturado_em,
        mapeado = EXCLUDED.mapeado,
        grupo_rejeite = EXCLUDED.grupo_rejeite,
        mantido_por = EXCLUDED.mantido_por,
        mantido_at = EXCLUDED.mantido_at,
        respondendo_por = EXCLUDED.respondendo_por,
        respondendo_at = EXCLUDED.respondendo_at
    RETURNING mapeado
  )
  SELECT
    (SELECT count(*)::integer FROM validos),
    (SELECT count(*)::integer FROM inseridos),
    (SELECT count(*)::integer FROM inseridos WHERE mapeado = true),
    (SELECT count(*)::integer FROM inseridos WHERE mapeado = false)
    INTO v_total_extraido, v_total_salvo, v_total_mapeado, v_total_externo_sem_usuario;

  v_total_ignorado := GREATEST(COALESCE(v_total_extraido, 0) - COALESCE(v_total_salvo, 0), 0);

  INSERT INTO public.smax_rejeites_snapshot_meta (
    equipe_id,
    pesquisado_em,
    total_extraido,
    total_mapeado,
    total_ignorado,
    total_externo_sem_usuario,
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
    COALESCE(v_total_ignorado, 0),
    COALESCE(v_total_externo_sem_usuario, 0),
    v_user_id,
    COALESCE(p_avisos, '[]'::jsonb),
    COALESCE(p_detalhes, '{}'::jsonb),
    now()
  )
  ON CONFLICT (equipe_id) DO UPDATE
  SET pesquisado_em = EXCLUDED.pesquisado_em,
      total_extraido = EXCLUDED.total_extraido,
      total_mapeado = EXCLUDED.total_mapeado,
      total_ignorado = EXCLUDED.total_ignorado,
      total_externo_sem_usuario = EXCLUDED.total_externo_sem_usuario,
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
    'total_ignorado', COALESCE(v_total_ignorado, 0)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_rejeites_listar(p_equipe_id uuid DEFAULT NULL)
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
  FROM public.smax_rejeites_snapshot_meta m
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
      'ultima_atualizacao', s.ultima_atualizacao,
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
    ORDER BY s.ultima_atualizacao DESC, s.ticket_numero
  ), '[]'::jsonb)
    INTO v_registros
  FROM public.smax_rejeites_snapshot s
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
      'ultima_atualizacao', grouped.ultima_atualizacao,
      'mapeado', grouped.mapeado,
      'grupo_rejeite', grouped.grupo_rejeite
    )
    ORDER BY grouped.usuario_nome, grouped.ultima_atualizacao DESC
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
      max(s.ultima_atualizacao) AS ultima_atualizacao,
      bool_and(s.mapeado) AS mapeado,
      s.grupo_rejeite
    FROM public.smax_rejeites_snapshot s
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
CREATE OR REPLACE FUNCTION public.smax_rejeites_liberar(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_rejeite record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Rejeite obrigatorio';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  UPDATE public.smax_rejeites_snapshot s
     SET mantido_por = NULL,
         mantido_at = NULL,
         respondendo_por = NULL,
         respondendo_at = NULL
   WHERE s.id = p_id
     AND s.equipe_id = v_user_equipe_id
  RETURNING s.id, s.ticket_numero
    INTO v_rejeite;

  IF v_rejeite.id IS NULL THEN
    RAISE EXCEPTION 'Rejeite nao encontrado';
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_rejeite.id,
    'ticket_numero', v_rejeite.ticket_numero
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_rejeites_liberar_lote(p_ids uuid[])
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

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  WITH ids AS (
    SELECT DISTINCT unnest(p_ids) AS id
  ), solicitados AS (
    SELECT s.id
    FROM public.smax_rejeites_snapshot s
    JOIN ids ON ids.id = s.id
    WHERE s.equipe_id = v_user_equipe_id
  ), alterados AS (
    UPDATE public.smax_rejeites_snapshot s
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
CREATE OR REPLACE FUNCTION public.smax_rejeites_marcar_respondendo(
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
  v_rejeite record;
  v_next_ativo boolean;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Rejeite obrigatorio';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  IF v_user_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao encontrado ou sem equipe';
  END IF;

  SELECT s.id,
         s.equipe_id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome AS mantido_por_nome,
         mantenedor.email AS mantido_por_email,
         s.respondendo_por,
         s.respondendo_at
    INTO v_rejeite
  FROM public.smax_rejeites_snapshot s
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.id = p_id
  FOR UPDATE OF s;

  IF v_rejeite.id IS NULL THEN
    RAISE EXCEPTION 'Rejeite nao encontrado';
  END IF;

  IF v_rejeite.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para alterar este rejeite';
  END IF;

  IF v_rejeite.mantido_por IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'nao_mantido_pelo_usuario',
      'id', v_rejeite.id,
      'ticket_numero', v_rejeite.ticket_numero,
      'ativo', false,
      'mantido_por', v_rejeite.mantido_por,
      'mantido_at', v_rejeite.mantido_at,
      'mantido_por_nome', v_rejeite.mantido_por_nome,
      'mantido_por_email', v_rejeite.mantido_por_email,
      'respondendo_por', v_rejeite.respondendo_por,
      'respondendo_at', v_rejeite.respondendo_at
    );
  END IF;

  v_next_ativo := COALESCE(p_ativo, v_rejeite.respondendo_por IS DISTINCT FROM v_user_id);

  UPDATE public.smax_rejeites_snapshot s
     SET respondendo_por = CASE WHEN v_next_ativo THEN v_user_id ELSE NULL END,
         respondendo_at = CASE WHEN v_next_ativo THEN v_now ELSE NULL END
   WHERE s.id = v_rejeite.id
  RETURNING s.id, s.ticket_numero, s.respondendo_por, s.respondendo_at
    INTO v_rejeite;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_rejeite.id,
    'ticket_numero', v_rejeite.ticket_numero,
    'ativo', v_next_ativo,
    'respondendo_por', v_rejeite.respondendo_por,
    'respondendo_at', v_rejeite.respondendo_at
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_rejeites_marcar_respondendo(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_marcar_respondendo(uuid, boolean) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

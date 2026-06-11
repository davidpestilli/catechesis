-- =====================================================================
-- SMAX Rejeites - Preservar tickets mantidos ao salvar snapshot
-- Salvar Snapshot deixa de fazer purge destrutivo de toda a equipe:
-- tickets mantidos por qualquer usuario sobrevivem ao purge, e tickets
-- mantidos que reaparecem na nova pesquisa sao atualizados por upsert.
-- =====================================================================

BEGIN;
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
  v_total_processado integer := 0;
  v_total_salvo integer := 0;
  v_total_mapeado integer := 0;
  v_total_externo_sem_usuario integer := 0;
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

  SELECT count(*)::integer
    INTO v_total_preservado_mantido
  FROM public.smax_rejeites_snapshot s
  WHERE s.equipe_id = p_equipe_id
    AND s.mantido_por IS NOT NULL;

  DELETE FROM public.smax_rejeites_snapshot s
  WHERE s.equipe_id = p_equipe_id
    AND s.mantido_por IS NULL;

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
    RETURNING id
  )
  SELECT
    (SELECT count(*)::integer FROM validos),
    (SELECT count(*)::integer FROM inseridos)
    INTO v_total_extraido, v_total_processado;

  SELECT count(*)::integer,
         count(*) FILTER (WHERE s.mapeado = true)::integer,
         count(*) FILTER (WHERE s.mapeado = false)::integer
    INTO v_total_salvo,
         v_total_mapeado,
         v_total_externo_sem_usuario
  FROM public.smax_rejeites_snapshot s
  WHERE s.equipe_id = p_equipe_id;

  v_total_ignorado := GREATEST(COALESCE(v_total_extraido, 0) - COALESCE(v_total_processado, 0), 0);

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
    'total_ignorado', COALESCE(v_total_ignorado, 0),
    'total_preservado_mantido', COALESCE(v_total_preservado_mantido, 0)
  );
END;
$$;
NOTIFY pgrst, 'reload schema';
COMMIT;

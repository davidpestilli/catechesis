-- ============================================================
-- Migracao: Sistema Solar - filtro por tempo de espera
-- Data: 2026-05-24
--
-- Objetivo:
--   Permitir que a etapa de planetas recorte os tickets candidatos por
--   faixa ou dia exato de espera antes da clusterizacao semantica.
--   O modo padrao continua sendo "todos" para preservar o comportamento
--   atual ate que o usuario escolha deliberadamente um recorte.
-- ============================================================

SET search_path TO public, extensions;
ALTER TABLE public.ticket_clusters
  ADD COLUMN IF NOT EXISTS tempo_espera_filtro jsonb;
UPDATE public.ticket_clusters
SET tempo_espera_filtro = '{"modo":"todos","label":"Todos"}'::jsonb
WHERE tempo_espera_filtro IS NULL;
ALTER TABLE public.ticket_clusters
  ALTER COLUMN tempo_espera_filtro SET DEFAULT '{"modo":"todos","label":"Todos"}'::jsonb,
  ALTER COLUMN tempo_espera_filtro SET NOT NULL;
COMMENT ON COLUMN public.ticket_clusters.tempo_espera_filtro IS
  'Filtro de tempo de espera usado na recomputacao compartilhada do Sistema Solar.';
ALTER TABLE public.ticket_cluster_workflows
  ADD COLUMN IF NOT EXISTS tempo_espera_filtro jsonb;
UPDATE public.ticket_cluster_workflows
SET tempo_espera_filtro = '{"modo":"todos","label":"Todos"}'::jsonb
WHERE tempo_espera_filtro IS NULL;
ALTER TABLE public.ticket_cluster_workflows
  ALTER COLUMN tempo_espera_filtro SET DEFAULT '{"modo":"todos","label":"Todos"}'::jsonb,
  ALTER COLUMN tempo_espera_filtro SET NOT NULL;
COMMENT ON COLUMN public.ticket_cluster_workflows.tempo_espera_filtro IS
  'Filtro de tempo de espera exibido durante o workflow compartilhado do Sistema Solar.';
DO $$
DECLARE
  v_function_sql text;
  v_after_threshold text := $tempo$
  v_tempo_espera_modo := lower(btrim(coalesce(p_tempo_espera_modo, 'todos')));

  IF v_tempo_espera_modo IN ('', 'todos', 'todas') THEN
    v_tempo_espera_modo := 'todos';
  ELSIF v_tempo_espera_modo = 'faixas' THEN
    v_tempo_espera_modo := 'faixa';
  ELSIF v_tempo_espera_modo = 'dias' THEN
    v_tempo_espera_modo := 'dia';
  END IF;

  IF v_tempo_espera_modo NOT IN ('todos', 'faixa', 'dia') THEN
    RAISE EXCEPTION 'Modo de tempo de espera invalido: %', p_tempo_espera_modo;
  END IF;

  IF v_tempo_espera_modo = 'faixa' THEN
    v_tempo_espera_bucket_id := lower(btrim(coalesce(p_tempo_espera_bucket_id, '')));

    CASE v_tempo_espera_bucket_id
      WHEN 'ate_24h' THEN
        v_tempo_espera_label := 'ate 24h';
        v_tempo_espera_horas_min := 0;
        v_tempo_espera_horas_max := 24;
      WHEN '24_48h' THEN
        v_tempo_espera_label := '24h - 48h';
        v_tempo_espera_horas_min := 24;
        v_tempo_espera_horas_max := 48;
      WHEN '48_72h' THEN
        v_tempo_espera_label := '48h - 72h';
        v_tempo_espera_horas_min := 48;
        v_tempo_espera_horas_max := 72;
      WHEN '72_168h' THEN
        v_tempo_espera_label := '3 - 7 dias';
        v_tempo_espera_horas_min := 72;
        v_tempo_espera_horas_max := 168;
      WHEN 'acima_168h' THEN
        v_tempo_espera_label := 'mais de 7 dias';
        v_tempo_espera_horas_min := 168;
        v_tempo_espera_horas_max := NULL;
      ELSE
        RAISE EXCEPTION 'Faixa de tempo de espera invalida: %', p_tempo_espera_bucket_id;
    END CASE;
  ELSIF v_tempo_espera_modo = 'dia' THEN
    IF p_tempo_espera_dia IS NULL OR p_tempo_espera_dia < 0 THEN
      RAISE EXCEPTION 'Dia de espera invalido: %', p_tempo_espera_dia;
    END IF;

    v_tempo_espera_dia := p_tempo_espera_dia;
    v_tempo_espera_label := CASE
      WHEN v_tempo_espera_dia = 0 THEN '0 dias'
      WHEN v_tempo_espera_dia = 1 THEN '1 dia'
      ELSE v_tempo_espera_dia::text || ' dias'
    END;
  ELSE
    v_tempo_espera_bucket_id := NULL;
    v_tempo_espera_dia := NULL;
    v_tempo_espera_label := 'Todos';
    v_tempo_espera_horas_min := NULL;
    v_tempo_espera_horas_max := NULL;
  END IF;

  v_tempo_espera_filtro := jsonb_build_object(
    'modo', v_tempo_espera_modo,
    'bucket_id', v_tempo_espera_bucket_id,
    'dia', v_tempo_espera_dia,
    'label', v_tempo_espera_label,
    'horas_min', v_tempo_espera_horas_min,
    'horas_max', v_tempo_espera_horas_max
  );
$tempo$;
BEGIN
  IF to_regprocedure('public.cluster_tickets_equipe(uuid, real, integer, integer, integer, text, text, integer)') IS NOT NULL THEN
    RAISE NOTICE 'cluster_tickets_equipe ja possui filtro por tempo de espera; nenhuma alteracao necessaria.';
    RETURN;
  END IF;

  IF to_regprocedure('public.cluster_tickets_equipe(uuid, real, integer, integer, integer)') IS NULL THEN
    RAISE EXCEPTION 'Funcao public.cluster_tickets_equipe(uuid, real, integer, integer, integer) nao encontrada';
  END IF;

  SELECT pg_get_functiondef('public.cluster_tickets_equipe(uuid, real, integer, integer, integer)'::regprocedure)
  INTO v_function_sql;

  v_function_sql := regexp_replace(
    v_function_sql,
    'CREATE OR REPLACE FUNCTION public\.cluster_tickets_equipe\(([^)]*p_max_satelites integer DEFAULT 120)\)',
    'CREATE OR REPLACE FUNCTION public.cluster_tickets_equipe(\1, p_tempo_espera_modo text DEFAULT ''todos''::text, p_tempo_espera_bucket_id text DEFAULT NULL::text, p_tempo_espera_dia integer DEFAULT NULL::integer)'
  );

  v_function_sql := replace(
    v_function_sql,
    $old$  v_min_regular_satelites integer := 3;
BEGIN$old$,
    $new$  v_min_regular_satelites integer := 3;
  v_tempo_espera_modo text := 'todos';
  v_tempo_espera_bucket_id text := NULL;
  v_tempo_espera_dia integer := NULL;
  v_tempo_espera_label text := 'Todos';
  v_tempo_espera_horas_min numeric := NULL;
  v_tempo_espera_horas_max numeric := NULL;
  v_tempo_espera_filtro jsonb := '{"modo":"todos","label":"Todos"}'::jsonb;
BEGIN$new$
  );

  IF position($old$  v_threshold := LEAST(0.97::real, GREATEST(0.50::real, p_threshold::real));$old$ IN v_function_sql) > 0 THEN
    v_function_sql := replace(
      v_function_sql,
      $old$  v_threshold := LEAST(0.97::real, GREATEST(0.50::real, p_threshold::real));$old$,
      $new$  v_threshold := LEAST(0.97::real, GREATEST(0.50::real, p_threshold::real));
$new$ || v_after_threshold
    );
  ELSIF position($old$  v_threshold := LEAST(0.97::real, GREATEST(0.88::real, p_threshold::real));$old$ IN v_function_sql) > 0 THEN
    v_function_sql := replace(
      v_function_sql,
      $old$  v_threshold := LEAST(0.97::real, GREATEST(0.88::real, p_threshold::real));$old$,
      $new$  v_threshold := LEAST(0.97::real, GREATEST(0.88::real, p_threshold::real));
$new$ || v_after_threshold
    );
  ELSE
    RAISE EXCEPTION 'Linha de threshold de cluster_tickets_equipe nao encontrada';
  END IF;

  v_function_sql := replace(
    v_function_sql,
    $old$      AND t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND t.mantido_por IS NULL
      AND NULLIF(BTRIM(t.descricao), '') IS NOT NULL$old$,
    $new$      AND t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND COALESCE(t.suspenso, false) = false
      AND t.mantido_por IS NULL
      AND (
        v_tempo_espera_modo = 'todos'
        OR (
          t.tempo_espera_origem IS NOT NULL
          AND (
            (
              v_tempo_espera_modo = 'faixa'
              AND GREATEST(0::numeric, EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600.0) >= v_tempo_espera_horas_min
              AND (
                v_tempo_espera_horas_max IS NULL
                OR GREATEST(0::numeric, EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600.0) < v_tempo_espera_horas_max
              )
            )
            OR (
              v_tempo_espera_modo = 'dia'
              AND GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 86400.0)::integer) = v_tempo_espera_dia
            )
          )
        )
      )
      AND NULLIF(BTRIM(t.descricao), '') IS NOT NULL$new$
  );

  v_function_sql := replace(
    v_function_sql,
    $old$        algoritmo_versao, threshold, resumo_status$old$,
    $new$        algoritmo_versao, threshold, resumo_status, tempo_espera_filtro$new$
  );

  v_function_sql := replace(
    v_function_sql,
    $old$        g.threshold_usado,
        'pendente'$old$,
    $new$        g.threshold_usado,
        'pendente',
        v_tempo_espera_filtro$new$
  );

  v_function_sql := replace(
    v_function_sql,
    $old$      'threshold_coesao', v_threshold,
      'algoritmo',$old$,
    $new$      'threshold_coesao', v_threshold,
      'tempo_espera_filtro', v_tempo_espera_filtro,
      'algoritmo',$new$
  );

  IF position('p_tempo_espera_modo' IN v_function_sql) = 0
     OR position('v_tempo_espera_filtro' IN v_function_sql) = 0
     OR position('tempo_espera_filtro' IN v_function_sql) = 0
     OR position('v_tempo_espera_modo = ''todos''' IN v_function_sql) = 0 THEN
    RAISE EXCEPTION 'Falha ao preparar cluster_tickets_equipe com filtro de tempo de espera';
  END IF;

  EXECUTE v_function_sql;

  DROP FUNCTION IF EXISTS public.cluster_tickets_equipe(uuid, real, integer, integer, integer);
END;
$$;
DO $$
DECLARE
  v_function_sql text;
BEGIN
  SELECT pg_get_functiondef('public.cluster_tickets_equipe(uuid, real, integer, integer, integer, text, text, integer)'::regprocedure)
  INTO v_function_sql;

  v_function_sql := replace(
    v_function_sql,
    $old$    'threshold_coesao', v_threshold,
    'algoritmo',$old$,
    $new$    'threshold_coesao', v_threshold,
    'tempo_espera_filtro', v_tempo_espera_filtro,
    'algoritmo',$new$
  );

  v_function_sql := replace(
    v_function_sql,
    $old$      'threshold_coesao', v_threshold,
      'algoritmo',$old$,
    $new$      'threshold_coesao', v_threshold,
      'tempo_espera_filtro', v_tempo_espera_filtro,
      'algoritmo',$new$
  );

  v_function_sql := replace(
    v_function_sql,
    $old$        'threshold_coesao', v_threshold,
        'algoritmo',$old$,
    $new$        'threshold_coesao', v_threshold,
        'tempo_espera_filtro', v_tempo_espera_filtro,
        'algoritmo',$new$
  );

  v_function_sql := replace(
    v_function_sql,
    $old$        algoritmo_versao, threshold, resumo_status
      )$old$,
    $new$        algoritmo_versao, threshold, resumo_status, tempo_espera_filtro
      )$new$
  );

  v_function_sql := replace(
    v_function_sql,
    $old$      g.threshold_usado,
      'pendente'
      FROM grupos g$old$,
    $new$      g.threshold_usado,
      'pendente',
      v_tempo_espera_filtro
      FROM grupos g$new$
  );

  v_function_sql := regexp_replace(
    v_function_sql,
    $pattern$(algoritmo_versao, threshold, resumo_status)([[:space:]]*\))$pattern$,
    $replacement$\1, tempo_espera_filtro\2$replacement$,
    'g'
  );

  v_function_sql := regexp_replace(
    v_function_sql,
    $pattern$(g\.threshold_usado,[[:space:]]*'pendente')([[:space:]]*FROM grupos g)$pattern$,
    $replacement$\1,
      v_tempo_espera_filtro\2$replacement$,
    'g'
  );

  EXECUTE v_function_sql;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer, text, text, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer, text, text, integer) IS
  'Agrupa tickets livres no Sistema Solar, opcionalmente recortando candidatos por faixa ou dia exato de tempo de espera.';
DROP FUNCTION IF EXISTS public.cluster_tickets_listar(uuid);
CREATE OR REPLACE FUNCTION public.cluster_tickets_listar(p_equipe_id uuid)
RETURNS TABLE(
  id uuid,
  problema_comum text,
  resumo_curto text,
  confianca smallint,
  total_satelites integer,
  total_livres_agora integer,
  categorias jsonb,
  subcategorias jsonb,
  gses jsonb,
  centroid_ticket_id uuid,
  resumo_status text,
  threshold real,
  tempo_espera_filtro jsonb,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    c.problema_comum,
    c.resumo_curto,
    c.confianca,
    (SELECT count(*)::int
       FROM public.ticket_cluster_membros m
       JOIN public.tickets t ON t.id = m.ticket_id
       WHERE m.cluster_id = c.id
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false),
    (SELECT count(*)::int
       FROM public.ticket_cluster_membros m
       JOIN public.tickets t ON t.id = m.ticket_id
       WHERE m.cluster_id = c.id
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND t.mantido_por IS NULL),
    c.categorias,
    c.subcategorias,
    c.gses,
    c.centroid_ticket_id,
    c.resumo_status,
    c.threshold,
    COALESCE(c.tempo_espera_filtro, '{"modo":"todos","label":"Todos"}'::jsonb),
    c.updated_at
  FROM public.ticket_clusters c
  WHERE c.equipe_id = p_equipe_id
  ORDER BY c.updated_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_listar(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.cluster_tickets_workflow_obter(p_equipe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_workflow public.ticket_cluster_workflows%ROWTYPE;
BEGIN
  SELECT *
  INTO v_workflow
  FROM public.ticket_cluster_workflows
  WHERE equipe_id = p_equipe_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'equipe_id', p_equipe_id,
      'workflow_id', NULL,
      'owner_user_id', NULL,
      'owner_nome', NULL,
      'owner_email', NULL,
      'stage', 'idle',
      'threshold_planetas', NULL,
      'threshold_estrelas', NULL,
      'tempo_espera_filtro', '{"modo":"todos","label":"Todos"}'::jsonb,
      'started_at', NULL,
      'expires_at', NULL,
      'updated_at', NULL,
      'is_active', false
    );
  END IF;

  RETURN jsonb_build_object(
    'equipe_id', v_workflow.equipe_id,
    'workflow_id', v_workflow.workflow_id,
    'owner_user_id', v_workflow.owner_user_id,
    'owner_nome', v_workflow.owner_nome,
    'owner_email', v_workflow.owner_email,
    'stage', v_workflow.stage,
    'threshold_planetas', v_workflow.threshold_planetas,
    'threshold_estrelas', v_workflow.threshold_estrelas,
    'tempo_espera_filtro', COALESCE(v_workflow.tempo_espera_filtro, '{"modo":"todos","label":"Todos"}'::jsonb),
    'started_at', v_workflow.started_at,
    'expires_at', v_workflow.expires_at,
    'updated_at', v_workflow.updated_at,
    'is_active', v_workflow.stage <> 'idle' AND v_workflow.expires_at IS NOT NULL AND v_workflow.expires_at > now()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_workflow_obter(uuid) TO authenticated;
DROP FUNCTION IF EXISTS public.cluster_tickets_workflow_set_stage(uuid, text, uuid, real, real);
CREATE OR REPLACE FUNCTION public.cluster_tickets_workflow_set_stage(
  p_equipe_id uuid,
  p_stage text,
  p_workflow_id uuid DEFAULT NULL,
  p_threshold_planetas real DEFAULT NULL,
  p_threshold_estrelas real DEFAULT NULL,
  p_tempo_espera_filtro jsonb DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_nome text;
  v_user_email text;
  v_lock_key bigint;
  v_workflow public.ticket_cluster_workflows%ROWTYPE;
  v_tempo_espera_filtro jsonb := COALESCE(p_tempo_espera_filtro, '{"modo":"todos","label":"Todos"}'::jsonb);
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado';
  END IF;

  IF p_stage IS NULL OR p_stage NOT IN (
    'computando_planetas',
    'aguardando_resumo',
    'gerando_resumos',
    'aguardando_estrelas',
    'computando_estrelas'
  ) THEN
    RAISE EXCEPTION 'Etapa de workflow inválida: %', COALESCE(p_stage, '<null>');
  END IF;

  IF jsonb_typeof(v_tempo_espera_filtro) IS DISTINCT FROM 'object' THEN
    v_tempo_espera_filtro := '{"modo":"todos","label":"Todos"}'::jsonb;
  END IF;

  SELECT u.nome, u.email
  INTO v_user_nome, v_user_email
  FROM public.users u
  WHERE u.id = v_user_id;

  v_lock_key := ('x' || substr(md5('cluster-workflow:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  INSERT INTO public.ticket_cluster_workflows (equipe_id)
  VALUES (p_equipe_id)
  ON CONFLICT (equipe_id) DO NOTHING;

  UPDATE public.ticket_cluster_workflows
  SET workflow_id = gen_random_uuid(),
      owner_user_id = NULL,
      owner_nome = NULL,
      owner_email = NULL,
      stage = 'idle',
      threshold_planetas = NULL,
      threshold_estrelas = NULL,
      tempo_espera_filtro = '{"modo":"todos","label":"Todos"}'::jsonb,
      started_at = NULL,
      expires_at = NULL,
      updated_at = now()
  WHERE equipe_id = p_equipe_id
    AND stage <> 'idle'
    AND expires_at IS NOT NULL
    AND expires_at <= now();

  SELECT *
  INTO v_workflow
  FROM public.ticket_cluster_workflows
  WHERE equipe_id = p_equipe_id
  FOR UPDATE;

  IF v_workflow.stage = 'idle' THEN
    UPDATE public.ticket_cluster_workflows
    SET workflow_id = gen_random_uuid(),
        owner_user_id = v_user_id,
        owner_nome = v_user_nome,
        owner_email = v_user_email,
        stage = p_stage,
        threshold_planetas = COALESCE(p_threshold_planetas, threshold_planetas),
        threshold_estrelas = COALESCE(p_threshold_estrelas, threshold_estrelas),
        tempo_espera_filtro = COALESCE(p_tempo_espera_filtro, tempo_espera_filtro, '{"modo":"todos","label":"Todos"}'::jsonb),
        started_at = now(),
        expires_at = now() + interval '3 minutes',
        updated_at = now()
    WHERE equipe_id = p_equipe_id
    RETURNING * INTO v_workflow;
  ELSIF v_workflow.owner_user_id = v_user_id THEN
    IF p_workflow_id IS NOT NULL AND v_workflow.workflow_id IS DISTINCT FROM p_workflow_id THEN
      RAISE EXCEPTION 'Fluxo do Sistema Solar foi renovado ou expirou nesta sessão.';
    END IF;

    UPDATE public.ticket_cluster_workflows
    SET stage = p_stage,
        threshold_planetas = COALESCE(p_threshold_planetas, threshold_planetas),
        threshold_estrelas = COALESCE(p_threshold_estrelas, threshold_estrelas),
        tempo_espera_filtro = COALESCE(p_tempo_espera_filtro, tempo_espera_filtro, '{"modo":"todos","label":"Todos"}'::jsonb),
        updated_at = now()
    WHERE equipe_id = p_equipe_id
    RETURNING * INTO v_workflow;
  ELSE
    RAISE EXCEPTION 'Sistema Solar em uso por % até %.', COALESCE(v_workflow.owner_nome, 'outro usuário'), to_char(v_workflow.expires_at, 'HH24:MI:SS');
  END IF;

  RETURN jsonb_build_object(
    'equipe_id', v_workflow.equipe_id,
    'workflow_id', v_workflow.workflow_id,
    'owner_user_id', v_workflow.owner_user_id,
    'owner_nome', v_workflow.owner_nome,
    'owner_email', v_workflow.owner_email,
    'stage', v_workflow.stage,
    'threshold_planetas', v_workflow.threshold_planetas,
    'threshold_estrelas', v_workflow.threshold_estrelas,
    'tempo_espera_filtro', COALESCE(v_workflow.tempo_espera_filtro, '{"modo":"todos","label":"Todos"}'::jsonb),
    'started_at', v_workflow.started_at,
    'expires_at', v_workflow.expires_at,
    'updated_at', v_workflow.updated_at,
    'is_active', v_workflow.stage <> 'idle' AND v_workflow.expires_at IS NOT NULL AND v_workflow.expires_at > now()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_workflow_set_stage(uuid, text, uuid, real, real, jsonb) TO authenticated;
CREATE OR REPLACE FUNCTION public.cluster_tickets_workflow_liberar(
  p_equipe_id uuid,
  p_workflow_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_lock_key bigint;
  v_workflow public.ticket_cluster_workflows%ROWTYPE;
BEGIN
  v_lock_key := ('x' || substr(md5('cluster-workflow:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  INSERT INTO public.ticket_cluster_workflows (equipe_id)
  VALUES (p_equipe_id)
  ON CONFLICT (equipe_id) DO NOTHING;

  SELECT *
  INTO v_workflow
  FROM public.ticket_cluster_workflows
  WHERE equipe_id = p_equipe_id
  FOR UPDATE;

  IF v_workflow.stage = 'idle' THEN
    RETURN public.cluster_tickets_workflow_obter(p_equipe_id);
  END IF;

  IF v_workflow.expires_at IS NOT NULL AND v_workflow.expires_at <= now() THEN
    UPDATE public.ticket_cluster_workflows
    SET workflow_id = gen_random_uuid(),
        owner_user_id = NULL,
        owner_nome = NULL,
        owner_email = NULL,
        stage = 'idle',
        threshold_planetas = NULL,
        threshold_estrelas = NULL,
        tempo_espera_filtro = '{"modo":"todos","label":"Todos"}'::jsonb,
        started_at = NULL,
        expires_at = NULL,
        updated_at = now()
    WHERE equipe_id = p_equipe_id;

    RETURN public.cluster_tickets_workflow_obter(p_equipe_id);
  END IF;

  IF v_user_id IS NULL OR v_workflow.owner_user_id IS DISTINCT FROM v_user_id OR (p_workflow_id IS NOT NULL AND v_workflow.workflow_id IS DISTINCT FROM p_workflow_id) THEN
    RAISE EXCEPTION 'Apenas o dono do workflow pode liberar o Sistema Solar.';
  END IF;

  UPDATE public.ticket_cluster_workflows
  SET workflow_id = gen_random_uuid(),
      owner_user_id = NULL,
      owner_nome = NULL,
      owner_email = NULL,
      stage = 'idle',
      threshold_planetas = NULL,
      threshold_estrelas = NULL,
      tempo_espera_filtro = '{"modo":"todos","label":"Todos"}'::jsonb,
      started_at = NULL,
      expires_at = NULL,
      updated_at = now()
  WHERE equipe_id = p_equipe_id;

  RETURN public.cluster_tickets_workflow_obter(p_equipe_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_workflow_liberar(uuid, uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';

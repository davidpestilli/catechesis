SET search_path TO public, extensions;
CREATE TABLE IF NOT EXISTS public.ticket_cluster_workflows (
  equipe_id            uuid PRIMARY KEY REFERENCES public.equipes(id) ON DELETE CASCADE,
  workflow_id          uuid NOT NULL DEFAULT gen_random_uuid(),
  owner_user_id        uuid REFERENCES public.users(id) ON DELETE SET NULL,
  owner_nome           text,
  owner_email          text,
  stage                text NOT NULL DEFAULT 'idle'
                       CHECK (stage IN (
                         'idle',
                         'computando_planetas',
                         'aguardando_resumo',
                         'gerando_resumos',
                         'aguardando_estrelas',
                         'computando_estrelas'
                       )),
  threshold_planetas   real,
  threshold_estrelas   real,
  started_at           timestamptz,
  expires_at           timestamptz,
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ticket_cluster_workflows_expires_at
  ON public.ticket_cluster_workflows(expires_at)
  WHERE stage <> 'idle';
DROP TRIGGER IF EXISTS trg_ticket_cluster_workflows_updated_at ON public.ticket_cluster_workflows;
CREATE TRIGGER trg_ticket_cluster_workflows_updated_at
BEFORE UPDATE ON public.ticket_cluster_workflows
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_timestamp();
ALTER TABLE public.ticket_cluster_workflows ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ticket_cluster_workflows_select ON public.ticket_cluster_workflows;
CREATE POLICY ticket_cluster_workflows_select ON public.ticket_cluster_workflows
  FOR SELECT TO authenticated USING (true);
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
    'started_at', v_workflow.started_at,
    'expires_at', v_workflow.expires_at,
    'updated_at', v_workflow.updated_at,
    'is_active', v_workflow.stage <> 'idle' AND v_workflow.expires_at IS NOT NULL AND v_workflow.expires_at > now()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_workflow_obter(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.cluster_tickets_workflow_set_stage(
  p_equipe_id uuid,
  p_stage text,
  p_workflow_id uuid DEFAULT NULL,
  p_threshold_planetas real DEFAULT NULL,
  p_threshold_estrelas real DEFAULT NULL
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
    'started_at', v_workflow.started_at,
    'expires_at', v_workflow.expires_at,
    'updated_at', v_workflow.updated_at,
    'is_active', v_workflow.stage <> 'idle' AND v_workflow.expires_at IS NOT NULL AND v_workflow.expires_at > now()
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_workflow_set_stage(uuid, text, uuid, real, real) TO authenticated;
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
      started_at = NULL,
      expires_at = NULL,
      updated_at = now()
  WHERE equipe_id = p_equipe_id;

  RETURN public.cluster_tickets_workflow_obter(p_equipe_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_workflow_liberar(uuid, uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.cluster_tickets_resumo_claim_next(
  p_equipe_id uuid,
  p_workflow_id uuid
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
  v_cluster_id uuid;
  v_amostras jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado';
  END IF;

  v_lock_key := ('x' || substr(md5('cluster-summary-claim:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  SELECT *
  INTO v_workflow
  FROM public.ticket_cluster_workflows
  WHERE equipe_id = p_equipe_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('status', 'workflow_missing');
  END IF;

  IF v_workflow.stage = 'idle' OR v_workflow.expires_at IS NULL OR v_workflow.expires_at <= now() THEN
    RETURN jsonb_build_object('status', 'workflow_expired');
  END IF;

  IF v_workflow.owner_user_id IS DISTINCT FROM v_user_id OR v_workflow.workflow_id IS DISTINCT FROM p_workflow_id THEN
    RETURN jsonb_build_object('status', 'workflow_mismatch');
  END IF;

  IF v_workflow.stage NOT IN ('aguardando_resumo', 'gerando_resumos') THEN
    RETURN jsonb_build_object('status', 'workflow_stage_invalid', 'stage', v_workflow.stage);
  END IF;

  IF v_workflow.stage = 'aguardando_resumo' THEN
    UPDATE public.ticket_cluster_workflows
    SET stage = 'gerando_resumos',
        updated_at = now()
    WHERE equipe_id = p_equipe_id;
  END IF;

  WITH candidate AS (
    SELECT c.id
    FROM public.ticket_clusters c
    WHERE c.equipe_id = p_equipe_id
      AND (
        c.resumo_status IN ('pendente', 'erro')
        OR (c.resumo_status = 'processando' AND c.updated_at <= now() - interval '3 minutes')
      )
    ORDER BY
      CASE c.resumo_status
        WHEN 'pendente' THEN 0
        WHEN 'erro' THEN 1
        ELSE 2
      END,
      c.total_satelites DESC,
      c.updated_at ASC,
      c.id ASC
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  ), claimed AS (
    UPDATE public.ticket_clusters c
    SET resumo_status = 'processando',
        updated_at = now()
    FROM candidate
    WHERE c.id = candidate.id
    RETURNING c.id
  )
  SELECT id INTO v_cluster_id FROM claimed;

  IF v_cluster_id IS NULL THEN
    RETURN jsonb_build_object('status', 'empty');
  END IF;

  SELECT (
    SELECT jsonb_agg(jsonb_build_object(
      'numero_chamado', s.numero_chamado,
      'descricao', LEFT(s.descricao, 800)
    ) ORDER BY s.similaridade DESC)
    FROM (
      SELECT t.numero_chamado, t.descricao, m.similaridade
      FROM public.ticket_cluster_membros m
      JOIN public.tickets t ON t.id = m.ticket_id
      WHERE m.cluster_id = v_cluster_id
      ORDER BY m.similaridade DESC
      LIMIT 5
    ) s
  ) INTO v_amostras;

  RETURN jsonb_build_object(
    'status', 'claimed',
    'cluster_id', v_cluster_id,
    'amostras', COALESCE(v_amostras, '[]'::jsonb)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_resumo_claim_next(uuid, uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.cluster_tickets_pendentes_resumo(p_equipe_id uuid)
RETURNS TABLE(
  cluster_id uuid,
  amostras jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    (
      SELECT jsonb_agg(jsonb_build_object(
        'numero_chamado', s.numero_chamado,
        'descricao', LEFT(s.descricao, 800)
      ) ORDER BY s.similaridade DESC)
      FROM (
        SELECT t.numero_chamado, t.descricao, m.similaridade
        FROM public.ticket_cluster_membros m
        JOIN public.tickets t ON t.id = m.ticket_id
        WHERE m.cluster_id = c.id
        ORDER BY m.similaridade DESC
        LIMIT 5
      ) s
    )
  FROM public.ticket_clusters c
  WHERE c.equipe_id = p_equipe_id
    AND (
      c.resumo_status IN ('pendente', 'erro')
      OR (c.resumo_status = 'processando' AND c.updated_at <= now() - interval '3 minutes')
    );
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_pendentes_resumo(uuid) TO authenticated;

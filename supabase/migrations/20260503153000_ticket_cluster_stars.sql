-- ============================================================
-- MIGRATION: Sistema Solar — Camada de Estrelas
-- Data: 2026-05-03
-- Objetivo: persistir agrupamentos temáticos acima dos planetas
-- (ticket_clusters), usando modelo hub por similaridade ao centro.
-- ============================================================

SET search_path TO public, extensions;
-- ============================================================
-- 1. Tabelas
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ticket_cluster_stars (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipe_id         uuid NOT NULL REFERENCES public.equipes(id) ON DELETE CASCADE,
  center_cluster_id uuid NOT NULL REFERENCES public.ticket_clusters(id) ON DELETE CASCADE,
  rotulo            text NOT NULL DEFAULT '',
  total_planetas    integer NOT NULL DEFAULT 0,
  total_satelites   integer NOT NULL DEFAULT 0,
  threshold         real NOT NULL DEFAULT 0.89,
  min_confianca     integer NOT NULL DEFAULT 60,
  algoritmo_versao  text NOT NULL DEFAULT 'v1-star-hub',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ticket_cluster_stars_equipe
  ON public.ticket_cluster_stars(equipe_id, total_satelites DESC, updated_at DESC);
CREATE TABLE IF NOT EXISTS public.ticket_cluster_star_membros (
  star_id           uuid NOT NULL REFERENCES public.ticket_cluster_stars(id) ON DELETE CASCADE,
  cluster_id        uuid NOT NULL REFERENCES public.ticket_clusters(id) ON DELETE CASCADE,
  orbit_similarity  real NOT NULL DEFAULT 0,
  orbit_band        text NOT NULL DEFAULT 'externa'
                    CHECK (orbit_band IN ('centro', 'interna', 'media', 'externa')),
  is_center         boolean NOT NULL DEFAULT false,
  ordem             integer NOT NULL DEFAULT 0,
  PRIMARY KEY (star_id, cluster_id)
);
CREATE INDEX IF NOT EXISTS idx_ticket_cluster_star_membros_cluster
  ON public.ticket_cluster_star_membros(cluster_id);
DROP TRIGGER IF EXISTS trg_ticket_cluster_stars_updated_at ON public.ticket_cluster_stars;
CREATE TRIGGER trg_ticket_cluster_stars_updated_at
BEFORE UPDATE ON public.ticket_cluster_stars
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_timestamp();
-- ============================================================
-- 2. RLS
-- ============================================================

ALTER TABLE public.ticket_cluster_stars ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_cluster_star_membros ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ticket_cluster_stars_select ON public.ticket_cluster_stars;
CREATE POLICY ticket_cluster_stars_select ON public.ticket_cluster_stars
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS ticket_cluster_star_membros_select ON public.ticket_cluster_star_membros;
CREATE POLICY ticket_cluster_star_membros_select ON public.ticket_cluster_star_membros
  FOR SELECT TO authenticated USING (true);
-- ============================================================
-- 3. RPC: recomputar estrelas por equipe
-- ============================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_estrelas_recomputar(
  p_equipe_id      uuid,
  p_threshold      real    DEFAULT 0.89,
  p_min_planetas   integer DEFAULT 2,
  p_min_confianca  integer DEFAULT 60
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
SET statement_timeout = '60s'
AS $$
DECLARE
  v_inicio timestamptz := clock_timestamp();
  v_lock_key bigint;
  v_threshold real := LEAST(0.95::real, GREATEST(0.88::real, COALESCE(p_threshold, 0.89)::real));
  v_center uuid;
  v_star_id uuid;
  v_rotulo text;
  v_member_count integer;
  v_total_satelites integer;
  v_total_planetas integer := 0;
  v_total_clusters integer := 0;
  v_estrelas integer := 0;
BEGIN
  IF p_min_planetas IS NULL OR p_min_planetas < 2 THEN
    p_min_planetas := 2;
  END IF;

  IF p_min_confianca IS NULL OR p_min_confianca < 0 THEN
    p_min_confianca := 60;
  END IF;

  v_lock_key := ('x' || substr(md5('cluster-stars:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  DELETE FROM public.ticket_cluster_stars WHERE equipe_id = p_equipe_id;

  DROP TABLE IF EXISTS _star_candidates, _star_pair_sims, _star_remaining, _star_rows, _star_member_rows;

  CREATE TEMP TABLE _star_candidates ON COMMIT DROP AS
    SELECT
      c.id AS cluster_id,
      c.resumo_curto,
      c.problema_comum,
      c.confianca,
      c.total_satelites,
      c.centroid_ticket_id,
      te.embedding
    FROM public.ticket_clusters c
    JOIN public.ticket_embeddings te ON te.ticket_id = c.centroid_ticket_id
    WHERE c.equipe_id = p_equipe_id
      AND c.centroid_ticket_id IS NOT NULL
      AND c.confianca >= p_min_confianca;

  SELECT count(*) INTO v_total_clusters
  FROM public.ticket_clusters c
  WHERE c.equipe_id = p_equipe_id;

  IF NOT EXISTS (SELECT 1 FROM _star_candidates) THEN
    RETURN jsonb_build_object(
      'n_estrelas', 0,
      'n_planetas_em_estrelas', 0,
      'n_planetas_solitarios', v_total_clusters,
      'threshold', v_threshold,
      'min_confianca', p_min_confianca,
      'algoritmo', 'v1-star-hub',
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  CREATE INDEX ON _star_candidates(cluster_id);

  CREATE TEMP TABLE _star_pair_sims ON COMMIT DROP AS
    SELECT
      a.cluster_id AS a_id,
      b.cluster_id AS b_id,
      (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _star_candidates a
    JOIN _star_candidates b ON a.cluster_id < b.cluster_id
    WHERE (1 - (a.embedding <=> b.embedding)) >= v_threshold;

  CREATE INDEX ON _star_pair_sims(a_id);
  CREATE INDEX ON _star_pair_sims(b_id);

  CREATE TEMP TABLE _star_remaining (
    cluster_id uuid PRIMARY KEY
  ) ON COMMIT DROP;
  INSERT INTO _star_remaining(cluster_id)
  SELECT cluster_id FROM _star_candidates;

  CREATE TEMP TABLE _star_rows (
    star_id uuid PRIMARY KEY,
    equipe_id uuid NOT NULL,
    center_cluster_id uuid NOT NULL,
    rotulo text NOT NULL,
    total_planetas integer NOT NULL,
    total_satelites integer NOT NULL,
    threshold real NOT NULL,
    min_confianca integer NOT NULL,
    algoritmo_versao text NOT NULL
  ) ON COMMIT DROP;

  CREATE TEMP TABLE _star_member_rows (
    star_id uuid NOT NULL,
    cluster_id uuid NOT NULL,
    orbit_similarity real NOT NULL,
    orbit_band text NOT NULL,
    is_center boolean NOT NULL,
    ordem integer NOT NULL,
    total_satelites integer NOT NULL,
    PRIMARY KEY (star_id, cluster_id)
  ) ON COMMIT DROP;

  LOOP
    SELECT cand.cluster_id
    INTO v_center
    FROM (
      SELECT
        c.cluster_id,
        c.total_satelites,
        (
          SELECT count(*)
          FROM _star_remaining r
          JOIN _star_pair_sims p
            ON (
              (p.a_id = c.cluster_id AND p.b_id = r.cluster_id)
              OR
              (p.b_id = c.cluster_id AND p.a_id = r.cluster_id)
            )
          WHERE r.cluster_id <> c.cluster_id
        ) AS neighbor_count,
        (
          SELECT COALESCE(sum(p.sim), 0)
          FROM _star_remaining r
          JOIN _star_pair_sims p
            ON (
              (p.a_id = c.cluster_id AND p.b_id = r.cluster_id)
              OR
              (p.b_id = c.cluster_id AND p.a_id = r.cluster_id)
            )
          WHERE r.cluster_id <> c.cluster_id
        ) AS weighted_degree
      FROM _star_candidates c
      JOIN _star_remaining rc ON rc.cluster_id = c.cluster_id
    ) cand
    WHERE cand.neighbor_count >= GREATEST(1, p_min_planetas - 1)
    ORDER BY cand.neighbor_count DESC, cand.weighted_degree DESC, cand.total_satelites DESC, cand.cluster_id
    LIMIT 1;

    EXIT WHEN NOT FOUND;

    v_star_id := gen_random_uuid();

    SELECT COALESCE(
      NULLIF(BTRIM(resumo_curto), ''),
      NULLIF(BTRIM(problema_comum), ''),
      'Estrela temática'
    )
    INTO v_rotulo
    FROM _star_candidates
    WHERE cluster_id = v_center;

    INSERT INTO _star_member_rows(star_id, cluster_id, orbit_similarity, orbit_band, is_center, ordem, total_satelites)
    SELECT
      v_star_id,
      c.cluster_id,
      1::real,
      'centro',
      true,
      0,
      c.total_satelites
    FROM _star_candidates c
    WHERE c.cluster_id = v_center;

    INSERT INTO _star_member_rows(star_id, cluster_id, orbit_similarity, orbit_band, is_center, ordem, total_satelites)
    SELECT
      v_star_id,
      c.cluster_id,
      p.sim,
      CASE
        WHEN p.sim >= v_threshold + 0.03 THEN 'interna'
        WHEN p.sim >= v_threshold + 0.015 THEN 'media'
        ELSE 'externa'
      END,
      false,
      row_number() OVER (ORDER BY p.sim DESC, c.total_satelites DESC, c.cluster_id),
      c.total_satelites
    FROM _star_remaining r
    JOIN _star_candidates c ON c.cluster_id = r.cluster_id
    JOIN _star_pair_sims p
      ON (
        (p.a_id = v_center AND p.b_id = r.cluster_id)
        OR
        (p.b_id = v_center AND p.a_id = r.cluster_id)
      )
    WHERE r.cluster_id <> v_center;

    SELECT count(*), COALESCE(sum(total_satelites), 0)
    INTO v_member_count, v_total_satelites
    FROM _star_member_rows
    WHERE star_id = v_star_id;

    IF v_member_count >= p_min_planetas THEN
      INSERT INTO _star_rows(
        star_id,
        equipe_id,
        center_cluster_id,
        rotulo,
        total_planetas,
        total_satelites,
        threshold,
        min_confianca,
        algoritmo_versao
      )
      VALUES (
        v_star_id,
        p_equipe_id,
        v_center,
        v_rotulo,
        v_member_count,
        v_total_satelites,
        v_threshold,
        p_min_confianca,
        'v1-star-hub'
      );

      DELETE FROM _star_remaining
      WHERE cluster_id IN (
        SELECT cluster_id FROM _star_member_rows WHERE star_id = v_star_id
      );
    ELSE
      DELETE FROM _star_member_rows WHERE star_id = v_star_id;
      DELETE FROM _star_remaining WHERE cluster_id = v_center;
    END IF;
  END LOOP;

  INSERT INTO public.ticket_cluster_stars(
    id,
    equipe_id,
    center_cluster_id,
    rotulo,
    total_planetas,
    total_satelites,
    threshold,
    min_confianca,
    algoritmo_versao
  )
  SELECT
    star_id,
    equipe_id,
    center_cluster_id,
    rotulo,
    total_planetas,
    total_satelites,
    threshold,
    min_confianca,
    algoritmo_versao
  FROM _star_rows;

  INSERT INTO public.ticket_cluster_star_membros(
    star_id,
    cluster_id,
    orbit_similarity,
    orbit_band,
    is_center,
    ordem
  )
  SELECT
    star_id,
    cluster_id,
    orbit_similarity,
    orbit_band,
    is_center,
    ordem
  FROM _star_member_rows;

  SELECT count(*), COALESCE(sum(total_planetas), 0)
  INTO v_estrelas, v_total_planetas
  FROM _star_rows;

  RETURN jsonb_build_object(
    'n_estrelas', v_estrelas,
    'n_planetas_em_estrelas', v_total_planetas,
    'n_planetas_solitarios', GREATEST(0, v_total_clusters - v_total_planetas),
    'threshold', v_threshold,
    'min_confianca', p_min_confianca,
    'algoritmo', 'v1-star-hub',
    'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_estrelas_recomputar(uuid, real, integer, integer) TO authenticated;
-- ============================================================
-- 4. RPC: painel de estrelas + planetas solitários
-- ============================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_estrelas_painel(p_equipe_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH stars AS (
    SELECT
      s.id,
      s.center_cluster_id,
      s.rotulo,
      s.total_planetas,
      s.total_satelites,
      s.threshold,
      s.min_confianca,
      s.algoritmo_versao,
      s.updated_at,
      COALESCE((
        SELECT jsonb_agg(jsonb_build_object(
          'cluster_id', sm.cluster_id,
          'orbit_similarity', sm.orbit_similarity,
          'orbit_band', sm.orbit_band,
          'is_center', sm.is_center,
          'ordem', sm.ordem
        ) ORDER BY sm.is_center DESC, sm.ordem ASC, sm.cluster_id)
        FROM public.ticket_cluster_star_membros sm
        WHERE sm.star_id = s.id
      ), '[]'::jsonb) AS members
    FROM public.ticket_cluster_stars s
    WHERE s.equipe_id = p_equipe_id
    ORDER BY s.total_satelites DESC, s.total_planetas DESC, s.updated_at DESC
  ),
  starred AS (
    SELECT DISTINCT sm.cluster_id
    FROM public.ticket_cluster_star_membros sm
    JOIN public.ticket_cluster_stars s ON s.id = sm.star_id
    WHERE s.equipe_id = p_equipe_id
  ),
  solitary AS (
    SELECT c.id
    FROM public.ticket_clusters c
    WHERE c.equipe_id = p_equipe_id
      AND NOT EXISTS (
        SELECT 1 FROM starred st WHERE st.cluster_id = c.id
      )
    ORDER BY c.total_satelites DESC, c.updated_at DESC
  )
  SELECT jsonb_build_object(
    'estrelas', COALESCE((SELECT jsonb_agg(to_jsonb(stars)) FROM stars), '[]'::jsonb),
    'planetas_solitarios', COALESCE((SELECT jsonb_agg(id) FROM solitary), '[]'::jsonb),
    'metricas', jsonb_build_object(
      'n_estrelas', (SELECT count(*) FROM stars),
      'n_planetas_em_estrelas', COALESCE((SELECT sum(total_planetas) FROM stars), 0),
      'n_planetas_solitarios', (SELECT count(*) FROM solitary),
      'threshold_atual', COALESCE((SELECT max(threshold) FROM stars), 0.89),
      'min_confianca_atual', COALESCE((SELECT max(min_confianca) FROM stars), 60)
    )
  );
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_estrelas_painel(uuid) TO authenticated;

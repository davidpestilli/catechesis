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
  v_review_removed integer := 0;
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
      'algoritmo', 'v2-star-hub-reviewed',
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
        'v2-star-hub-reviewed'
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

  IF EXISTS (SELECT 1 FROM _star_rows) THEN
    LOOP
      DELETE FROM _star_member_rows WHERE NOT is_center;

      INSERT INTO _star_member_rows(star_id, cluster_id, orbit_similarity, orbit_band, is_center, ordem, total_satelites)
      SELECT
        best.star_id,
        best.cluster_id,
        best.sim,
        CASE
          WHEN best.sim >= v_threshold + 0.03 THEN 'interna'
          WHEN best.sim >= v_threshold + 0.015 THEN 'media'
          ELSE 'externa'
        END,
        false,
        0,
        cand.total_satelites
      FROM (
        SELECT
          cand.cluster_id,
          s.star_id,
          p.sim,
          row_number() OVER (
            PARTITION BY cand.cluster_id
            ORDER BY p.sim DESC, s.total_satelites DESC, s.center_cluster_id
          ) AS rn
        FROM _star_candidates cand
        JOIN _star_rows s ON s.center_cluster_id <> cand.cluster_id
        JOIN _star_pair_sims p
          ON (
            (p.a_id = cand.cluster_id AND p.b_id = s.center_cluster_id)
            OR
            (p.b_id = cand.cluster_id AND p.a_id = s.center_cluster_id)
          )
        WHERE cand.cluster_id NOT IN (SELECT center_cluster_id FROM _star_rows)
          AND p.sim >= v_threshold
      ) best
      JOIN _star_candidates cand ON cand.cluster_id = best.cluster_id
      WHERE best.rn = 1;

      WITH star_stats AS (
        SELECT
          star_id,
          count(*) AS total_planetas,
          COALESCE(sum(total_satelites), 0) AS total_satelites
        FROM _star_member_rows
        GROUP BY star_id
      )
      UPDATE _star_rows s
      SET total_planetas = stats.total_planetas,
          total_satelites = stats.total_satelites,
          algoritmo_versao = 'v2-star-hub-reviewed'
      FROM star_stats stats
      WHERE stats.star_id = s.star_id;

      SELECT count(*)
      INTO v_review_removed
      FROM _star_rows
      WHERE total_planetas < p_min_planetas;

      EXIT WHEN v_review_removed = 0;

      DELETE FROM _star_member_rows
      WHERE star_id IN (
        SELECT star_id FROM _star_rows WHERE total_planetas < p_min_planetas
      );

      DELETE FROM _star_rows
      WHERE total_planetas < p_min_planetas;

      EXIT WHEN NOT EXISTS (SELECT 1 FROM _star_rows);
    END LOOP;

    UPDATE _star_member_rows
    SET ordem = 0
    WHERE is_center;

    UPDATE _star_member_rows m
    SET ordem = ranked.ordem
    FROM (
      SELECT
        star_id,
        cluster_id,
        row_number() OVER (
          PARTITION BY star_id
          ORDER BY orbit_similarity DESC, total_satelites DESC, cluster_id
        ) AS ordem
      FROM _star_member_rows
      WHERE NOT is_center
    ) ranked
    WHERE ranked.star_id = m.star_id
      AND ranked.cluster_id = m.cluster_id;
  END IF;

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
    'algoritmo', 'v2-star-hub-reviewed',
    'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_estrelas_recomputar(uuid, real, integer, integer) TO authenticated;

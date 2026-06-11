-- ============================================================
-- Migracao: Sistema Solar refina mega-clusters
-- Data: 2026-05-02
--
-- Objetivo:
--   Componentes semanticamente conectados acima de p_max_satelites
--   deixam de ser descartados de imediato. A RPC reprocessa cada
--   mega-componente isoladamente com thresholds progressivamente mais
--   rigidos para obter planetas menores e mais especificos.
-- ============================================================

SET search_path TO public, extensions;
CREATE OR REPLACE FUNCTION public.cluster_tickets_equipe(
  p_equipe_id     uuid,
  p_threshold     real    DEFAULT 0.91,
  p_min_satelites integer DEFAULT 3,
  p_top_k         integer DEFAULT 20,
  p_max_satelites integer DEFAULT 120
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
SET statement_timeout = '180s'
AS $$
DECLARE
  v_inicio       timestamptz := clock_timestamp();
  v_n_avaliados integer;
  v_n_clusters  integer;
  v_n_agrupados integer;
  v_n_componentes_gigantes integer := 0;
  v_n_componentes_refinados integer := 0;
  v_n_clusters_refinados integer := 0;
  v_n_tickets_refinados integer := 0;
  v_n_descartados_grandes integer := 0;
  v_n_tickets_descartados_grandes integer := 0;
  v_lock_key bigint;
  v_frontier record;
  v_ref_threshold real;
  v_refine_max_level integer := 4;
  v_changed integer;
  v_iter integer;
  v_rows integer;
  v_more_count integer;
  v_more_size integer;
BEGIN
  v_lock_key := ('x' || substr(md5('cluster:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  DELETE FROM public.ticket_clusters WHERE equipe_id = p_equipe_id;

  CREATE TEMP TABLE _candidatos ON COMMIT DROP AS
    SELECT te.ticket_id, te.embedding
    FROM public.ticket_embeddings te
    JOIN public.tickets t ON t.id = te.ticket_id
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    WHERE ge.equipe_id = p_equipe_id
      AND t.status = 'aguardando';

  SELECT count(*) INTO v_n_avaliados FROM _candidatos;

  IF v_n_avaliados = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0,
      'n_tickets_agrupados', 0,
      'n_tickets_avaliados', 0,
      'n_componentes_gigantes', 0,
      'n_componentes_refinados', 0,
      'n_clusters_refinados', 0,
      'n_tickets_refinados', 0,
      'n_descartados_grandes', 0,
      'n_tickets_descartados_grandes', 0,
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  CREATE TEMP TABLE _arestas ON COMMIT DROP AS
    SELECT a.ticket_id AS a_id, b.ticket_id AS b_id, (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _candidatos a
    CROSS JOIN LATERAL (
      SELECT c.ticket_id, c.embedding
      FROM _candidatos c
      WHERE c.ticket_id <> a.ticket_id
      ORDER BY a.embedding <=> c.embedding
      LIMIT p_top_k
    ) b
    WHERE (1 - (a.embedding <=> b.embedding)) >= p_threshold;

  CREATE TEMP TABLE _uf (ticket_id uuid PRIMARY KEY, root uuid NOT NULL) ON COMMIT DROP;
  INSERT INTO _uf(ticket_id, root) SELECT ticket_id, ticket_id FROM _candidatos;

  v_changed := 1;
  v_iter := 0;
  WHILE v_changed > 0 AND v_iter < 50 LOOP
    WITH pares AS (
      SELECT DISTINCT ua.root AS ra, ub.root AS rb
      FROM _arestas e
      JOIN _uf ua ON ua.ticket_id = e.a_id
      JOIN _uf ub ON ub.ticket_id = e.b_id
      WHERE ua.root <> ub.root
    ),
    novos AS (
      SELECT ra AS perdedor, LEAST(ra, rb) AS vencedor FROM pares WHERE ra > rb
      UNION
      SELECT rb, LEAST(ra, rb) FROM pares WHERE rb > ra
    ),
    atualizacoes AS (
      UPDATE _uf SET root = n.vencedor
      FROM novos n
      WHERE _uf.root = n.perdedor
      RETURNING 1
    )
    SELECT count(*) INTO v_changed FROM atualizacoes;
    v_iter := v_iter + 1;
  END LOOP;

  CREATE TEMP TABLE _componentes ON COMMIT DROP AS
    SELECT root, count(*)::integer AS tamanho, array_agg(ticket_id) AS membros
    FROM _uf
    GROUP BY root;

  CREATE TEMP TABLE _grupos (
    root uuid NOT NULL,
    tamanho integer NOT NULL,
    membros uuid[] NOT NULL,
    refinado boolean NOT NULL DEFAULT false,
    threshold_usado real NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _grupos(root, tamanho, membros, refinado, threshold_usado)
  SELECT root, tamanho, membros, false, p_threshold
  FROM _componentes
  WHERE tamanho BETWEEN p_min_satelites AND p_max_satelites;

  CREATE TEMP TABLE _grupos_refinados (
    root uuid NOT NULL,
    tamanho integer NOT NULL,
    membros uuid[] NOT NULL,
    refinado boolean NOT NULL DEFAULT true,
    threshold_usado real NOT NULL,
    origem_root uuid NOT NULL
  ) ON COMMIT DROP;

  CREATE TEMP TABLE _ref_frontier (
    id bigserial PRIMARY KEY,
    origem_root uuid NOT NULL,
    nivel integer NOT NULL,
    threshold_usado real NOT NULL,
    membros uuid[] NOT NULL,
    tamanho integer NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _ref_frontier(origem_root, nivel, threshold_usado, membros, tamanho)
  SELECT root, 0, p_threshold, membros, tamanho
  FROM _componentes
  WHERE tamanho > p_max_satelites;

  SELECT count(*) INTO v_n_componentes_gigantes FROM _ref_frontier;

  CREATE TEMP TABLE _ref_candidatos ON COMMIT DROP AS
    SELECT * FROM _candidatos WHERE false;
  CREATE TEMP TABLE _ref_arestas (a_id uuid NOT NULL, b_id uuid NOT NULL, sim real NOT NULL) ON COMMIT DROP;
  CREATE TEMP TABLE _ref_uf (ticket_id uuid PRIMARY KEY, root uuid NOT NULL) ON COMMIT DROP;
  CREATE TEMP TABLE _ref_componentes (root uuid NOT NULL, tamanho integer NOT NULL, membros uuid[] NOT NULL) ON COMMIT DROP;

  LOOP
    SELECT * INTO v_frontier
    FROM _ref_frontier
    ORDER BY tamanho DESC, id
    LIMIT 1;

    EXIT WHEN NOT FOUND;

    DELETE FROM _ref_frontier WHERE id = v_frontier.id;

    IF v_frontier.nivel >= v_refine_max_level THEN
      v_n_descartados_grandes := v_n_descartados_grandes + 1;
      v_n_tickets_descartados_grandes := v_n_tickets_descartados_grandes + v_frontier.tamanho;
      CONTINUE;
    END IF;

    v_ref_threshold := LEAST(0.99::real, (p_threshold + ((v_frontier.nivel + 1) * 0.03))::real);
    IF v_ref_threshold <= v_frontier.threshold_usado THEN
      v_ref_threshold := LEAST(0.99::real, (v_frontier.threshold_usado + 0.01)::real);
    END IF;

    TRUNCATE _ref_candidatos, _ref_arestas, _ref_uf, _ref_componentes;

    INSERT INTO _ref_candidatos(ticket_id, embedding)
    SELECT c.ticket_id, c.embedding
    FROM _candidatos c
    WHERE c.ticket_id = ANY(v_frontier.membros);

    INSERT INTO _ref_arestas(a_id, b_id, sim)
    SELECT a.ticket_id AS a_id, b.ticket_id AS b_id, (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _ref_candidatos a
    CROSS JOIN LATERAL (
      SELECT c.ticket_id, c.embedding
      FROM _ref_candidatos c
      WHERE c.ticket_id <> a.ticket_id
      ORDER BY a.embedding <=> c.embedding
      LIMIT p_top_k
    ) b
    WHERE (1 - (a.embedding <=> b.embedding)) >= v_ref_threshold;

    INSERT INTO _ref_uf(ticket_id, root)
    SELECT ticket_id, ticket_id FROM _ref_candidatos;

    v_changed := 1;
    v_iter := 0;
    WHILE v_changed > 0 AND v_iter < 50 LOOP
      WITH pares AS (
        SELECT DISTINCT ua.root AS ra, ub.root AS rb
        FROM _ref_arestas e
        JOIN _ref_uf ua ON ua.ticket_id = e.a_id
        JOIN _ref_uf ub ON ub.ticket_id = e.b_id
        WHERE ua.root <> ub.root
      ),
      novos AS (
        SELECT ra AS perdedor, LEAST(ra, rb) AS vencedor FROM pares WHERE ra > rb
        UNION
        SELECT rb, LEAST(ra, rb) FROM pares WHERE rb > ra
      ),
      atualizacoes AS (
        UPDATE _ref_uf SET root = n.vencedor
        FROM novos n
        WHERE _ref_uf.root = n.perdedor
        RETURNING 1
      )
      SELECT count(*) INTO v_changed FROM atualizacoes;
      v_iter := v_iter + 1;
    END LOOP;

    INSERT INTO _ref_componentes(root, tamanho, membros)
    SELECT root, count(*)::integer AS tamanho, array_agg(ticket_id) AS membros
    FROM _ref_uf
    GROUP BY root;

    INSERT INTO _grupos_refinados(root, tamanho, membros, refinado, threshold_usado, origem_root)
    SELECT root, tamanho, membros, true, v_ref_threshold, v_frontier.origem_root
    FROM _ref_componentes
    WHERE tamanho BETWEEN p_min_satelites AND p_max_satelites;

    IF (v_frontier.nivel + 1) < v_refine_max_level AND v_ref_threshold < 0.99 THEN
      INSERT INTO _ref_frontier(origem_root, nivel, threshold_usado, membros, tamanho)
      SELECT v_frontier.origem_root, v_frontier.nivel + 1, v_ref_threshold, membros, tamanho
      FROM _ref_componentes
      WHERE tamanho > p_max_satelites;
    ELSE
      SELECT count(*), COALESCE(sum(tamanho), 0)::integer
      INTO v_more_count, v_more_size
      FROM _ref_componentes
      WHERE tamanho > p_max_satelites;

      v_n_descartados_grandes := v_n_descartados_grandes + COALESCE(v_more_count, 0);
      v_n_tickets_descartados_grandes := v_n_tickets_descartados_grandes + COALESCE(v_more_size, 0);
    END IF;
  END LOOP;

  INSERT INTO _grupos(root, tamanho, membros, refinado, threshold_usado)
  SELECT root, tamanho, membros, refinado, threshold_usado
  FROM _grupos_refinados;

  SELECT
    count(DISTINCT origem_root)::integer,
    count(*)::integer,
    COALESCE(sum(tamanho), 0)::integer
  INTO v_n_componentes_refinados, v_n_clusters_refinados, v_n_tickets_refinados
  FROM _grupos_refinados;

  SELECT count(*), COALESCE(sum(tamanho), 0)::integer
  INTO v_n_clusters, v_n_agrupados
  FROM _grupos;

  IF v_n_clusters = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0,
      'n_tickets_agrupados', 0,
      'n_tickets_avaliados', v_n_avaliados,
      'n_componentes_gigantes', v_n_componentes_gigantes,
      'n_componentes_refinados', v_n_componentes_refinados,
      'n_clusters_refinados', v_n_clusters_refinados,
      'n_tickets_refinados', v_n_tickets_refinados,
      'n_descartados_grandes', v_n_descartados_grandes,
      'n_tickets_descartados_grandes', v_n_tickets_descartados_grandes,
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  WITH grupos AS (
    SELECT g.root, g.tamanho, g.membros, g.refinado, g.threshold_usado, gen_random_uuid() AS cluster_id
    FROM _grupos g
  ),
  inserts AS (
    INSERT INTO public.ticket_clusters (
      id, equipe_id, total_satelites, total_livres,
      categorias, subcategorias, gses, centroid_ticket_id,
      algoritmo_versao, threshold, resumo_status
    )
    SELECT
      g.cluster_id, p_equipe_id, g.tamanho,
      (SELECT count(*) FROM public.tickets t
        WHERE t.id = ANY(g.membros) AND t.mantido_por IS NULL),
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', x.cat_id, 'nome', x.cat_nome, 'count', x.c) ORDER BY x.c DESC), '[]'::jsonb)
        FROM (
          SELECT ce.id AS cat_id, ce.nome AS cat_nome, count(*)::int AS c
          FROM public.tickets t
          LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
          LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
          WHERE t.id = ANY(g.membros) GROUP BY ce.id, ce.nome
        ) x),
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', x.sub_id, 'nome', x.sub_nome, 'count', x.c) ORDER BY x.c DESC), '[]'::jsonb)
        FROM (
          SELECT sg.id AS sub_id, sg.nome AS sub_nome, count(*)::int AS c
          FROM public.tickets t
          LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
          LEFT JOIN public.subcategorias_gse sg ON sg.id = ta.subcategoria_gse_id
          WHERE t.id = ANY(g.membros) GROUP BY sg.id, sg.nome
        ) x),
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('gse', x.gse, 'count', x.c) ORDER BY x.c DESC), '[]'::jsonb)
        FROM (
          SELECT t.gse, count(*)::int AS c FROM public.tickets t
          WHERE t.id = ANY(g.membros) GROUP BY t.gse
        ) x),
      g.root,
      CASE
        WHEN g.refinado THEN 'v3-cosine-refine-max' || p_max_satelites::text
        ELSE 'v3-cosine-direct-max' || p_max_satelites::text
      END,
      g.threshold_usado,
      'pendente'
    FROM grupos g
    RETURNING id
  )
  INSERT INTO public.ticket_cluster_membros (cluster_id, ticket_id, similaridade)
  SELECT
    g.cluster_id, t_id,
    COALESCE((1 - (
      (SELECT embedding FROM public.ticket_embeddings WHERE ticket_id = t_id)
      <=>
      (SELECT embedding FROM public.ticket_embeddings WHERE ticket_id = g.root)
    ))::real, 0)
  FROM grupos g
  CROSS JOIN LATERAL unnest(g.membros) AS t_id;

  RETURN jsonb_build_object(
    'n_clusters', v_n_clusters,
    'n_tickets_agrupados', v_n_agrupados,
    'n_tickets_avaliados', v_n_avaliados,
    'n_componentes_gigantes', v_n_componentes_gigantes,
    'n_componentes_refinados', v_n_componentes_refinados,
    'n_clusters_refinados', v_n_clusters_refinados,
    'n_tickets_refinados', v_n_tickets_refinados,
    'n_descartados_grandes', v_n_descartados_grandes,
    'n_tickets_descartados_grandes', v_n_tickets_descartados_grandes,
    'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) IS
  'Agrupa tickets pendentes por embeddings. Desde v3, mega-componentes acima de p_max_satelites sao refinados em subclusters com thresholds progressivamente mais rigidos.';

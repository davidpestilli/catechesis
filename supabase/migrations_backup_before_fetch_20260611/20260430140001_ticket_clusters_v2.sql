-- =====================================================
-- PATCH: Sistema Solar — afinamento threshold/perf/anti-mega-cluster
-- Data: 2026-04-30
-- Mudanças:
--   1. statement_timeout interno = 180s (evita timeout do PostgREST)
--   2. Default threshold 0.88 -> 0.91 (granularidade melhor)
--   3. Default min_satelites mantido em 3
--   4. Novo parâmetro p_max_satelites (default 120): clusters maiores
--      que isso são DESCARTADOS (provável "ponte" por single-link).
--   5. algoritmo_versao = 'v2-cosine091-min3-max120'
-- =====================================================

DROP FUNCTION IF EXISTS public.cluster_tickets_equipe(uuid, real, integer, integer);
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
  v_n_avaliados  integer;
  v_n_clusters   integer;
  v_n_agrupados  integer;
  v_n_descartados_grandes integer := 0;
  v_lock_key     bigint;
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
      'n_clusters', 0, 'n_tickets_agrupados', 0, 'n_tickets_avaliados', 0,
      'n_descartados_grandes', 0,
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

  DECLARE
    v_changed integer := 1;
    v_iter integer := 0;
  BEGIN
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
  END;

  -- Componentes que respeitam tamanho mínimo E máximo
  CREATE TEMP TABLE _grupos ON COMMIT DROP AS
    SELECT root, count(*)::integer AS tamanho, array_agg(ticket_id) AS membros
    FROM _uf
    GROUP BY root
    HAVING count(*) BETWEEN p_min_satelites AND p_max_satelites;

  -- Estatística: quantos componentes ficaram acima do teto (ruído provável)
  SELECT count(*) INTO v_n_descartados_grandes
  FROM (SELECT root FROM _uf GROUP BY root HAVING count(*) > p_max_satelites) x;

  SELECT count(*), COALESCE(sum(tamanho), 0) INTO v_n_clusters, v_n_agrupados FROM _grupos;

  IF v_n_clusters = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0, 'n_tickets_agrupados', 0, 'n_tickets_avaliados', v_n_avaliados,
      'n_descartados_grandes', v_n_descartados_grandes,
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  WITH grupos AS (
    SELECT g.root, g.tamanho, g.membros, gen_random_uuid() AS cluster_id FROM _grupos g
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
      'v2-cosine091-min3-max' || p_max_satelites::text,
      p_threshold,
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
    'n_descartados_grandes', v_n_descartados_grandes,
    'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) TO authenticated;

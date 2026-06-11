-- ============================================================
-- Migracao: Sistema Solar v5 - coesao complete-link + medoid
-- Data: 2026-05-02
--
-- Objetivo:
--   Substituir o agrupamento v4 por uma versao global mais conservadora:
--   1. Mantem candidatos acionaveis e arestas dentro da mesma subcategoria.
--   2. Usa o threshold informado como etapa de recall inicial.
--   3. Divide cada componente por coesao interna complete-link.
--   4. Grava um medoid semantico real como centroid_ticket_id.
--   5. Ignora placeholders sem descricao util para nao formar lotes
--      acionaveis apenas por texto artificial.
--
-- Motivacao:
--   O union-find/single-link da v4 ainda permitia pontes dentro de
--   subcategorias amplas, formando planetas com pares internos muito abaixo
--   do threshold. A v5 so aceita um satelite no planeta final quando ele e
--   suficientemente parecido com todos os membros ja aceitos.
-- ============================================================

SET search_path TO public, extensions;
CREATE OR REPLACE FUNCTION public.cluster_tickets_equipe(
  p_equipe_id     uuid,
  p_threshold     real    DEFAULT 0.85,
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
  v_inicio timestamptz := clock_timestamp();
  v_n_avaliados integer := 0;
  v_n_com_subcategoria integer := 0;
  v_n_clusters integer := 0;
  v_n_agrupados integer := 0;
  v_n_componentes_gigantes integer := 0;
  v_n_componentes_refinados integer := 0;
  v_n_clusters_refinados integer := 0;
  v_n_tickets_refinados integer := 0;
  v_n_descartados_grandes integer := 0;
  v_n_tickets_descartados_grandes integer := 0;
  v_n_descartados_pequenos integer := 0;
  v_lock_key bigint;
  v_changed integer;
  v_iter integer;
  v_frontier record;
  v_seed uuid;
  v_candidate uuid;
  v_remaining_count integer;
  v_group_count integer;
  v_group_members uuid[];
  v_medoid uuid;
  v_group_min_sim real;
  v_group_avg_sim real;
  v_coesao_threshold real;
  v_next_threshold real;
  v_refine_max_level integer := 4;
BEGIN
  IF p_min_satelites IS NULL OR p_min_satelites < 2 THEN
    p_min_satelites := 3;
  END IF;

  IF p_top_k IS NULL OR p_top_k < 1 THEN
    p_top_k := 20;
  END IF;

  IF p_max_satelites IS NULL OR p_max_satelites < p_min_satelites THEN
    p_max_satelites := GREATEST(120, p_min_satelites);
  END IF;

  -- Threshold de coesao final. Ex.: slider 0.85 -> planeta final precisa
  -- ter todos os pares internos >= 0.88, salvo rodadas de refino.
  v_coesao_threshold := LEAST(0.97::real, GREATEST(0.88::real, (p_threshold + 0.03)::real));

  v_lock_key := ('x' || substr(md5('cluster:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  DELETE FROM public.ticket_clusters WHERE equipe_id = p_equipe_id;

  DROP TABLE IF EXISTS _candidatos, _arestas, _uf, _componentes, _split_frontier,
    _split_sims, _remaining, _current_group, _grupos;

  CREATE TEMP TABLE _candidatos ON COMMIT DROP AS
    SELECT
      te.ticket_id,
      te.embedding,
      ta.categoria_equipe_id,
      ta.subcategoria_gse_id,
      t.gse
    FROM public.ticket_embeddings te
    JOIN public.tickets t ON t.id = te.ticket_id
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
    WHERE ge.equipe_id = p_equipe_id
      AND t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND t.mantido_por IS NULL
      AND NULLIF(BTRIM(t.descricao), '') IS NOT NULL
      AND lower(BTRIM(t.descricao)) !~ '^(descri[cç][aã]o\s+n[aã]o\s+encontrada|sem\s+descri[cç][aã]o|n[aã]o\s+informado|nao\s+informado|description\s+not\s+found)$';

  SELECT count(*) INTO v_n_avaliados FROM _candidatos;
  SELECT count(*) INTO v_n_com_subcategoria FROM _candidatos WHERE subcategoria_gse_id IS NOT NULL;

  IF v_n_avaliados = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0,
      'n_tickets_agrupados', 0,
      'n_tickets_avaliados', 0,
      'n_tickets_com_subcategoria', 0,
      'n_componentes_gigantes', 0,
      'n_componentes_refinados', 0,
      'n_clusters_refinados', 0,
      'n_tickets_refinados', 0,
      'n_descartados_grandes', 0,
      'n_tickets_descartados_grandes', 0,
      'n_descartados_pequenos', 0,
      'threshold_recall', p_threshold,
      'threshold_coesao', v_coesao_threshold,
      'algoritmo', 'v5-complete-medoid',
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  CREATE INDEX ON _candidatos(ticket_id);
  CREATE INDEX ON _candidatos(subcategoria_gse_id);

  -- Recall inicial: same-subcategoria + top-K vetorial + threshold do usuario.
  CREATE TEMP TABLE _arestas ON COMMIT DROP AS
    SELECT a.ticket_id AS a_id, b.ticket_id AS b_id, (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _candidatos a
    CROSS JOIN LATERAL (
      SELECT c.ticket_id, c.embedding
      FROM _candidatos c
      WHERE c.ticket_id <> a.ticket_id
        AND c.subcategoria_gse_id = a.subcategoria_gse_id
      ORDER BY a.embedding <=> c.embedding
      LIMIT p_top_k
    ) b
    WHERE a.subcategoria_gse_id IS NOT NULL
      AND (1 - (a.embedding <=> b.embedding)) >= p_threshold;

  CREATE INDEX ON _arestas(a_id);
  CREATE INDEX ON _arestas(b_id);

  -- Union-find apenas para achar componentes candidatos. A decisao final do
  -- planeta acontece depois, por complete-link.
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
    SELECT root, count(*)::integer AS tamanho, array_agg(ticket_id ORDER BY ticket_id) AS membros
    FROM _uf
    GROUP BY root;

  CREATE TEMP TABLE _split_frontier (
    id bigserial PRIMARY KEY,
    origem_root uuid NOT NULL,
    nivel integer NOT NULL,
    threshold_usado real NOT NULL,
    membros uuid[] NOT NULL,
    tamanho integer NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _split_frontier(origem_root, nivel, threshold_usado, membros, tamanho)
  SELECT root, 0, v_coesao_threshold, membros, tamanho
  FROM _componentes
  WHERE tamanho >= p_min_satelites;

  SELECT count(*) INTO v_n_componentes_gigantes
  FROM _componentes
  WHERE tamanho > p_max_satelites;

  CREATE TEMP TABLE _split_sims (
    a_id uuid NOT NULL,
    b_id uuid NOT NULL,
    sim real NOT NULL,
    PRIMARY KEY (a_id, b_id)
  ) ON COMMIT DROP;

  CREATE TEMP TABLE _remaining (ticket_id uuid PRIMARY KEY) ON COMMIT DROP;
  CREATE TEMP TABLE _current_group (ticket_id uuid PRIMARY KEY) ON COMMIT DROP;

  CREATE TEMP TABLE _grupos (
    root uuid NOT NULL,
    tamanho integer NOT NULL,
    membros uuid[] NOT NULL,
    refinado boolean NOT NULL DEFAULT false,
    threshold_usado real NOT NULL,
    coesao_min real,
    coesao_media real,
    origem_root uuid NOT NULL
  ) ON COMMIT DROP;

  LOOP
    SELECT * INTO v_frontier
    FROM _split_frontier
    ORDER BY tamanho DESC, nivel ASC, id ASC
    LIMIT 1;

    EXIT WHEN NOT FOUND;

    DELETE FROM _split_frontier WHERE id = v_frontier.id;

    IF v_frontier.tamanho < p_min_satelites THEN
      v_n_descartados_pequenos := v_n_descartados_pequenos + v_frontier.tamanho;
      CONTINUE;
    END IF;

    TRUNCATE _split_sims, _remaining, _current_group;

    INSERT INTO _remaining(ticket_id)
    SELECT unnest(v_frontier.membros);

    INSERT INTO _split_sims(a_id, b_id, sim)
    SELECT LEAST(a.ticket_id, b.ticket_id), GREATEST(a.ticket_id, b.ticket_id),
           (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _candidatos a
    JOIN _candidatos b ON a.ticket_id < b.ticket_id
    WHERE a.ticket_id = ANY(v_frontier.membros)
      AND b.ticket_id = ANY(v_frontier.membros);

    LOOP
      SELECT count(*) INTO v_remaining_count FROM _remaining;
      EXIT WHEN v_remaining_count < p_min_satelites;

      TRUNCATE _current_group;

      SELECT r.ticket_id INTO v_seed
      FROM _remaining r
      ORDER BY
        (
          SELECT count(*)
          FROM _remaining o
          JOIN _split_sims s
            ON s.a_id = LEAST(r.ticket_id, o.ticket_id)
           AND s.b_id = GREATEST(r.ticket_id, o.ticket_id)
          WHERE o.ticket_id <> r.ticket_id
            AND s.sim >= v_frontier.threshold_usado
        ) DESC,
        (
          SELECT avg(s.sim)
          FROM _remaining o
          JOIN _split_sims s
            ON s.a_id = LEAST(r.ticket_id, o.ticket_id)
           AND s.b_id = GREATEST(r.ticket_id, o.ticket_id)
          WHERE o.ticket_id <> r.ticket_id
        ) DESC NULLS LAST,
        r.ticket_id
      LIMIT 1;

      INSERT INTO _current_group(ticket_id) VALUES (v_seed);
      DELETE FROM _remaining WHERE ticket_id = v_seed;

      LOOP
        SELECT r.ticket_id INTO v_candidate
        FROM _remaining r
        WHERE NOT EXISTS (
          SELECT 1
          FROM _current_group g
          LEFT JOIN _split_sims s
            ON s.a_id = LEAST(g.ticket_id, r.ticket_id)
           AND s.b_id = GREATEST(g.ticket_id, r.ticket_id)
          WHERE COALESCE(s.sim, 0) < v_frontier.threshold_usado
        )
        ORDER BY
          (
            SELECT avg(COALESCE(s.sim, 0))
            FROM _current_group g
            LEFT JOIN _split_sims s
              ON s.a_id = LEAST(g.ticket_id, r.ticket_id)
             AND s.b_id = GREATEST(g.ticket_id, r.ticket_id)
          ) DESC NULLS LAST,
          r.ticket_id
        LIMIT 1;

        EXIT WHEN NOT FOUND;

        INSERT INTO _current_group(ticket_id) VALUES (v_candidate);
        DELETE FROM _remaining WHERE ticket_id = v_candidate;
      END LOOP;

      SELECT count(*), array_agg(ticket_id ORDER BY ticket_id)
      INTO v_group_count, v_group_members
      FROM _current_group;

      IF v_group_count < p_min_satelites THEN
        v_n_descartados_pequenos := v_n_descartados_pequenos + v_group_count;
        CONTINUE;
      END IF;

      IF v_group_count > p_max_satelites THEN
        IF v_frontier.nivel < v_refine_max_level AND v_frontier.threshold_usado < 0.99 THEN
          v_next_threshold := LEAST(0.99::real, (v_frontier.threshold_usado + 0.03)::real);
          INSERT INTO _split_frontier(origem_root, nivel, threshold_usado, membros, tamanho)
          VALUES (v_frontier.origem_root, v_frontier.nivel + 1, v_next_threshold, v_group_members, v_group_count);
          CONTINUE;
        END IF;

        v_n_descartados_grandes := v_n_descartados_grandes + 1;
        v_n_tickets_descartados_grandes := v_n_tickets_descartados_grandes + v_group_count;
        CONTINUE;
      END IF;

      SELECT g.ticket_id INTO v_medoid
      FROM _current_group g
      ORDER BY
        (
          SELECT avg(CASE
            WHEN o.ticket_id = g.ticket_id THEN 1::real
            ELSE COALESCE(s.sim, 0)
          END)
          FROM _current_group o
          LEFT JOIN _split_sims s
            ON s.a_id = LEAST(g.ticket_id, o.ticket_id)
           AND s.b_id = GREATEST(g.ticket_id, o.ticket_id)
        ) DESC,
        g.ticket_id
      LIMIT 1;

      SELECT min(s.sim), avg(s.sim)
      INTO v_group_min_sim, v_group_avg_sim
      FROM _current_group a
      JOIN _current_group b ON a.ticket_id < b.ticket_id
      JOIN _split_sims s
        ON s.a_id = LEAST(a.ticket_id, b.ticket_id)
       AND s.b_id = GREATEST(a.ticket_id, b.ticket_id);

      INSERT INTO _grupos(root, tamanho, membros, refinado, threshold_usado, coesao_min, coesao_media, origem_root)
      VALUES (
        v_medoid,
        v_group_count,
        v_group_members,
        v_frontier.nivel > 0,
        v_frontier.threshold_usado,
        COALESCE(v_group_min_sim, 1),
        COALESCE(v_group_avg_sim, 1),
        v_frontier.origem_root
      );
    END LOOP;

    SELECT count(*) INTO v_remaining_count FROM _remaining;
    v_n_descartados_pequenos := v_n_descartados_pequenos + COALESCE(v_remaining_count, 0);
  END LOOP;

  SELECT
    count(*)::integer,
    COALESCE(sum(tamanho), 0)::integer,
    COALESCE(count(*) FILTER (WHERE refinado), 0)::integer,
    COALESCE(sum(tamanho) FILTER (WHERE refinado), 0)::integer,
    COALESCE(count(DISTINCT origem_root) FILTER (WHERE refinado), 0)::integer
  INTO v_n_clusters, v_n_agrupados, v_n_clusters_refinados, v_n_tickets_refinados, v_n_componentes_refinados
  FROM _grupos;

  IF v_n_clusters = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0,
      'n_tickets_agrupados', 0,
      'n_tickets_avaliados', v_n_avaliados,
      'n_tickets_com_subcategoria', v_n_com_subcategoria,
      'n_componentes_gigantes', v_n_componentes_gigantes,
      'n_componentes_refinados', v_n_componentes_refinados,
      'n_clusters_refinados', v_n_clusters_refinados,
      'n_tickets_refinados', v_n_tickets_refinados,
      'n_descartados_grandes', v_n_descartados_grandes,
      'n_tickets_descartados_grandes', v_n_tickets_descartados_grandes,
      'n_descartados_pequenos', v_n_descartados_pequenos,
      'threshold_recall', p_threshold,
      'threshold_coesao', v_coesao_threshold,
      'algoritmo', 'v5-complete-medoid',
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  WITH grupos AS (
    SELECT g.*, gen_random_uuid() AS cluster_id
    FROM _grupos g
    ORDER BY g.tamanho DESC, g.coesao_media DESC
  ),
  inserts AS (
    INSERT INTO public.ticket_clusters (
      id, equipe_id, total_satelites, total_livres,
      categorias, subcategorias, gses, centroid_ticket_id,
      algoritmo_versao, threshold, resumo_status
    )
    SELECT
      g.cluster_id,
      p_equipe_id,
      g.tamanho,
      (SELECT count(*) FROM public.tickets t
        WHERE t.id = ANY(g.membros)
          AND t.status = 'aguardando'
          AND t.usuario_atual IS NULL
          AND t.mantido_por IS NULL),
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
        WHEN g.refinado THEN 'v5-complete-medoid-refine-max' || p_max_satelites::text
        ELSE 'v5-complete-medoid-max' || p_max_satelites::text
      END,
      g.threshold_usado,
      'pendente'
    FROM grupos g
    RETURNING id
  )
  INSERT INTO public.ticket_cluster_membros (cluster_id, ticket_id, similaridade)
  SELECT
    g.cluster_id,
    t_id,
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
    'n_tickets_com_subcategoria', v_n_com_subcategoria,
    'n_componentes_gigantes', v_n_componentes_gigantes,
    'n_componentes_refinados', v_n_componentes_refinados,
    'n_clusters_refinados', v_n_clusters_refinados,
    'n_tickets_refinados', v_n_tickets_refinados,
    'n_descartados_grandes', v_n_descartados_grandes,
    'n_tickets_descartados_grandes', v_n_tickets_descartados_grandes,
    'n_descartados_pequenos', v_n_descartados_pequenos,
    'threshold_recall', p_threshold,
    'threshold_coesao', v_coesao_threshold,
    'algoritmo', 'v5-complete-medoid',
    'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) IS
  'Agrupa tickets livres por embeddings dentro da mesma subcategoria. Desde v5, divide componentes por coesao complete-link e usa medoid real para evitar planetas formados por pontes semanticas.';
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
  WITH membros_rankeados AS (
    SELECT
      c.id AS cluster_id,
      t.numero_chamado,
      t.descricao,
      m.similaridade,
      row_number() OVER (PARTITION BY c.id ORDER BY m.similaridade DESC, t.numero_chamado) AS rn_central,
      row_number() OVER (PARTITION BY c.id ORDER BY m.similaridade ASC, t.numero_chamado) AS rn_periferico
    FROM public.ticket_clusters c
    JOIN public.ticket_cluster_membros m ON m.cluster_id = c.id
    JOIN public.tickets t ON t.id = m.ticket_id
    WHERE c.equipe_id = p_equipe_id
      AND c.resumo_status IN ('pendente','erro')
      AND t.status = 'aguardando'
      AND t.usuario_atual IS NULL
  ),
  amostras AS (
    SELECT DISTINCT ON (cluster_id, numero_chamado)
      cluster_id,
      numero_chamado,
      descricao,
      similaridade,
      CASE WHEN rn_central <= 3 THEN rn_central ELSE 100 + rn_periferico END AS ordem
    FROM membros_rankeados
    WHERE rn_central <= 3 OR rn_periferico <= 2
    ORDER BY cluster_id, numero_chamado, ordem
  )
  SELECT
    c.id,
    COALESCE(
      jsonb_agg(jsonb_build_object(
        'numero_chamado', a.numero_chamado,
        'descricao', LEFT(a.descricao, 800)
      ) ORDER BY a.ordem, a.similaridade DESC) FILTER (WHERE a.numero_chamado IS NOT NULL),
      '[]'::jsonb
    ) AS amostras
  FROM public.ticket_clusters c
  LEFT JOIN amostras a ON a.cluster_id = c.id
  WHERE c.equipe_id = p_equipe_id
    AND c.resumo_status IN ('pendente','erro')
  GROUP BY c.id;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_pendentes_resumo(uuid) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_pendentes_resumo(uuid) IS
  'Lista clusters pendentes de resumo com amostras centrais e perifericas para reduzir resumos puxados por um unico satelite.';

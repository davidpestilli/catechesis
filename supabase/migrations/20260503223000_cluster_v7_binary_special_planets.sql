-- ============================================================
-- Migracao: Sistema Solar v7 - binarios residuais como planetas especiais
-- Data: 2026-05-03
--
-- Objetivo:
--   Preservar o pipeline v6 para planetas regulares (3+ satelites) e,
--   ao final da clusterizacao, promover pares residuais altamente coesos
--   a planetas especiais binarios, sem criar uma nova hierarquia.
--
-- Estrategia:
--   1. Mantem o recall global + pair-seed + complete-link do v6.
--   2. Continua tentando formar primeiro os planetas regulares com minimo 3.
--   3. Depois da reatribuicao dos orfaos aos planetas regulares, busca nos
--      remanescentes pares nao sobrepostos com similaridade >= threshold.
--   4. Persiste esses pares como clusters de tamanho 2 na mesma tabela
--      `ticket_clusters`, marcando a versao do algoritmo como binaria.
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
  v_n_clusters_binarios integer := 0;
  v_n_tickets_binarios integer := 0;
  v_lock_key bigint;
  v_changed integer;
  v_iter integer;
  v_frontier record;
  v_seed_a uuid;
  v_seed_b uuid;
  v_candidate uuid;
  v_attach_ticket uuid;
  v_attach_group_id bigint;
  v_remaining_count integer;
  v_group_count integer;
  v_group_members uuid[];
  v_threshold real;
  v_min_regular_satelites integer := 3;
BEGIN
  IF p_min_satelites IS NULL OR p_min_satelites < 2 THEN
    p_min_satelites := 3;
  END IF;

  v_min_regular_satelites := GREATEST(3, p_min_satelites);

  -- Mantido por compatibilidade com a API atual; a v7 nao usa top-k,
  -- pois a compatibilidade inicial e global entre todos os candidatos.
  IF p_top_k IS NULL OR p_top_k < 1 THEN
    p_top_k := 20;
  END IF;

  IF p_max_satelites IS NULL OR p_max_satelites < v_min_regular_satelites THEN
    p_max_satelites := GREATEST(120, v_min_regular_satelites);
  END IF;

  IF p_threshold IS NULL THEN
    p_threshold := 0.85;
  END IF;

  -- Piso operacional: qualquer planeta final, inclusive binarios, precisa
  -- respeitar no minimo 0.88 de coesao. Thresholds acima disso endurecem
  -- tanto os planetas regulares quanto os binarios residuais.
  v_threshold := LEAST(0.97::real, GREATEST(0.88::real, p_threshold::real));

  v_lock_key := ('x' || substr(md5('cluster:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  DELETE FROM public.ticket_clusters WHERE equipe_id = p_equipe_id;

  DROP TABLE IF EXISTS _candidatos, _pair_sims, _uf, _componentes,
    _frontier, _remaining, _current_group, _grupos;

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
      AND lower(regexp_replace(BTRIM(t.descricao), '[[:space:]]+', ' ', 'g')) NOT IN (
        'descrição não encontrada',
        'descricao nao encontrada',
        'sem descrição',
        'sem descricao',
        'não informado',
        'nao informado',
        'description not found'
      );

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
      'n_clusters_binarios', 0,
      'n_tickets_binarios', 0,
      'n_descartados_grandes', 0,
      'n_tickets_descartados_grandes', 0,
      'n_descartados_pequenos', 0,
      'threshold_recall', v_threshold,
      'threshold_coesao', v_threshold,
      'algoritmo', 'v7-global-complete-pairseed-binarios',
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  CREATE INDEX ON _candidatos(ticket_id);

  CREATE TEMP TABLE _pair_sims ON COMMIT DROP AS
    SELECT
      a.ticket_id AS a_id,
      b.ticket_id AS b_id,
      (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _candidatos a
    JOIN _candidatos b ON a.ticket_id < b.ticket_id
    WHERE (1 - (a.embedding <=> b.embedding)) >= v_threshold;

  CREATE INDEX ON _pair_sims(a_id);
  CREATE INDEX ON _pair_sims(b_id);

  CREATE TEMP TABLE _uf (ticket_id uuid PRIMARY KEY, root uuid NOT NULL) ON COMMIT DROP;
  INSERT INTO _uf(ticket_id, root) SELECT ticket_id, ticket_id FROM _candidatos;

  v_changed := 1;
  v_iter := 0;
  WHILE v_changed > 0 AND v_iter < 50 LOOP
    WITH pares AS (
      SELECT DISTINCT ua.root AS ra, ub.root AS rb
      FROM _pair_sims e
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

  SELECT count(*) INTO v_n_componentes_gigantes
  FROM _componentes
  WHERE tamanho > p_max_satelites;

  CREATE TEMP TABLE _frontier (
    origem_root uuid PRIMARY KEY,
    membros uuid[] NOT NULL,
    tamanho integer NOT NULL,
    threshold_usado real NOT NULL
  ) ON COMMIT DROP;

  INSERT INTO _frontier(origem_root, membros, tamanho, threshold_usado)
  SELECT root, membros, tamanho, v_threshold
  FROM _componentes
  WHERE tamanho >= 2;

  CREATE TEMP TABLE _remaining (ticket_id uuid PRIMARY KEY) ON COMMIT DROP;
  CREATE TEMP TABLE _current_group (ticket_id uuid PRIMARY KEY) ON COMMIT DROP;

  CREATE TEMP TABLE _grupos (
    grupo_id bigserial PRIMARY KEY,
    membros uuid[] NOT NULL,
    tamanho integer NOT NULL,
    threshold_usado real NOT NULL,
    origem_root uuid NOT NULL,
    refinado boolean NOT NULL DEFAULT false,
    binario boolean NOT NULL DEFAULT false
  ) ON COMMIT DROP;

  LOOP
    SELECT * INTO v_frontier
    FROM _frontier
    ORDER BY tamanho DESC, origem_root
    LIMIT 1;

    EXIT WHEN NOT FOUND;

    DELETE FROM _frontier WHERE origem_root = v_frontier.origem_root;

    TRUNCATE _remaining, _current_group;

    INSERT INTO _remaining(ticket_id)
    SELECT unnest(v_frontier.membros);

    LOOP
      SELECT count(*) INTO v_remaining_count FROM _remaining;
      EXIT WHEN v_remaining_count < v_min_regular_satelites;

      SELECT cand.a_id, cand.b_id
      INTO v_seed_a, v_seed_b
      FROM (
        SELECT
          e.a_id,
          e.b_id,
          e.sim,
          (
            SELECT count(*)
            FROM _remaining r
            WHERE r.ticket_id <> e.a_id
              AND r.ticket_id <> e.b_id
              AND EXISTS (
                SELECT 1
                FROM _pair_sims sa
                WHERE sa.a_id = LEAST(e.a_id, r.ticket_id)
                  AND sa.b_id = GREATEST(e.a_id, r.ticket_id)
                  AND sa.sim >= v_frontier.threshold_usado
              )
              AND EXISTS (
                SELECT 1
                FROM _pair_sims sb
                WHERE sb.a_id = LEAST(e.b_id, r.ticket_id)
                  AND sb.b_id = GREATEST(e.b_id, r.ticket_id)
                  AND sb.sim >= v_frontier.threshold_usado
              )
          ) AS common_count,
          (
            SELECT count(*)
            FROM _remaining r
            WHERE r.ticket_id <> e.a_id
              AND EXISTS (
                SELECT 1
                FROM _pair_sims sa
                WHERE sa.a_id = LEAST(e.a_id, r.ticket_id)
                  AND sa.b_id = GREATEST(e.a_id, r.ticket_id)
                  AND sa.sim >= v_frontier.threshold_usado
              )
          ) + (
            SELECT count(*)
            FROM _remaining r
            WHERE r.ticket_id <> e.b_id
              AND EXISTS (
                SELECT 1
                FROM _pair_sims sb
                WHERE sb.a_id = LEAST(e.b_id, r.ticket_id)
                  AND sb.b_id = GREATEST(e.b_id, r.ticket_id)
                  AND sb.sim >= v_frontier.threshold_usado
              )
          ) AS degree_sum
        FROM _pair_sims e
        WHERE e.sim >= v_frontier.threshold_usado
          AND EXISTS (SELECT 1 FROM _remaining ra WHERE ra.ticket_id = e.a_id)
          AND EXISTS (SELECT 1 FROM _remaining rb WHERE rb.ticket_id = e.b_id)
      ) cand
      WHERE cand.common_count + 2 >= v_min_regular_satelites
      ORDER BY cand.common_count DESC, cand.sim DESC, cand.degree_sum DESC, cand.a_id, cand.b_id
      LIMIT 1;

      EXIT WHEN NOT FOUND;

      TRUNCATE _current_group;
      INSERT INTO _current_group(ticket_id) VALUES (v_seed_a), (v_seed_b);
      DELETE FROM _remaining WHERE ticket_id IN (v_seed_a, v_seed_b);

      LOOP
        SELECT count(*) INTO v_group_count FROM _current_group;
        EXIT WHEN v_group_count >= p_max_satelites;

        SELECT cand.ticket_id
        INTO v_candidate
        FROM (
          SELECT
            r.ticket_id,
            (
              SELECT avg(s.sim)
              FROM _current_group g
              JOIN _pair_sims s
                ON s.a_id = LEAST(g.ticket_id, r.ticket_id)
               AND s.b_id = GREATEST(g.ticket_id, r.ticket_id)
              WHERE s.sim >= v_frontier.threshold_usado
            ) AS avg_sim,
            (
              SELECT count(*)
              FROM _remaining o
              WHERE o.ticket_id <> r.ticket_id
                AND EXISTS (
                  SELECT 1
                  FROM _pair_sims so
                  WHERE so.a_id = LEAST(o.ticket_id, r.ticket_id)
                    AND so.b_id = GREATEST(o.ticket_id, r.ticket_id)
                    AND so.sim >= v_frontier.threshold_usado
                )
            ) AS degree_sum
          FROM _remaining r
          WHERE NOT EXISTS (
            SELECT 1
            FROM _current_group g
            LEFT JOIN _pair_sims s
              ON s.a_id = LEAST(g.ticket_id, r.ticket_id)
             AND s.b_id = GREATEST(g.ticket_id, r.ticket_id)
            WHERE COALESCE(s.sim, 0) < v_frontier.threshold_usado
          )
        ) cand
        ORDER BY cand.avg_sim DESC NULLS LAST, cand.degree_sum DESC, cand.ticket_id
        LIMIT 1;

        EXIT WHEN NOT FOUND;

        INSERT INTO _current_group(ticket_id) VALUES (v_candidate);
        DELETE FROM _remaining WHERE ticket_id = v_candidate;
      END LOOP;

      SELECT count(*), array_agg(ticket_id ORDER BY ticket_id)
      INTO v_group_count, v_group_members
      FROM _current_group;

      IF v_group_count >= v_min_regular_satelites THEN
        INSERT INTO _grupos(membros, tamanho, threshold_usado, origem_root, binario)
        VALUES (v_group_members, v_group_count, v_frontier.threshold_usado, v_frontier.origem_root, false);
      ELSE
        v_n_descartados_pequenos := v_n_descartados_pequenos + v_group_count;
      END IF;
    END LOOP;

    LOOP
      SELECT cand.ticket_id, cand.grupo_id
      INTO v_attach_ticket, v_attach_group_id
      FROM (
        SELECT
          r.ticket_id,
          g.grupo_id,
          g.tamanho,
          (
            SELECT avg(s.sim)
            FROM unnest(g.membros) AS member(member_id)
            JOIN _pair_sims s
              ON s.a_id = LEAST(member.member_id, r.ticket_id)
             AND s.b_id = GREATEST(member.member_id, r.ticket_id)
            WHERE s.sim >= g.threshold_usado
          ) AS avg_sim
        FROM _remaining r
        JOIN _grupos g
          ON g.origem_root = v_frontier.origem_root
         AND g.tamanho < p_max_satelites
         AND NOT g.binario
        WHERE NOT EXISTS (
          SELECT 1
          FROM unnest(g.membros) AS member(member_id)
          LEFT JOIN _pair_sims s
            ON s.a_id = LEAST(member.member_id, r.ticket_id)
           AND s.b_id = GREATEST(member.member_id, r.ticket_id)
          WHERE COALESCE(s.sim, 0) < g.threshold_usado
        )
      ) cand
      ORDER BY cand.avg_sim DESC NULLS LAST, cand.tamanho ASC, cand.ticket_id, cand.grupo_id
      LIMIT 1;

      EXIT WHEN NOT FOUND;

      UPDATE _grupos
      SET membros = array_append(membros, v_attach_ticket),
          tamanho = tamanho + 1
      WHERE grupo_id = v_attach_group_id;

      DELETE FROM _remaining WHERE ticket_id = v_attach_ticket;
    END LOOP;

    LOOP
      SELECT e.a_id, e.b_id
      INTO v_seed_a, v_seed_b
      FROM _pair_sims e
      WHERE e.sim >= v_frontier.threshold_usado
        AND EXISTS (SELECT 1 FROM _remaining ra WHERE ra.ticket_id = e.a_id)
        AND EXISTS (SELECT 1 FROM _remaining rb WHERE rb.ticket_id = e.b_id)
      ORDER BY e.sim DESC, e.a_id, e.b_id
      LIMIT 1;

      EXIT WHEN NOT FOUND;

      INSERT INTO _grupos(membros, tamanho, threshold_usado, origem_root, binario)
      VALUES (ARRAY[v_seed_a, v_seed_b]::uuid[], 2, v_frontier.threshold_usado, v_frontier.origem_root, true);

      DELETE FROM _remaining WHERE ticket_id IN (v_seed_a, v_seed_b);
    END LOOP;

    SELECT count(*) INTO v_remaining_count FROM _remaining;
    v_n_descartados_pequenos := v_n_descartados_pequenos + COALESCE(v_remaining_count, 0);
  END LOOP;

  SELECT count(*)::integer, COALESCE(sum(tamanho), 0)::integer
  INTO v_n_clusters, v_n_agrupados
  FROM _grupos;

  SELECT count(*)::integer, COALESCE(sum(tamanho), 0)::integer
  INTO v_n_clusters_binarios, v_n_tickets_binarios
  FROM _grupos
  WHERE binario;

  SELECT
    count(*)::integer,
    COALESCE(sum(n_clusters), 0)::integer,
    COALESCE(sum(n_tickets), 0)::integer
  INTO v_n_componentes_refinados, v_n_clusters_refinados, v_n_tickets_refinados
  FROM (
    SELECT origem_root, count(*)::integer AS n_clusters, sum(tamanho)::integer AS n_tickets
    FROM _grupos
    GROUP BY origem_root
    HAVING count(*) > 1
  ) split_origins;

  IF v_n_clusters = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0,
      'n_tickets_agrupados', 0,
      'n_tickets_avaliados', v_n_avaliados,
      'n_tickets_com_subcategoria', v_n_com_subcategoria,
      'n_componentes_gigantes', v_n_componentes_gigantes,
      'n_componentes_refinados', COALESCE(v_n_componentes_refinados, 0),
      'n_clusters_refinados', COALESCE(v_n_clusters_refinados, 0),
      'n_tickets_refinados', COALESCE(v_n_tickets_refinados, 0),
      'n_clusters_binarios', 0,
      'n_tickets_binarios', 0,
      'n_descartados_grandes', 0,
      'n_tickets_descartados_grandes', 0,
      'n_descartados_pequenos', v_n_descartados_pequenos,
      'threshold_recall', v_threshold,
      'threshold_coesao', v_threshold,
      'algoritmo', 'v7-global-complete-pairseed-binarios',
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  WITH grupos AS (
    SELECT
      g.grupo_id,
      g.membros,
      g.tamanho,
      g.threshold_usado,
      g.refinado,
      g.binario,
      gen_random_uuid() AS cluster_id,
      (
        SELECT member.member_id
        FROM unnest(g.membros) AS member(member_id)
        ORDER BY (
          SELECT avg(
            CASE
              WHEN other.member_id = member.member_id THEN 1::real
              ELSE COALESCE(s.sim, 0)
            END
          )
          FROM unnest(g.membros) AS other(member_id)
          LEFT JOIN _pair_sims s
            ON s.a_id = LEAST(member.member_id, other.member_id)
           AND s.b_id = GREATEST(member.member_id, other.member_id)
        ) DESC, member.member_id
        LIMIT 1
      ) AS medoid,
      (
        SELECT COALESCE(min(s.sim), 1::real)
        FROM unnest(g.membros) AS a(member_id)
        JOIN unnest(g.membros) AS b(member_id) ON a.member_id < b.member_id
        JOIN _pair_sims s
          ON s.a_id = LEAST(a.member_id, b.member_id)
         AND s.b_id = GREATEST(a.member_id, b.member_id)
      ) AS coesao_min,
      (
        SELECT COALESCE(avg(s.sim), 1::real)
        FROM unnest(g.membros) AS a(member_id)
        JOIN unnest(g.membros) AS b(member_id) ON a.member_id < b.member_id
        JOIN _pair_sims s
          ON s.a_id = LEAST(a.member_id, b.member_id)
         AND s.b_id = GREATEST(a.member_id, b.member_id)
      ) AS coesao_media
    FROM _grupos g
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
      g.medoid,
      CASE
        WHEN g.binario THEN 'v7-global-complete-pairseed-binary-max' || p_max_satelites::text
        WHEN g.refinado THEN 'v7-global-complete-pairseed-refine-max' || p_max_satelites::text
        ELSE 'v7-global-complete-pairseed-max' || p_max_satelites::text
      END,
      g.threshold_usado,
      'pendente'
    FROM grupos g
    ORDER BY g.tamanho DESC, g.coesao_media DESC
    RETURNING id
  )
  INSERT INTO public.ticket_cluster_membros (cluster_id, ticket_id, similaridade)
  SELECT
    g.cluster_id,
    t_id,
    COALESCE((1 - (
      (SELECT embedding FROM public.ticket_embeddings WHERE ticket_id = t_id)
      <=>
      (SELECT embedding FROM public.ticket_embeddings WHERE ticket_id = g.medoid)
    ))::real, 0)
  FROM grupos g
  CROSS JOIN LATERAL unnest(g.membros) AS t_id;

  RETURN jsonb_build_object(
    'n_clusters', v_n_clusters,
    'n_tickets_agrupados', v_n_agrupados,
    'n_tickets_avaliados', v_n_avaliados,
    'n_tickets_com_subcategoria', v_n_com_subcategoria,
    'n_componentes_gigantes', v_n_componentes_gigantes,
    'n_componentes_refinados', COALESCE(v_n_componentes_refinados, 0),
    'n_clusters_refinados', COALESCE(v_n_clusters_refinados, 0),
    'n_tickets_refinados', COALESCE(v_n_tickets_refinados, 0),
    'n_clusters_binarios', v_n_clusters_binarios,
    'n_tickets_binarios', v_n_tickets_binarios,
    'n_descartados_grandes', 0,
    'n_tickets_descartados_grandes', 0,
    'n_descartados_pequenos', v_n_descartados_pequenos,
    'threshold_recall', v_threshold,
    'threshold_coesao', v_threshold,
    'algoritmo', 'v7-global-complete-pairseed-binarios',
    'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) IS
  'Agrupa tickets livres com recall global e complete-link por pair-seed. Desde v7, pares residuais altamente coesos tambem viram planetas binarios especiais na mesma tabela ticket_clusters.';

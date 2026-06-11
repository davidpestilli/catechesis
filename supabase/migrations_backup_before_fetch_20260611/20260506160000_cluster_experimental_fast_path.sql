-- ============================================================
-- Migracao: Sistema Solar - caminho rapido para threshold experimental
-- Data: 2026-05-06
--
-- Objetivo:
--   Thresholds abaixo de 0.88 podem criar grafos muito densos e fazer a
--   fase complete-link ultrapassar o timeout HTTP/RPC. Para esses thresholds
--   experimentais, a RPC passa a usar componentes conexas do grafo top-K,
--   divididas por p_max_satelites. Thresholds 0.88+ seguem no caminho v7
--   estrito, sem alteracao de comportamento.
-- ============================================================

SET search_path TO public, extensions;
DO $$
DECLARE
  v_function_sql text;
  v_anchor text := '  CREATE INDEX ON _pair_sims(a_id);
  CREATE INDEX ON _pair_sims(b_id);';
  v_fast_path text := '  CREATE INDEX ON _pair_sims(a_id);
  CREATE INDEX ON _pair_sims(b_id);

  IF v_threshold < 0.88::real THEN
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

    CREATE TEMP TABLE _grupos (
      grupo_id bigserial PRIMARY KEY,
      membros uuid[] NOT NULL,
      tamanho integer NOT NULL,
      threshold_usado real NOT NULL,
      origem_root uuid NOT NULL,
      refinado boolean NOT NULL DEFAULT false,
      binario boolean NOT NULL DEFAULT false
    ) ON COMMIT DROP;

    WITH membros_componentes AS (
      SELECT
        c.root,
        u.ticket_id,
        u.ord,
        ((u.ord - 1) / p_max_satelites)::integer AS chunk_id
      FROM _componentes c
      CROSS JOIN LATERAL unnest(c.membros) WITH ORDINALITY AS u(ticket_id, ord)
    ), grupos_componentes AS (
      SELECT
        root,
        chunk_id,
        array_agg(ticket_id ORDER BY ord) AS membros,
        count(*)::integer AS tamanho
      FROM membros_componentes
      GROUP BY root, chunk_id
      HAVING count(*) >= 2
    )
    INSERT INTO _grupos(membros, tamanho, threshold_usado, origem_root, refinado, binario)
    SELECT membros, tamanho, v_threshold, root, tamanho > p_max_satelites, tamanho = 2
    FROM grupos_componentes
    ORDER BY tamanho DESC, root, chunk_id;

    SELECT count(*)::integer, COALESCE(sum(tamanho), 0)::integer
    INTO v_n_clusters, v_n_agrupados
    FROM _grupos;

    v_n_descartados_pequenos := GREATEST(0, v_n_avaliados - v_n_agrupados);

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
        ''n_clusters'', 0,
        ''n_tickets_agrupados'', 0,
        ''n_tickets_avaliados'', v_n_avaliados,
        ''n_tickets_com_subcategoria'', v_n_com_subcategoria,
        ''n_componentes_gigantes'', v_n_componentes_gigantes,
        ''n_componentes_refinados'', 0,
        ''n_clusters_refinados'', 0,
        ''n_tickets_refinados'', 0,
        ''n_clusters_binarios'', 0,
        ''n_tickets_binarios'', 0,
        ''n_descartados_grandes'', 0,
        ''n_tickets_descartados_grandes'', 0,
        ''n_descartados_pequenos'', v_n_descartados_pequenos,
        ''threshold_recall'', v_threshold,
        ''threshold_coesao'', v_threshold,
        ''algoritmo'', ''v7-experimental-topk-components'',
        ''segundos'', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
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
                ELSE COALESCE((1 - (em.embedding <=> eo.embedding))::real, 0)
              END
            )
            FROM unnest(g.membros) AS other(member_id)
            LEFT JOIN public.ticket_embeddings em ON em.ticket_id = member.member_id
            LEFT JOIN public.ticket_embeddings eo ON eo.ticket_id = other.member_id
          ) DESC, member.member_id
          LIMIT 1
        ) AS medoid,
        (
          SELECT COALESCE(min(COALESCE(s.sim, v_threshold)), v_threshold)
          FROM unnest(g.membros) AS a(member_id)
          JOIN unnest(g.membros) AS b(member_id) ON a.member_id < b.member_id
          LEFT JOIN _pair_sims s
            ON s.a_id = LEAST(a.member_id, b.member_id)
           AND s.b_id = GREATEST(a.member_id, b.member_id)
        ) AS coesao_min,
        (
          SELECT COALESCE(avg(COALESCE(s.sim, v_threshold)), v_threshold)
          FROM unnest(g.membros) AS a(member_id)
          JOIN unnest(g.membros) AS b(member_id) ON a.member_id < b.member_id
          LEFT JOIN _pair_sims s
            ON s.a_id = LEAST(a.member_id, b.member_id)
           AND s.b_id = GREATEST(a.member_id, b.member_id)
        ) AS coesao_media
      FROM _grupos g
    ), inserts AS (
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
            AND t.status = ''aguardando''
            AND t.usuario_atual IS NULL
            AND t.mantido_por IS NULL),
        (SELECT COALESCE(jsonb_agg(jsonb_build_object(''id'', x.cat_id, ''nome'', x.cat_nome, ''count'', x.c) ORDER BY x.c DESC), ''[]''::jsonb)
          FROM (
            SELECT ce.id AS cat_id, ce.nome AS cat_nome, count(*)::int AS c
            FROM public.tickets t
            LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
            LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
            WHERE t.id = ANY(g.membros) GROUP BY ce.id, ce.nome
          ) x),
        (SELECT COALESCE(jsonb_agg(jsonb_build_object(''id'', x.sub_id, ''nome'', x.sub_nome, ''count'', x.c) ORDER BY x.c DESC), ''[]''::jsonb)
          FROM (
            SELECT sg.id AS sub_id, sg.nome AS sub_nome, count(*)::int AS c
            FROM public.tickets t
            LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
            LEFT JOIN public.subcategorias_gse sg ON sg.id = ta.subcategoria_gse_id
            WHERE t.id = ANY(g.membros) GROUP BY sg.id, sg.nome
          ) x),
        (SELECT COALESCE(jsonb_agg(jsonb_build_object(''gse'', x.gse, ''count'', x.c) ORDER BY x.c DESC), ''[]''::jsonb)
          FROM (
            SELECT t.gse, count(*)::int AS c FROM public.tickets t
            WHERE t.id = ANY(g.membros) GROUP BY t.gse
          ) x),
        g.medoid,
        CASE
          WHEN g.binario THEN ''v7-experimental-topk-components-binary-max'' || p_max_satelites::text
          WHEN g.refinado THEN ''v7-experimental-topk-components-split-max'' || p_max_satelites::text
          ELSE ''v7-experimental-topk-components-max'' || p_max_satelites::text
        END,
        g.threshold_usado,
        ''pendente''
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
      ''n_clusters'', v_n_clusters,
      ''n_tickets_agrupados'', v_n_agrupados,
      ''n_tickets_avaliados'', v_n_avaliados,
      ''n_tickets_com_subcategoria'', v_n_com_subcategoria,
      ''n_componentes_gigantes'', v_n_componentes_gigantes,
      ''n_componentes_refinados'', COALESCE(v_n_componentes_refinados, 0),
      ''n_clusters_refinados'', COALESCE(v_n_clusters_refinados, 0),
      ''n_tickets_refinados'', COALESCE(v_n_tickets_refinados, 0),
      ''n_clusters_binarios'', v_n_clusters_binarios,
      ''n_tickets_binarios'', v_n_tickets_binarios,
      ''n_descartados_grandes'', 0,
      ''n_tickets_descartados_grandes'', 0,
      ''n_descartados_pequenos'', v_n_descartados_pequenos,
      ''threshold_recall'', v_threshold,
      ''threshold_coesao'', v_threshold,
      ''algoritmo'', ''v7-experimental-topk-components'',
      ''segundos'', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;';
BEGIN
  SELECT pg_get_functiondef('public.cluster_tickets_equipe(uuid, real, integer, integer, integer)'::regprocedure)
  INTO v_function_sql;

  IF v_function_sql IS NULL THEN
    RAISE EXCEPTION 'Funcao public.cluster_tickets_equipe(uuid, real, integer, integer, integer) nao encontrada';
  END IF;

  IF position('v7-experimental-topk-components' IN v_function_sql) > 0 THEN
    RAISE NOTICE 'cluster_tickets_equipe ja possui caminho experimental rapido; nenhuma alteracao necessaria.';
    RETURN;
  END IF;

  IF position(v_anchor IN v_function_sql) = 0 THEN
    RAISE NOTICE 'Ancora dos indices _pair_sims nao encontrada; mantendo definicao atual.';
    RETURN;
  END IF;

  v_function_sql := replace(v_function_sql, v_anchor, v_fast_path);

  EXECUTE v_function_sql;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) IS
  'Agrupa tickets livres com recall global e complete-link por pair-seed. Thresholds 0.88+ usam o caminho v7 estrito; thresholds experimentais abaixo de 0.88 usam componentes top-K para evitar timeout/upstream failed.';

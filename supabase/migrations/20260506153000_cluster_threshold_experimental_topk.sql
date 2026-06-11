-- ============================================================
-- Migracao: Sistema Solar - limitar arestas em thresholds experimentais
-- Data: 2026-05-06
--
-- Objetivo:
--   Evitar timeout/upstream failed quando o usuario testa thresholds muito
--   baixos (ex.: 0.50). Para thresholds abaixo do piso historico 0.88,
--   a RPC passa a manter somente as top-K conexoes mais similares por
--   ticket. Para 0.88+, o comportamento permanece exato como antes.
-- ============================================================

SET search_path TO public, extensions;
DO $$
DECLARE
  v_function_sql text;
  v_old_block text := 'CREATE TEMP TABLE _pair_sims ON COMMIT DROP AS
    SELECT
      a.ticket_id AS a_id,
      b.ticket_id AS b_id,
      (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _candidatos a
    JOIN _candidatos b ON a.ticket_id < b.ticket_id
    WHERE (1 - (a.embedding <=> b.embedding)) >= v_threshold;';
  v_new_block text := 'CREATE TEMP TABLE _pair_sims ON COMMIT DROP AS
    WITH scored AS (
      SELECT
        a.ticket_id AS a_id,
        b.ticket_id AS b_id,
        (1 - (a.embedding <=> b.embedding))::real AS sim
      FROM _candidatos a
      JOIN _candidatos b ON a.ticket_id < b.ticket_id
      WHERE (1 - (a.embedding <=> b.embedding)) >= v_threshold
    ), ranked AS (
      SELECT
        scored.*,
        row_number() OVER (PARTITION BY a_id ORDER BY sim DESC, b_id) AS rn_a,
        row_number() OVER (PARTITION BY b_id ORDER BY sim DESC, a_id) AS rn_b
      FROM scored
    )
    SELECT a_id, b_id, sim
    FROM ranked
    WHERE v_threshold >= 0.88::real
       OR rn_a <= p_top_k
       OR rn_b <= p_top_k;';
BEGIN
  SELECT pg_get_functiondef('public.cluster_tickets_equipe(uuid, real, integer, integer, integer)'::regprocedure)
  INTO v_function_sql;

  IF v_function_sql IS NULL THEN
    RAISE EXCEPTION 'Funcao public.cluster_tickets_equipe(uuid, real, integer, integer, integer) nao encontrada';
  END IF;

  IF position('WITH scored AS (' IN v_function_sql) > 0
     AND position('rn_a <= p_top_k' IN v_function_sql) > 0 THEN
    RAISE NOTICE 'cluster_tickets_equipe ja limita top-K em thresholds experimentais; nenhuma alteracao necessaria.';
    RETURN;
  END IF;

  IF position(v_old_block IN v_function_sql) = 0 THEN
    RAISE NOTICE 'Bloco _pair_sims esperado nao encontrado; mantendo definicao atual.';
    RETURN;
  END IF;

  v_function_sql := replace(v_function_sql, v_old_block, v_new_block);

  EXECUTE v_function_sql;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) IS
  'Agrupa tickets livres com recall global e complete-link por pair-seed. Thresholds experimentais abaixo de 0.88 limitam o grafo aos top-K vizinhos por ticket para evitar timeout; 0.88+ preserva o comportamento exato.';

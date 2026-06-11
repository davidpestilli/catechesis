-- ============================================================
-- Migracao: Sistema Solar - permitir threshold experimental 0.50
-- Data: 2026-05-06
--
-- Objetivo:
--   Liberar testes com threshold de planetas abaixo do piso operacional
--   anterior (0.88), mantendo o teto em 0.97.
-- ============================================================

SET search_path TO public, extensions;
DO $$
DECLARE
  v_function_sql text;
  v_old_floor text := 'GREATEST(0.88::real, p_threshold::real)';
  v_new_floor text := 'GREATEST(0.50::real, p_threshold::real)';
BEGIN
  SELECT pg_get_functiondef('public.cluster_tickets_equipe(uuid, real, integer, integer, integer)'::regprocedure)
  INTO v_function_sql;

  IF v_function_sql IS NULL THEN
    RAISE EXCEPTION 'Funcao public.cluster_tickets_equipe(uuid, real, integer, integer, integer) nao encontrada';
  END IF;

  IF position(v_new_floor IN v_function_sql) > 0 THEN
    RAISE NOTICE 'cluster_tickets_equipe ja permite threshold minimo 0.50; nenhuma alteracao necessaria.';
    RETURN;
  END IF;

  IF position(v_old_floor IN v_function_sql) = 0 THEN
    RAISE NOTICE 'cluster_tickets_equipe nao possui piso interno 0.88; mantendo definicao atual.';
  ELSE
    v_function_sql := replace(v_function_sql, v_old_floor, v_new_floor);
    v_function_sql := replace(
      v_function_sql,
      'Piso operacional: qualquer planeta final, inclusive binarios, precisa
  -- respeitar no minimo 0.88 de coesao. Thresholds acima disso endurecem
  -- tanto os planetas regulares quanto os binarios residuais.',
      'Piso experimental: permite testes exploratorios a partir de 0.50.
  -- Thresholds mais baixos aumentam recall e podem gerar orbitas maiores;
  -- o teto em 0.97 segue protegendo chamadas acima do limite operacional.'
    );

    EXECUTE v_function_sql;
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer, integer) IS
  'Agrupa tickets livres com recall global e complete-link por pair-seed. Desde 2026-05-06, aceita threshold experimental a partir de 0.50; pares residuais coesos continuam virando planetas binarios especiais.';

-- =====================================================
-- SOS: metricas de atendidos no modal Palavras SOS
-- Hoje: 00:00-23:59 do dia atual (America/Sao_Paulo)
-- Semana: domingo 00:00 ate sabado 23:59 da semana vigente
-- =====================================================

CREATE OR REPLACE FUNCTION public.sos_obter_metricas_atendidos(p_equipe_id uuid)
RETURNS TABLE(
  atendidos_hoje bigint,
  atendidos_semana bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_gses text[];
  v_timezone constant text := 'America/Sao_Paulo';
  v_hoje_inicio timestamp without time zone;
  v_amanha_inicio timestamp without time zone;
  v_semana_inicio timestamp without time zone;
  v_proxima_semana_inicio timestamp without time zone;
BEGIN
  IF NOT public.tem_permissao('distribuidor.sos_keywords') THEN
    RAISE EXCEPTION 'Apenas usuarios autorizados podem consultar metricas SOS';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatorio para metricas SOS';
  END IF;

  SELECT array_agg(ge.gse) INTO v_gses
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  IF v_gses IS NULL OR array_length(v_gses, 1) IS NULL THEN
    RETURN QUERY SELECT 0::bigint, 0::bigint;
    RETURN;
  END IF;

  v_hoje_inicio := (now() AT TIME ZONE v_timezone)::date::timestamp;
  v_amanha_inicio := v_hoje_inicio + interval '1 day';

  -- EXTRACT(DOW): domingo=0 ... sabado=6
  v_semana_inicio := (v_hoje_inicio::date - EXTRACT(DOW FROM v_hoje_inicio)::int)::timestamp;
  v_proxima_semana_inicio := v_semana_inicio + interval '7 day';

  RETURN QUERY
  SELECT
    COUNT(*) FILTER (
      WHERE (t.finished_at AT TIME ZONE v_timezone) >= v_hoje_inicio
        AND (t.finished_at AT TIME ZONE v_timezone) < v_amanha_inicio
    )::bigint AS atendidos_hoje,
    COUNT(*) FILTER (
      WHERE (t.finished_at AT TIME ZONE v_timezone) >= v_semana_inicio
        AND (t.finished_at AT TIME ZONE v_timezone) < v_proxima_semana_inicio
    )::bigint AS atendidos_semana
  FROM public.tickets t
  WHERE t.sos = true
    AND t.finished_at IS NOT NULL
    AND t.gse = ANY(v_gses);
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_obter_metricas_atendidos(uuid) TO authenticated;
COMMENT ON FUNCTION public.sos_obter_metricas_atendidos(uuid) IS
  'Retorna quantidade de tickets SOS atendidos hoje e na semana vigente (domingo-sabado) para a equipe informada.';
NOTIFY pgrst, 'reload schema';

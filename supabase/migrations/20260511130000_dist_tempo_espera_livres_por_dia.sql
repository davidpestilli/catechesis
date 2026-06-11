-- Distribuicao dos tickets livres nao mantidos por dia exato de espera.
-- Usa os mesmos filtros da visao por faixas da aba Tempo de Espera.

CREATE INDEX IF NOT EXISTS idx_tickets_dist_livres_nao_mantidos_dia
ON public.tickets (gse, origem, tempo_espera_origem)
WHERE status = 'aguardando'
  AND suspenso = false
  AND usuario_atual IS NULL
  AND mantido_por IS NULL;
DROP FUNCTION IF EXISTS public.dist_obter_distribuicao_dias_espera_livres(uuid, text);
CREATE OR REPLACE FUNCTION public.dist_obter_distribuicao_dias_espera_livres(
  p_equipe_id uuid,
  p_origem text DEFAULT NULL
)
RETURNS TABLE(
  dia_espera integer,
  label text,
  cor text,
  ordem integer,
  total bigint,
  percentual numeric,
  total_geral bigint,
  total_vip bigint,
  total_sos bigint,
  tempo_medio_horas numeric,
  ticket_mais_antigo_em timestamp,
  atualizado_em timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_gses text[];
BEGIN
  SELECT COALESCE(array_agg(ge.gse), ARRAY[]::text[])
  INTO v_gses
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  RETURN QUERY
  WITH base AS (
    SELECT
      t.id,
      COALESCE(t.vip, false) AS vip,
      COALESCE(t.sos, false) AS sos,
      t.tempo_espera_origem,
      GREATEST(
        0,
        FLOOR(EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 86400.0)::integer
      ) AS dia_espera,
      GREATEST(
        0::numeric,
        EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600.0
      ) AS espera_horas
    FROM public.tickets t
    WHERE t.gse = ANY(v_gses)
      AND t.status = 'aguardando'
      AND t.suspenso = false
      AND t.usuario_atual IS NULL
      AND t.mantido_por IS NULL
      AND t.tempo_espera_origem IS NOT NULL
      AND (p_origem IS NULL OR trim(p_origem) = '' OR t.origem = p_origem)
  ),
  agrupado AS (
    SELECT
      b.dia_espera,
      COUNT(*)::bigint AS total
    FROM base b
    GROUP BY b.dia_espera
  ),
  totais AS (
    SELECT
      COUNT(*)::bigint AS total_geral,
      COUNT(*) FILTER (WHERE vip)::bigint AS total_vip,
      COUNT(*) FILTER (WHERE sos)::bigint AS total_sos,
      COALESCE(ROUND(AVG(espera_horas)::numeric, 2), 0::numeric) AS tempo_medio_horas,
      MIN(tempo_espera_origem) AS ticket_mais_antigo_em
    FROM base
  ),
  paleta AS (
    SELECT ARRAY[
      '#22C55E', '#84CC16', '#EAB308', '#F59E0B', '#F97316', '#EF4444',
      '#EC4899', '#A855F7', '#6366F1', '#06B6D4', '#14B8A6', '#10B981'
    ]::text[] AS cores
  )
  SELECT
    agrupado.dia_espera,
    CASE
      WHEN agrupado.dia_espera = 0 THEN '0 dias'
      WHEN agrupado.dia_espera = 1 THEN '1 dia'
      ELSE agrupado.dia_espera::text || ' dias'
    END AS label,
    paleta.cores[(agrupado.dia_espera % array_length(paleta.cores, 1)) + 1] AS cor,
    agrupado.dia_espera AS ordem,
    agrupado.total,
    CASE
      WHEN totais.total_geral = 0 THEN 0::numeric
      ELSE ROUND((agrupado.total::numeric * 100) / totais.total_geral, 2)
    END AS percentual,
    totais.total_geral,
    totais.total_vip,
    totais.total_sos,
    totais.tempo_medio_horas,
    totais.ticket_mais_antigo_em,
    now() AS atualizado_em
  FROM agrupado
  CROSS JOIN totais
  CROSS JOIN paleta
  ORDER BY agrupado.dia_espera DESC;
END;
$function$;
COMMENT ON FUNCTION public.dist_obter_distribuicao_dias_espera_livres(uuid, text)
IS 'Distribui a fila Livres do Distribuidor por dia exato de espera, excluindo chamados mantidos por usuarios.';
GRANT EXECUTE ON FUNCTION public.dist_obter_distribuicao_dias_espera_livres(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dist_obter_distribuicao_dias_espera_livres(uuid, text) TO service_role;

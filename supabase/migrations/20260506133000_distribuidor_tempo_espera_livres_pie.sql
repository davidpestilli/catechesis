-- Distribuicao dinamica dos tickets livres nao mantidos por tempo de espera.
-- Fonte: public.tickets, mesma fila do Distribuidor de Chamados.

CREATE INDEX IF NOT EXISTS idx_tickets_dist_livres_nao_mantidos_tempo
ON public.tickets (gse, origem, tempo_espera_origem)
WHERE status = 'aguardando'
  AND suspenso = false
  AND usuario_atual IS NULL
  AND mantido_por IS NULL;
DROP FUNCTION IF EXISTS public.dist_obter_distribuicao_tempo_espera_livres(uuid, text);
CREATE OR REPLACE FUNCTION public.dist_obter_distribuicao_tempo_espera_livres(
  p_equipe_id uuid,
  p_origem text DEFAULT NULL
)
RETURNS TABLE(
  bucket_id text,
  label text,
  horas_min numeric,
  horas_max numeric,
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
  WITH buckets AS (
    SELECT *
    FROM (VALUES
      ('ate_24h'::text, 'ate 24h'::text, 0::numeric, 24::numeric, '#22C55E'::text, 1),
      ('24_48h'::text, '24h - 48h'::text, 24::numeric, 48::numeric, '#EAB308'::text, 2),
      ('48_72h'::text, '48h - 72h'::text, 48::numeric, 72::numeric, '#F97316'::text, 3),
      ('72_168h'::text, '3 - 7 dias'::text, 72::numeric, 168::numeric, '#EF4444'::text, 4),
      ('acima_168h'::text, 'mais de 7 dias'::text, 168::numeric, NULL::numeric, '#A855F7'::text, 5)
    ) AS b(bucket_id, label, horas_min, horas_max, cor, ordem)
  ),
  base AS (
    SELECT
      t.id,
      COALESCE(t.vip, false) AS vip,
      COALESCE(t.sos, false) AS sos,
      t.tempo_espera_origem,
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
  bucketed AS (
    SELECT
      CASE
        WHEN b.espera_horas < 24 THEN 'ate_24h'
        WHEN b.espera_horas < 48 THEN '24_48h'
        WHEN b.espera_horas < 72 THEN '48_72h'
        WHEN b.espera_horas < 168 THEN '72_168h'
        ELSE 'acima_168h'
      END AS bucket_id,
      COUNT(*)::bigint AS total
    FROM base b
    GROUP BY 1
  ),
  totais AS (
    SELECT
      COUNT(*)::bigint AS total_geral,
      COUNT(*) FILTER (WHERE vip)::bigint AS total_vip,
      COUNT(*) FILTER (WHERE sos)::bigint AS total_sos,
      COALESCE(ROUND(AVG(espera_horas)::numeric, 2), 0::numeric) AS tempo_medio_horas,
      MIN(tempo_espera_origem) AS ticket_mais_antigo_em
    FROM base
  )
  SELECT
    buckets.bucket_id,
    buckets.label,
    buckets.horas_min,
    buckets.horas_max,
    buckets.cor,
    buckets.ordem,
    COALESCE(bucketed.total, 0)::bigint AS total,
    CASE
      WHEN totais.total_geral = 0 THEN 0::numeric
      ELSE ROUND((COALESCE(bucketed.total, 0)::numeric * 100) / totais.total_geral, 2)
    END AS percentual,
    totais.total_geral,
    totais.total_vip,
    totais.total_sos,
    totais.tempo_medio_horas,
    totais.ticket_mais_antigo_em,
    now() AS atualizado_em
  FROM buckets
  CROSS JOIN totais
  LEFT JOIN bucketed ON bucketed.bucket_id = buckets.bucket_id
  ORDER BY buckets.ordem;
END;
$function$;
COMMENT ON FUNCTION public.dist_obter_distribuicao_tempo_espera_livres(uuid, text)
IS 'Distribui a fila Livres do Distribuidor por tempo de espera, excluindo chamados mantidos por usuarios.';
GRANT EXECUTE ON FUNCTION public.dist_obter_distribuicao_tempo_espera_livres(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dist_obter_distribuicao_tempo_espera_livres(uuid, text) TO service_role;

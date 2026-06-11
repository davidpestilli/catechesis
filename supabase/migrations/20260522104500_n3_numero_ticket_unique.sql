-- =====================================================
-- MIGRACAO: Impedir tickets SMAX duplicados em escalacoes_n3
-- - Normaliza numero_ticket com trim
-- - Consolida registros legados duplicados preservando relacionamentos
-- - Garante trim e unicidade no banco
-- =====================================================

UPDATE public.escalacoes_n3
SET numero_ticket = btrim(numero_ticket)
WHERE numero_ticket IS DISTINCT FROM btrim(numero_ticket);
DROP TABLE IF EXISTS tmp_escalacoes_n3_radar_counts;
CREATE TEMP TABLE tmp_escalacoes_n3_radar_counts (
  escalacao_n3_id uuid PRIMARY KEY,
  total bigint NOT NULL
);
DO $$
BEGIN
  IF to_regclass('public.radar_tickets') IS NOT NULL THEN
    EXECUTE $sql$
      INSERT INTO tmp_escalacoes_n3_radar_counts (escalacao_n3_id, total)
      SELECT escalacao_n3_id, COUNT(*)::bigint
      FROM public.radar_tickets
      WHERE escalacao_n3_id IS NOT NULL
      GROUP BY escalacao_n3_id
    $sql$;
  END IF;
END $$;
DROP TABLE IF EXISTS tmp_escalacoes_n3_duplicate_map;
CREATE TEMP TABLE tmp_escalacoes_n3_duplicate_map AS
WITH metrics AS (
  SELECT
    e.id,
    e.numero_ticket,
    e.status,
    e.data_envio,
    e.created_at,
    COALESCE(length(e.motivo_envio), 0) AS motivo_len,
    COALESCE(radar.total, 0) AS radar_count,
    COALESCE((SELECT COUNT(*) FROM public.escalacao_n3_retornos r WHERE r.escalacao_n3_id = e.id), 0) AS retorno_count,
    COALESCE((SELECT COUNT(*) FROM public.escalacoes_n3_vinculos v WHERE v.escalacao_a_id = e.id OR v.escalacao_b_id = e.id), 0) AS vinculo_count
  FROM public.escalacoes_n3 e
  LEFT JOIN tmp_escalacoes_n3_radar_counts radar
    ON radar.escalacao_n3_id = e.id
),
ranked AS (
  SELECT
    m.*,
    FIRST_VALUE(id) OVER (
      PARTITION BY numero_ticket
      ORDER BY
        CASE WHEN status = 'ativo' THEN 1 ELSE 0 END DESC,
        radar_count DESC,
        retorno_count DESC,
        vinculo_count DESC,
        motivo_len DESC,
        data_envio DESC NULLS LAST,
        created_at DESC NULLS LAST,
        id DESC
    ) AS canonical_id,
    COUNT(*) OVER (PARTITION BY numero_ticket) AS total_in_group
  FROM metrics m
)
SELECT id AS duplicate_id, canonical_id, numero_ticket AS ticket_num
FROM ranked
WHERE total_in_group > 1
  AND id <> canonical_id;
DROP TABLE IF EXISTS tmp_escalacoes_n3_affected_ids;
CREATE TEMP TABLE tmp_escalacoes_n3_affected_ids AS
SELECT DISTINCT canonical_id AS escalacao_n3_id FROM tmp_escalacoes_n3_duplicate_map
UNION
SELECT duplicate_id AS escalacao_n3_id FROM tmp_escalacoes_n3_duplicate_map;
DROP TABLE IF EXISTS tmp_escalacoes_n3_retornos_rebuilt;
CREATE TEMP TABLE tmp_escalacoes_n3_retornos_rebuilt AS
WITH all_retornos AS (
  SELECT
    COALESCE(map.canonical_id, r.escalacao_n3_id) AS escalacao_n3_id,
    r.data_retorno,
    r.resposta_n3,
    r.created_at,
    r.id AS source_id
  FROM public.escalacao_n3_retornos r
  LEFT JOIN tmp_escalacoes_n3_duplicate_map map
    ON map.duplicate_id = r.escalacao_n3_id
  WHERE r.escalacao_n3_id IN (
    SELECT escalacao_n3_id FROM tmp_escalacoes_n3_affected_ids
  )
),
renumbered AS (
  SELECT
    escalacao_n3_id,
    ROW_NUMBER() OVER (
      PARTITION BY escalacao_n3_id
      ORDER BY created_at ASC NULLS LAST, data_retorno ASC NULLS LAST, source_id ASC
    ) AS numero_retorno,
    data_retorno,
    resposta_n3,
    created_at
  FROM all_retornos
)
SELECT *
FROM renumbered;
DELETE FROM public.escalacao_n3_retornos r
USING tmp_escalacoes_n3_affected_ids affected
WHERE r.escalacao_n3_id = affected.escalacao_n3_id;
INSERT INTO public.escalacao_n3_retornos (
  escalacao_n3_id,
  numero_retorno,
  data_retorno,
  resposta_n3,
  created_at
)
SELECT
  escalacao_n3_id,
  numero_retorno,
  data_retorno,
  resposta_n3,
  created_at
FROM tmp_escalacoes_n3_retornos_rebuilt
ORDER BY escalacao_n3_id, numero_retorno;
DROP TABLE IF EXISTS tmp_escalacoes_n3_vinculos_rebuilt;
CREATE TEMP TABLE tmp_escalacoes_n3_vinculos_rebuilt AS
WITH affected_links AS (
  SELECT
    v.id,
    COALESCE(map_a.canonical_id, v.escalacao_a_id) AS mapped_a,
    COALESCE(map_b.canonical_id, v.escalacao_b_id) AS mapped_b,
    v.criado_por,
    v.created_at
  FROM public.escalacoes_n3_vinculos v
  LEFT JOIN tmp_escalacoes_n3_duplicate_map map_a
    ON map_a.duplicate_id = v.escalacao_a_id
  LEFT JOIN tmp_escalacoes_n3_duplicate_map map_b
    ON map_b.duplicate_id = v.escalacao_b_id
  WHERE v.escalacao_a_id IN (
      SELECT escalacao_n3_id FROM tmp_escalacoes_n3_affected_ids
    )
    OR v.escalacao_b_id IN (
      SELECT escalacao_n3_id FROM tmp_escalacoes_n3_affected_ids
    )
),
normalized AS (
  SELECT
    LEAST(mapped_a, mapped_b) AS escalacao_a_id,
    GREATEST(mapped_a, mapped_b) AS escalacao_b_id,
    criado_por,
    created_at,
    id
  FROM affected_links
  WHERE mapped_a <> mapped_b
),
deduplicated AS (
  SELECT DISTINCT ON (escalacao_a_id, escalacao_b_id)
    escalacao_a_id,
    escalacao_b_id,
    criado_por,
    created_at
  FROM normalized
  ORDER BY escalacao_a_id, escalacao_b_id, created_at ASC, id ASC
)
SELECT *
FROM deduplicated;
DELETE FROM public.escalacoes_n3_vinculos v
USING tmp_escalacoes_n3_affected_ids affected
WHERE v.escalacao_a_id = affected.escalacao_n3_id
   OR v.escalacao_b_id = affected.escalacao_n3_id;
INSERT INTO public.escalacoes_n3_vinculos (
  escalacao_a_id,
  escalacao_b_id,
  criado_por,
  created_at
)
SELECT
  escalacao_a_id,
  escalacao_b_id,
  criado_por,
  created_at
FROM tmp_escalacoes_n3_vinculos_rebuilt;
DO $$
BEGIN
  IF to_regclass('public.radar_tickets') IS NOT NULL THEN
    EXECUTE $sql$
      UPDATE public.radar_tickets rt
      SET escalacao_n3_id = map.canonical_id
      FROM tmp_escalacoes_n3_duplicate_map map
      WHERE rt.escalacao_n3_id = map.duplicate_id
    $sql$;
  END IF;
END $$;
DO $$
BEGIN
  IF to_regclass('public.smax_status_snapshot') IS NOT NULL THEN
    EXECUTE $sql$
      UPDATE public.smax_status_snapshot s
      SET escalacao_n3_id = map.canonical_id
      FROM tmp_escalacoes_n3_duplicate_map map
      WHERE s.escalacao_n3_id = map.duplicate_id
    $sql$;
  END IF;
END $$;
DELETE FROM public.escalacoes_n3 e
USING tmp_escalacoes_n3_duplicate_map map
WHERE e.id = map.duplicate_id;
ALTER TABLE public.escalacoes_n3
  DROP CONSTRAINT IF EXISTS chk_escalacoes_n3_numero_ticket_trimmed;
ALTER TABLE public.escalacoes_n3
  ADD CONSTRAINT chk_escalacoes_n3_numero_ticket_trimmed
  CHECK (numero_ticket = btrim(numero_ticket));
DROP INDEX IF EXISTS public.idx_escalacoes_n3_numero_ticket;
CREATE UNIQUE INDEX IF NOT EXISTS uq_escalacoes_n3_numero_ticket
  ON public.escalacoes_n3 (numero_ticket);

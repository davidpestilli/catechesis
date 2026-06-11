WITH assuntos_normalizados AS (
  SELECT
    e.id,
    string_agg(
      NULLIF(
        btrim(
          regexp_replace(
            regexp_replace(btrim(partes.tag), '[[:space:],]+', '-', 'g'),
            '-{2,}',
            '-',
            'g'
          ),
          '-'
        ),
        ''
      ),
      '; ' ORDER BY partes.ord
    ) AS assunto_normalizado
  FROM public.escalacoes_n3 e
  CROSS JOIN LATERAL regexp_split_to_table(coalesce(e.assunto, ''), ';') WITH ORDINALITY AS partes(tag, ord)
  WHERE e.assunto IS NOT NULL
  GROUP BY e.id
)
UPDATE public.escalacoes_n3 e
SET assunto = n.assunto_normalizado
FROM assuntos_normalizados n
WHERE e.id = n.id
  AND e.assunto IS DISTINCT FROM n.assunto_normalizado;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_escalacoes_n3_assunto_single_token'
  ) THEN
    ALTER TABLE public.escalacoes_n3
      ADD CONSTRAINT chk_escalacoes_n3_assunto_single_token
      CHECK (
        assunto IS NULL
        OR btrim(assunto) = ''
        OR btrim(assunto) ~ '^[^[:space:],;]+(\s*;\s*[^[:space:],;]+)*$'
      );
  END IF;
END $$;
COMMENT ON COLUMN public.escalacoes_n3.assunto IS 'Tags de assunto separadas por ;, com uma palavra/token por tag';

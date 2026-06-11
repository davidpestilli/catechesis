SET search_path TO public, extensions;
ALTER TABLE public.scripts_customizados
  ADD COLUMN IF NOT EXISTS instancia text;
ALTER TABLE public.scripts_customizados
  DROP CONSTRAINT IF EXISTS chk_scripts_instancia;
ALTER TABLE public.scripts_customizados
  ADD CONSTRAINT chk_scripts_instancia
  CHECK (
    instancia IS NULL
    OR instancia IN ('1G', '2G', 'ColRec', 'Externo (1G/2G)')
  );
COMMENT ON COLUMN public.scripts_customizados.instancia IS
  'Instancia do script: 1G, 2G, ColRec ou Externo (1G/2G). Campo obrigatorio no editor.';
WITH instancias_vigentes AS (
  SELECT
    id,
    CASE
      WHEN equipe_id IN (
        '90c2ed6a-bf56-4081-b4d6-63f37855ec12'::uuid, -- 2.2.1
        '2299bffb-48ce-45eb-9e46-bcbc4d15c964'::uuid  -- 2.2.2
      ) THEN '1G'
      WHEN equipe_id = '22222222-2222-2222-2222-222222222222'::uuid THEN '2G' -- 2.3.1
      WHEN equipe_id = '11111111-1111-1111-1111-111111111111'::uuid THEN 'Externo (1G/2G)' -- 2.3.2
      ELSE NULL
    END AS instancia_calculada
  FROM public.scripts_customizados
  WHERE deletado IS DISTINCT FROM true
    AND desativado_em IS NULL
    AND equipe_id IN (
      '90c2ed6a-bf56-4081-b4d6-63f37855ec12'::uuid,
      '2299bffb-48ce-45eb-9e46-bcbc4d15c964'::uuid,
      '22222222-2222-2222-2222-222222222222'::uuid,
      '11111111-1111-1111-1111-111111111111'::uuid
    )
)
UPDATE public.scripts_customizados s
SET instancia = i.instancia_calculada
FROM instancias_vigentes i
WHERE s.id = i.id
  AND i.instancia_calculada IS NOT NULL
  AND s.instancia IS DISTINCT FROM i.instancia_calculada;
DO $$
DECLARE
  v_sem_instancia integer;
BEGIN
  SELECT count(*)
    INTO v_sem_instancia
  FROM public.scripts_customizados
  WHERE deletado IS DISTINCT FROM true
    AND desativado_em IS NULL
    AND equipe_id IN (
      '90c2ed6a-bf56-4081-b4d6-63f37855ec12'::uuid,
      '2299bffb-48ce-45eb-9e46-bcbc4d15c964'::uuid,
      '22222222-2222-2222-2222-222222222222'::uuid,
      '11111111-1111-1111-1111-111111111111'::uuid
    )
    AND instancia IS NULL;

  IF v_sem_instancia > 0 THEN
    RAISE EXCEPTION 'Backfill de instancia incompleto: % scripts vigentes sem instancia.', v_sem_instancia;
  END IF;
END $$;

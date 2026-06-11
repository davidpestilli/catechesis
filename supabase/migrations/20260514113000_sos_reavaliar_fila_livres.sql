-- SOS: reavaliar somente a fila Livres da equipe e reduzir atualizacoes desnecessarias.

CREATE INDEX IF NOT EXISTS idx_tickets_sos_reavaliar_livres
ON public.tickets (gse, id)
WHERE status = 'aguardando'
  AND usuario_atual IS NULL
  AND COALESCE(suspenso, false) = false;
CREATE OR REPLACE FUNCTION public.sos_reavaliar_tickets_fila(p_equipe_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
SET statement_timeout = '45s'
AS $$
DECLARE
  v_gses text[];
  v_count integer := 0;
BEGIN
  IF NOT public.tem_permissao('distribuidor.sos_keywords') THEN
    RAISE EXCEPTION 'Apenas usuarios autorizados podem reavaliar palavras SOS';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatorio para reavaliacao SOS';
  END IF;

  SELECT array_agg(gse) INTO v_gses
  FROM public.gse_equipes
  WHERE equipe_id = p_equipe_id;

  IF v_gses IS NULL OR array_length(v_gses, 1) IS NULL THEN
    RETURN 0;
  END IF;

  WITH calculado AS MATERIALIZED (
    SELECT
      t.id,
      t.sos,
      t.sos_palavras,
      t.sos_override,
      matched.novas_palavras,
      COALESCE(array_length(matched.novas_palavras, 1), 0) > 0 AS novo_sos
    FROM public.tickets t
    CROSS JOIN LATERAL (
      SELECT public.sos_match_palavras(t.descricao, p_equipe_id) AS novas_palavras
    ) matched
    WHERE t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND COALESCE(t.suspenso, false) = false
      AND t.gse = ANY(v_gses)
  ), atualizados AS (
    UPDATE public.tickets t
       SET sos_palavras = c.novas_palavras,
           sos = CASE
                   WHEN c.sos_override IS TRUE THEN t.sos
                   ELSE c.novo_sos
                 END
      FROM calculado c
     WHERE t.id = c.id
       AND (
         t.sos_palavras IS DISTINCT FROM c.novas_palavras
         OR (
           c.sos_override IS NOT TRUE
           AND t.sos IS DISTINCT FROM c.novo_sos
         )
       )
    RETURNING t.id
  )
  SELECT COUNT(*)::integer INTO v_count
  FROM calculado;

  RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_reavaliar_tickets_fila(uuid) TO authenticated;
COMMENT ON FUNCTION public.sos_reavaliar_tickets_fila(uuid) IS
  'Reavalia classificacao SOS apenas da fila Livres da equipe especificada (status=aguardando, sem usuario_atual, suspenso=false).';

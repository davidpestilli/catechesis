-- Sistema Solar: heatmap de similaridade par a par dos satelites de um planeta.
-- A RPC calcula similaridade cosseno diretamente sobre ticket_embeddings.

CREATE OR REPLACE FUNCTION public.cluster_tickets_heatmap(
  p_cluster_id uuid,
  p_max_tickets integer DEFAULT 36
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  WITH parametros AS (
    SELECT GREATEST(2, LEAST(COALESCE(p_max_tickets, 36), 60))::integer AS limite
  ),
  visiveis AS (
    SELECT
      m.ticket_id,
      m.similaridade AS similaridade_centro,
      t.numero_chamado,
      t.gse,
      t.descricao,
      row_number() OVER (ORDER BY m.similaridade DESC, t.numero_chamado ASC) AS ordem
    FROM public.ticket_cluster_membros m
    JOIN public.tickets t ON t.id = m.ticket_id
    WHERE m.cluster_id = p_cluster_id
      AND t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND COALESCE(t.suspenso, false) = false
  ),
  selecionados AS (
    SELECT v.*
    FROM visiveis v, parametros p
    WHERE v.ordem <= p.limite
  ),
  com_embeddings AS (
    SELECT
      s.*,
      te.embedding
    FROM selecionados s
    LEFT JOIN public.ticket_embeddings te ON te.ticket_id = s.ticket_id
  )
  SELECT jsonb_build_object(
    'cluster_id', p_cluster_id,
    'total_tickets', (SELECT count(*)::integer FROM visiveis),
    'limite', (SELECT limite FROM parametros),
    'tickets', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'ticket_id', e.ticket_id,
        'numero_chamado', e.numero_chamado,
        'gse', e.gse,
        'descricao', e.descricao,
        'similaridade_centro', e.similaridade_centro,
        'ordem', e.ordem,
        'tem_embedding', e.embedding IS NOT NULL
      ) ORDER BY e.ordem)
      FROM com_embeddings e
    ), '[]'::jsonb),
    'cells', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'ticket_a_id', a.ticket_id,
        'ticket_b_id', b.ticket_id,
        'similaridade', CASE
          WHEN a.ticket_id = b.ticket_id THEN 1::real
          WHEN a.embedding IS NULL OR b.embedding IS NULL THEN NULL
          ELSE GREATEST(-1::double precision, LEAST(1::double precision, 1 - (a.embedding <=> b.embedding)))::real
        END
      ) ORDER BY a.ordem, b.ordem)
      FROM com_embeddings a
      CROSS JOIN com_embeddings b
    ), '[]'::jsonb)
  );
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_heatmap(uuid, integer) TO authenticated;
COMMENT ON FUNCTION public.cluster_tickets_heatmap(uuid, integer) IS
  'Retorna matriz de similaridade cosseno par a par dos tickets visiveis de um planeta do Sistema Solar.';

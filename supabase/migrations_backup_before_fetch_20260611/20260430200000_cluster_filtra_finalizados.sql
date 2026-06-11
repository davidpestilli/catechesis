-- =====================================================
-- PATCH: Sistema Solar — filtrar tickets que saíram da fila
-- (status != 'aguardando' OU usuario_atual NOT NULL)
-- nas RPCs cluster_tickets_obter e cluster_tickets_listar.
-- =====================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_obter(p_cluster_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'cluster', to_jsonb(c.*),
    'satelites', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'ticket_id', m.ticket_id,
        'similaridade', m.similaridade,
        'numero_chamado', t.numero_chamado,
        'gse', t.gse,
        'descricao', t.descricao,
        'email', t.email,
        'vip', t.vip,
        'sos', t.sos,
        'mantido_por', t.mantido_por,
        'mantido_por_nome', u.nome,
        'mantido_por_email', u.email,
        'tempo_espera_origem', t.tempo_espera_origem,
        'categoria_id',     ta.categoria_equipe_id,
        'categoria_nome',   ce.nome,
        'subcategoria_id',  ta.subcategoria_gse_id,
        'subcategoria_nome', sg.nome
      ) ORDER BY m.similaridade DESC)
      FROM public.ticket_cluster_membros m
      JOIN public.tickets t ON t.id = m.ticket_id
      LEFT JOIN public.users u ON u.id = t.mantido_por
      LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
      LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
      LEFT JOIN public.subcategorias_gse sg ON sg.id = ta.subcategoria_gse_id
      WHERE m.cluster_id = c.id
        AND t.status = 'aguardando'
        AND t.usuario_atual IS NULL
    ), '[]'::jsonb)
  )
  FROM public.ticket_clusters c
  WHERE c.id = p_cluster_id;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_obter(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.cluster_tickets_listar(p_equipe_id uuid)
RETURNS TABLE(
  id uuid,
  problema_comum text,
  resumo_curto text,
  confianca smallint,
  total_satelites integer,
  total_livres_agora integer,
  categorias jsonb,
  subcategorias jsonb,
  gses jsonb,
  centroid_ticket_id uuid,
  resumo_status text,
  threshold real,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    c.problema_comum,
    c.resumo_curto,
    c.confianca,
    -- total_satelites = apenas tickets ainda na fila
    (SELECT count(*)::int
       FROM public.ticket_cluster_membros m
       JOIN public.tickets t ON t.id = m.ticket_id
       WHERE m.cluster_id = c.id
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL),
    -- total_livres_agora = na fila e sem reserva
    (SELECT count(*)::int
       FROM public.ticket_cluster_membros m
       JOIN public.tickets t ON t.id = m.ticket_id
       WHERE m.cluster_id = c.id
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND t.mantido_por IS NULL),
    c.categorias,
    c.subcategorias,
    c.gses,
    c.centroid_ticket_id,
    c.resumo_status,
    c.threshold,
    c.updated_at
  FROM public.ticket_clusters c
  WHERE c.equipe_id = p_equipe_id
  ORDER BY c.updated_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_listar(uuid) TO authenticated;

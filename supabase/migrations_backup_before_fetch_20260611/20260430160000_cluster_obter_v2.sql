-- =====================================================
-- PATCH: Sistema Solar — cluster_tickets_obter retorna categoria/subcategoria por satélite
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
    ), '[]'::jsonb)
  )
  FROM public.ticket_clusters c
  WHERE c.id = p_cluster_id;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_obter(uuid) TO authenticated;

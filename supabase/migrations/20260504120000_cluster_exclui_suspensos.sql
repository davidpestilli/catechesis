-- =====================================================
-- Sistema Solar: excluir tickets suspensos das visualizacoes
--
-- Tickets anexados a um chamado Global ficam com suspenso = true.
-- Eles devem sair do Sistema Solar como saem da fila principal do
-- Distribuidor, permanecendo apenas na lista de Suspensos.
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
        AND COALESCE(t.suspenso, false) = false
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
    (SELECT count(*)::int
       FROM public.ticket_cluster_membros m
       JOIN public.tickets t ON t.id = m.ticket_id
       WHERE m.cluster_id = c.id
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false),
    (SELECT count(*)::int
       FROM public.ticket_cluster_membros m
       JOIN public.tickets t ON t.id = m.ticket_id
       WHERE m.cluster_id = c.id
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
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
SET search_path TO public, extensions;
CREATE OR REPLACE FUNCTION public.cluster_tickets_buscar_por_prompt(
  p_equipe_id uuid,
  p_query_embedding vector(2000),
  p_threshold double precision DEFAULT 0.55,
  p_max integer DEFAULT 80
)
RETURNS TABLE (
  ticket_id uuid,
  numero_chamado text,
  gse text,
  status text,
  descricao text,
  email text,
  vip boolean,
  sos boolean,
  mantido_por uuid,
  mantido_por_nome text,
  mantido_por_email text,
  tempo_espera_origem timestamp with time zone,
  similaridade double precision,
  categoria_id uuid,
  categoria_nome text,
  subcategoria_id uuid,
  subcategoria_nome text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
  SELECT
    t.id AS ticket_id,
    t.numero_chamado,
    t.gse,
    t.status,
    t.descricao,
    t.email,
    t.vip,
    t.sos,
    t.mantido_por,
    u.nome  AS mantido_por_nome,
    u.email AS mantido_por_email,
    t.tempo_espera_origem,
    1.0 - (te.embedding <=> p_query_embedding) AS similaridade,
    ta.categoria_equipe_id  AS categoria_id,
    ce.nome                 AS categoria_nome,
    ta.subcategoria_gse_id  AS subcategoria_id,
    sg.nome                 AS subcategoria_nome
  FROM public.ticket_embeddings te
  JOIN public.tickets t           ON t.id = te.ticket_id
  LEFT JOIN public.users u        ON u.id = t.mantido_por
  LEFT JOIN public.ticket_analises ta   ON ta.ticket_id = t.id
  LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
  LEFT JOIN public.subcategorias_gse sg ON sg.id = ta.subcategoria_gse_id
  WHERE te.equipe_id = p_equipe_id
    AND t.status = 'aguardando'
    AND t.usuario_atual IS NULL
    AND COALESCE(t.suspenso, false) = false
    AND (1.0 - (te.embedding <=> p_query_embedding)) >= p_threshold
  ORDER BY te.embedding <=> p_query_embedding ASC
  LIMIT p_max;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_buscar_por_prompt(uuid, vector, double precision, integer) TO authenticated;
RESET search_path;

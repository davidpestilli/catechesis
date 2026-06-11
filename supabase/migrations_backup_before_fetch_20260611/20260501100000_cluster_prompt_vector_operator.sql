-- =====================================================
-- PATCH: Sistema Solar — search_path robusto para pgvector
--
-- Em produção o tipo/operador vector está em public; no Docker local pode
-- estar em extensions. Abrir o search_path na criação e execução evita
-- divergência sem amarrar a função a um schema específico da extensão.
-- =====================================================

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
    AND (1.0 - (te.embedding <=> p_query_embedding)) >= p_threshold
  ORDER BY te.embedding <=> p_query_embedding ASC
  LIMIT p_max;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_buscar_por_prompt(uuid, vector, double precision, integer) TO authenticated;
RESET search_path;

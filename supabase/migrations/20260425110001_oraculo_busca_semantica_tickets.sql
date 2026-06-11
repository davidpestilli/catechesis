-- Pesquisa semântica de tickets (equipes 2.3.1 / 2.3.2) na aba Buscar do Oráculo.
-- Usa a tabela `ticket_embeddings` (descricao embedding) + JOIN em `tickets`.
-- Restrição: somente status 'aguardando'/'finalizado' (alinhado com is_ticket_embedding_target).

-- ---------------------------------------------------------------------------
-- 1) Lista de GSEs disponíveis para pesquisa semântica (com contagem)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.listar_grupos_embedding_oraculo()
RETURNS TABLE(grupo_designado text, total_chamados bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $$
  SELECT te.gse AS grupo_designado, COUNT(*)::bigint AS total_chamados
  FROM public.ticket_embeddings te
  GROUP BY te.gse
  ORDER BY COUNT(*) DESC, te.gse ASC;
$$;
GRANT EXECUTE ON FUNCTION public.listar_grupos_embedding_oraculo() TO anon, authenticated, service_role;
-- ---------------------------------------------------------------------------
-- 2) Busca semântica
-- ---------------------------------------------------------------------------
-- Retorno alinhado com SearchResultado (frontend):
--   numero_chamado text, data_abertura date, grupo_designado text,
--   descricao text, solucao text, email text,
--   relevance_score double precision, match_field text
--
-- Defensivo: limita às equipes 2.3.1/2.3.2 mesmo que ticket_embeddings tenha
-- algum vazamento futuro. Status restrito conforme pipeline.
CREATE OR REPLACE FUNCTION public.buscar_tickets_semantica_oraculo(
  p_query_embedding vector,
  p_grupos_designados text[] DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_min_similarity double precision DEFAULT 0.20
)
RETURNS TABLE(
  numero_chamado text,
  data_abertura date,
  grupo_designado text,
  descricao text,
  solucao text,
  email text,
  relevance_score double precision,
  match_field text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public', 'extensions'
SET statement_timeout TO '30s'
AS $function$
DECLARE
  v_use_groups boolean := (p_grupos_designados IS NOT NULL AND array_length(p_grupos_designados, 1) > 0);
  v_limit integer := GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
  v_threshold double precision := COALESCE(p_min_similarity, 0.20);
BEGIN
  IF p_query_embedding IS NULL THEN
    RAISE EXCEPTION 'p_query_embedding não pode ser NULL';
  END IF;

  RETURN QUERY
  SELECT
    t.numero_chamado::text,
    t.created_at::date            AS data_abertura,
    t.gse::text                   AS grupo_designado,
    COALESCE(t.descricao, '')::text   AS descricao,
    COALESCE(t.resposta_ia, '')::text AS solucao,
    t.email::text,
    (1 - (te.embedding <=> p_query_embedding))::double precision AS relevance_score,
    'descricao'::text             AS match_field
  FROM public.ticket_embeddings te
  JOIN public.tickets t   ON t.id = te.ticket_id
  JOIN public.equipes e   ON e.id = te.equipe_id
  WHERE e.sgs_codigo IN ('2.3.1', '2.3.2')
    AND t.status IN ('aguardando', 'finalizado')
    AND (NOT v_use_groups OR te.gse = ANY(p_grupos_designados))
    AND (1 - (te.embedding <=> p_query_embedding)) >= v_threshold
  ORDER BY te.embedding <=> p_query_embedding ASC
  LIMIT v_limit;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.buscar_tickets_semantica_oraculo(vector, text[], integer, double precision)
  TO anon, authenticated, service_role;

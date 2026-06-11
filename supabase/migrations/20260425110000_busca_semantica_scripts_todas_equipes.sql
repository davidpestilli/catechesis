-- =====================================================================
-- Migration: Expandir escopo de embeddings de scripts para todas as
--            equipes (apenas filtra scripts deletados).
--
-- - `is_script_embedding_target` passa a aceitar qualquer equipe e
--   ignora `habilitado_smith` (apenas exige `deletado = false`).
-- - `buscar_scripts_por_embedding_texto` deixa de restringir por
--   equipe; a busca textual do ScriptsModal cobre todos os scripts
--   ativos do sistema.
-- - O RPC `buscar_scripts_similares_por_embedding_ticket` (analise
--   Oraculo) NAO e' alterado: continua aplicando a regra
--   231 ve' 231; 232 ve' 232+externo.
-- =====================================================================

SET search_path = public, extensions;
-- ---------------------------------------------------------------------
-- 1) is_script_embedding_target: agora cobre todas as equipes
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_script_embedding_target(
  p_equipe_id uuid,
  p_habilitado_smith boolean,
  p_deletado boolean
)
RETURNS boolean
LANGUAGE sql
STABLE
AS $$
  SELECT
    p_equipe_id IS NOT NULL
    AND COALESCE(p_deletado, false) = false;
$$;
COMMENT ON FUNCTION public.is_script_embedding_target IS
  'Escopo de embeddings: todos os scripts ativos (deletado = false), independentemente de equipe ou habilitado_smith.';
-- ---------------------------------------------------------------------
-- 2) buscar_scripts_por_embedding_texto: sem restricao de equipe
-- ---------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.buscar_scripts_por_embedding_texto(
  p_query_embedding vector(2000),
  p_equipe_id_referencia uuid DEFAULT NULL,
  p_limit integer DEFAULT 50,
  p_min_similarity double precision DEFAULT 0.20
)
RETURNS TABLE(
  script_id uuid,
  similarity double precision
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
AS $$
BEGIN
  IF p_query_embedding IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    se.script_id,
    1 - (se.embedding <=> p_query_embedding) AS similarity
  FROM public.script_embeddings se
  JOIN public.scripts_customizados s ON s.id = se.script_id
  WHERE COALESCE(s.deletado, false) = false
    AND (1 - (se.embedding <=> p_query_embedding)) >= p_min_similarity
  ORDER BY se.embedding <=> p_query_embedding
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 200));
END;
$$;
GRANT EXECUTE ON FUNCTION public.buscar_scripts_por_embedding_texto(vector, uuid, integer, double precision) TO authenticated;
COMMENT ON FUNCTION public.buscar_scripts_por_embedding_texto IS
  'Busca semantica de scripts (campo Buscar Titulos do ScriptsModal). Cobre todos os scripts ativos do sistema.';
-- ---------------------------------------------------------------------
-- 3) Re-enfileirar scripts recem-elegiveis (de outras equipes) para
--    que o worker/card Dev gere os embeddings ausentes.
-- ---------------------------------------------------------------------
INSERT INTO public.script_embeddings_queue (script_id, motivo, tentativas, next_retry_at, created_at, updated_at)
SELECT s.id, 'expansao_escopo_todas_equipes', 0, now(), now(), now()
FROM public.scripts_customizados s
LEFT JOIN public.script_embeddings se ON se.script_id = s.id
LEFT JOIN public.script_embeddings_queue q ON q.script_id = s.id
WHERE se.script_id IS NULL
  AND q.script_id IS NULL
  AND public.is_script_embedding_target(s.equipe_id, s.habilitado_smith, s.deletado);

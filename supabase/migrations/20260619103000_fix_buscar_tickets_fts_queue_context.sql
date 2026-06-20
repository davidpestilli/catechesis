DROP FUNCTION IF EXISTS public.buscar_tickets_fts(text, uuid, text, integer);
CREATE OR REPLACE FUNCTION public.buscar_tickets_fts(
  p_query text,
  p_equipe_id uuid,
  p_origem text DEFAULT NULL::text,
  p_suspenso boolean DEFAULT false,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_tsquery tsquery;
  v_clean_query text;
  v_gse_list text[];
  v_result jsonb;
BEGIN
  IF p_query IS NULL OR trim(p_query) = '' THEN
    RETURN '[]'::jsonb;
  END IF;

  IF p_equipe_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  v_clean_query := trim(p_query);

  SELECT array_agg(ge.gse)
  INTO v_gse_list
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  IF v_gse_list IS NULL OR array_length(v_gse_list, 1) IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  BEGIN
    v_tsquery := websearch_to_tsquery('portuguese', public.f_unaccent(v_clean_query));
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      v_tsquery := plainto_tsquery('portuguese', public.f_unaccent(v_clean_query));
    EXCEPTION WHEN OTHERS THEN
      RETURN '[]'::jsonb;
    END;
  END;

  SELECT COALESCE(jsonb_agg(row_to_json(subq)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      t.id,
      t.numero_chamado,
      t.gse,
      t.tempo_espera_origem,
      t.descricao,
      t.email,
      t.vip,
      t.sos,
      t.sos_palavras,
      t.sos_override,
      t.is_reopened,
      t.suspenso,
      t.fila_finalizacao_contexto,
      t.causa_suspensao,
      t.comentario,
      t.resposta_ia,
      t.origem,
      t.status,
      t.created_at,
      t.updated_at,
      t.assigned_at,
      t.started_at,
      t.finished_at,
      t.version,
      t.mantido_por,
      t.mantido_at,
      t.usuario_atual,
      ts_rank_cd(t.search_vector_descricao, v_tsquery) AS fts_rank,
      'fts' AS match_type
    FROM public.tickets t
    WHERE t.gse = ANY(v_gse_list)
      AND (
        (
          p_suspenso = true
          AND t.status = 'aguardando'
          AND t.suspenso = true
          AND t.usuario_atual IS NULL
        )
        OR (
          p_suspenso = false
          AND t.suspenso = false
          AND (
            (t.status = 'aguardando' AND t.usuario_atual IS NULL)
            OR (t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL)
          )
        )
      )
      AND (p_origem IS NULL OR t.origem::text = p_origem)
      AND t.search_vector_descricao @@ v_tsquery
    ORDER BY
      CASE WHEN public.is_gse_homologacao(t.gse) THEN 0 ELSE 1 END,
      t.vip DESC,
      ts_rank_cd(t.search_vector_descricao, v_tsquery) DESC
    LIMIT p_limit
  ) subq;

  IF jsonb_array_length(v_result) > 0 THEN
    RETURN v_result;
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(subq)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      t.id,
      t.numero_chamado,
      t.gse,
      t.tempo_espera_origem,
      t.descricao,
      t.email,
      t.vip,
      t.sos,
      t.sos_palavras,
      t.sos_override,
      t.is_reopened,
      t.suspenso,
      t.fila_finalizacao_contexto,
      t.causa_suspensao,
      t.comentario,
      t.resposta_ia,
      t.origem,
      t.status,
      t.created_at,
      t.updated_at,
      t.assigned_at,
      t.started_at,
      t.finished_at,
      t.version,
      t.mantido_por,
      t.mantido_at,
      t.usuario_atual,
      similarity(public.f_unaccent(coalesce(t.descricao, '')), public.f_unaccent(v_clean_query)) AS fts_rank,
      'ilike' AS match_type
    FROM public.tickets t
    WHERE t.gse = ANY(v_gse_list)
      AND (
        (
          p_suspenso = true
          AND t.status = 'aguardando'
          AND t.suspenso = true
          AND t.usuario_atual IS NULL
        )
        OR (
          p_suspenso = false
          AND t.suspenso = false
          AND (
            (t.status = 'aguardando' AND t.usuario_atual IS NULL)
            OR (t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL)
          )
        )
      )
      AND (p_origem IS NULL OR t.origem::text = p_origem)
      AND public.f_unaccent(coalesce(t.descricao, '')) ILIKE '%' || public.f_unaccent(v_clean_query) || '%'
    ORDER BY
      CASE WHEN public.is_gse_homologacao(t.gse) THEN 0 ELSE 1 END,
      t.vip DESC,
      similarity(public.f_unaccent(coalesce(t.descricao, '')), public.f_unaccent(v_clean_query)) DESC
    LIMIT p_limit
  ) subq;

  RETURN v_result;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.buscar_tickets_fts(text, uuid, text, boolean, integer) TO authenticated;
COMMENT ON FUNCTION public.buscar_tickets_fts(text, uuid, text, boolean, integer) IS
'Busca Full-Text Search na descrição dos tickets da fila atual do Distribuidor.
Quando p_suspenso=false, busca a fila Livres visível ao usuário.
Quando p_suspenso=true, busca a fila Suspensos.
Usa FTS com fallback ILIKE para termos não encontrados pelo stemmer.';

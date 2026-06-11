-- Adiciona suporte a múltiplos grupos designados na busca do Oráculo (aba Buscar)
--
-- Mudança: novo parâmetro opcional `p_grupos_designados text[]`.
-- Quando informado e não vazio, filtra por `c.grupo_designado = ANY(p_grupos_designados)`,
-- substituindo o filtro single-value `p_grupo_designado`.
-- Mantém retrocompatibilidade com `p_grupo_designado text`.

CREATE OR REPLACE FUNCTION public.buscar_chamados(
  p_query text,
  p_buscar_em text DEFAULT 'ambas'::text,
  p_filtro_solucao text DEFAULT 'com-solucao'::text,
  p_grupo_designado text DEFAULT NULL::text,
  p_data_inicio date DEFAULT NULL::date,
  p_data_fim date DEFAULT NULL::date,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_grupos_designados text[] DEFAULT NULL
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
SET statement_timeout TO '30s'
AS $function$
DECLARE
  v_parsed RECORD;
  v_fts_count INT;
  v_similarity_threshold FLOAT := 0.3;
  v_use_array BOOLEAN := (p_grupos_designados IS NOT NULL AND array_length(p_grupos_designados, 1) > 0);
BEGIN
  SELECT * INTO v_parsed FROM parse_query_avancada(p_query);

  IF v_parsed.tsquery_result IS NOT NULL OR v_parsed.has_phrase THEN
    SELECT COUNT(*) INTO v_fts_count
    FROM oraculo_chamados c
    WHERE
      (v_parsed.tsquery_result IS NULL OR
        CASE
          WHEN p_buscar_em = 'descricoes' THEN c.search_vector_descricao @@ v_parsed.tsquery_result
          WHEN p_buscar_em = 'solucoes' THEN c.search_vector_solucao @@ v_parsed.tsquery_result
          ELSE (c.search_vector_descricao @@ v_parsed.tsquery_result OR c.search_vector_solucao @@ v_parsed.tsquery_result)
        END
      )
      AND (NOT v_parsed.has_phrase OR
        CASE
          WHEN p_buscar_em = 'descricoes' THEN c.descricao ILIKE '%' || v_parsed.phrase_text || '%'
          WHEN p_buscar_em = 'solucoes' THEN c.solucao ILIKE '%' || v_parsed.phrase_text || '%'
          ELSE (c.descricao ILIKE '%' || v_parsed.phrase_text || '%' OR c.solucao ILIKE '%' || v_parsed.phrase_text || '%')
        END
      )
      AND (array_length(v_parsed.exclude_terms, 1) IS NULL OR NOT (
        CASE
          WHEN p_buscar_em = 'descricoes' THEN c.descricao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
          WHEN p_buscar_em = 'solucoes' THEN c.solucao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
          ELSE (c.descricao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
                OR c.solucao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t))
        END
      ))
      AND (
        (v_use_array AND c.grupo_designado = ANY(p_grupos_designados))
        OR (NOT v_use_array AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado))
      )
      AND (p_data_inicio IS NULL OR c.data_abertura::date >= p_data_inicio)
      AND (p_data_fim IS NULL OR c.data_abertura::date <= p_data_fim)
      AND (
        p_filtro_solucao = 'tanto-faz'
        OR (p_filtro_solucao = 'com-solucao' AND c.solucao IS NOT NULL AND TRIM(c.solucao) <> '' AND TRIM(c.solucao) <> '-')
        OR (p_filtro_solucao = 'sem-solucao' AND (c.solucao IS NULL OR TRIM(c.solucao) = '' OR TRIM(c.solucao) = '-'))
      );

    IF v_fts_count > 0 THEN
      RETURN QUERY
      SELECT
        c.numero_chamado,
        c.data_abertura::date,
        c.grupo_designado,
        c.descricao,
        c.solucao,
        c.email,
        CASE
          WHEN p_buscar_em = 'descricoes' THEN ts_rank_cd(c.search_vector_descricao, v_parsed.tsquery_result)
          WHEN p_buscar_em = 'solucoes' THEN ts_rank_cd(c.search_vector_solucao, v_parsed.tsquery_result)
          ELSE GREATEST(
            ts_rank_cd(c.search_vector_descricao, v_parsed.tsquery_result) * 1.2,
            ts_rank_cd(c.search_vector_solucao, v_parsed.tsquery_result)
          )
        END::FLOAT AS score,
        CASE
          WHEN p_buscar_em = 'descricoes' THEN 'descricao'::TEXT
          WHEN p_buscar_em = 'solucoes' THEN 'solucao'::TEXT
          WHEN v_parsed.tsquery_result IS NOT NULL
               AND c.search_vector_descricao @@ v_parsed.tsquery_result
               AND c.search_vector_solucao @@ v_parsed.tsquery_result THEN 'ambas'::TEXT
          WHEN v_parsed.tsquery_result IS NOT NULL
               AND c.search_vector_descricao @@ v_parsed.tsquery_result THEN 'descricao'::TEXT
          ELSE 'solucao'::TEXT
        END AS campo_match
      FROM oraculo_chamados c
      WHERE
        (v_parsed.tsquery_result IS NULL OR
          CASE
            WHEN p_buscar_em = 'descricoes' THEN c.search_vector_descricao @@ v_parsed.tsquery_result
            WHEN p_buscar_em = 'solucoes' THEN c.search_vector_solucao @@ v_parsed.tsquery_result
            ELSE (c.search_vector_descricao @@ v_parsed.tsquery_result OR c.search_vector_solucao @@ v_parsed.tsquery_result)
          END
        )
        AND (NOT v_parsed.has_phrase OR
          CASE
            WHEN p_buscar_em = 'descricoes' THEN c.descricao ILIKE '%' || v_parsed.phrase_text || '%'
            WHEN p_buscar_em = 'solucoes' THEN c.solucao ILIKE '%' || v_parsed.phrase_text || '%'
            ELSE (c.descricao ILIKE '%' || v_parsed.phrase_text || '%' OR c.solucao ILIKE '%' || v_parsed.phrase_text || '%')
          END
        )
        AND (array_length(v_parsed.exclude_terms, 1) IS NULL OR NOT (
          CASE
            WHEN p_buscar_em = 'descricoes' THEN c.descricao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
            WHEN p_buscar_em = 'solucoes' THEN c.solucao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
            ELSE (c.descricao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
                  OR c.solucao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t))
          END
        ))
        AND (
          (v_use_array AND c.grupo_designado = ANY(p_grupos_designados))
          OR (NOT v_use_array AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado))
        )
        AND (p_data_inicio IS NULL OR c.data_abertura::date >= p_data_inicio)
        AND (p_data_fim IS NULL OR c.data_abertura::date <= p_data_fim)
        AND (
          p_filtro_solucao = 'tanto-faz'
          OR (p_filtro_solucao = 'com-solucao' AND c.solucao IS NOT NULL AND TRIM(c.solucao) <> '' AND TRIM(c.solucao) <> '-')
          OR (p_filtro_solucao = 'sem-solucao' AND (c.solucao IS NULL OR TRIM(c.solucao) = '' OR TRIM(c.solucao) = '-'))
        )
      ORDER BY score DESC, c.data_abertura DESC
      LIMIT p_limit
      OFFSET p_offset;

      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    c.numero_chamado,
    c.data_abertura::date,
    c.grupo_designado,
    c.descricao,
    c.solucao,
    c.email,
    CASE
      WHEN p_buscar_em = 'descricoes' THEN similarity(c.descricao, p_query)
      WHEN p_buscar_em = 'solucoes' THEN similarity(c.solucao, p_query)
      ELSE GREATEST(similarity(c.descricao, p_query), similarity(c.solucao, p_query))
    END::FLOAT AS score,
    CASE
      WHEN p_buscar_em = 'descricoes' THEN 'descricao'::TEXT
      WHEN p_buscar_em = 'solucoes' THEN 'solucao'::TEXT
      WHEN similarity(c.descricao, p_query) >= similarity(c.solucao, p_query) THEN 'descricao'::TEXT
      ELSE 'solucao'::TEXT
    END AS campo_match
  FROM oraculo_chamados c
  WHERE
    CASE
      WHEN p_buscar_em = 'descricoes' THEN similarity(c.descricao, p_query) > v_similarity_threshold
      WHEN p_buscar_em = 'solucoes' THEN similarity(c.solucao, p_query) > v_similarity_threshold
      ELSE (similarity(c.descricao, p_query) > v_similarity_threshold
            OR similarity(c.solucao, p_query) > v_similarity_threshold)
    END
    AND (array_length(v_parsed.exclude_terms, 1) IS NULL OR NOT (
      CASE
        WHEN p_buscar_em = 'descricoes' THEN c.descricao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
        WHEN p_buscar_em = 'solucoes' THEN c.solucao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
        ELSE (c.descricao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t)
              OR c.solucao ILIKE ANY(SELECT '%' || t || '%' FROM unnest(v_parsed.exclude_terms) t))
      END
    ))
    AND (
      (v_use_array AND c.grupo_designado = ANY(p_grupos_designados))
      OR (NOT v_use_array AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado))
    )
    AND (p_data_inicio IS NULL OR c.data_abertura::date >= p_data_inicio)
    AND (p_data_fim IS NULL OR c.data_abertura::date <= p_data_fim)
    AND (
      p_filtro_solucao = 'tanto-faz'
      OR (p_filtro_solucao = 'com-solucao' AND c.solucao IS NOT NULL AND TRIM(c.solucao) <> '' AND TRIM(c.solucao) <> '-')
      OR (p_filtro_solucao = 'sem-solucao' AND (c.solucao IS NULL OR TRIM(c.solucao) = '' OR TRIM(c.solucao) = '-'))
    )
  ORDER BY score DESC, c.data_abertura DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$;

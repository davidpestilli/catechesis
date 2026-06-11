-- Fix: oraculo_chamados.data_abertura virou TIMESTAMP enquanto data_envio_aceite continua DATE.
-- A subtração TIMESTAMP - DATE retorna INTERVAL e não pode ser cast para NUMERIC,
-- quebrando funções que calculam tempo de resposta. Solução: cast ::date em ambos os lados.

-- =========================================================================
-- 1) obter_tempo_resposta_stats
-- =========================================================================
CREATE OR REPLACE FUNCTION public.obter_tempo_resposta_stats(p_dias integer DEFAULT NULL::integer, p_equipe text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
AS $function$
DECLARE
  v_data_inicio DATE;
  v_iqr_upper NUMERIC;
  v_result JSONB;
  v_total_base BIGINT;
  v_sem_aceite BIGINT;
  v_sem_aceite_fechados BIGINT;
  v_data_invertida BIGINT;
  v_outliers BIGINT;
BEGIN
  IF p_dias IS NOT NULL THEN
    v_data_inicio := CURRENT_DATE - (p_dias || ' days')::INTERVAL;
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE data_envio_aceite IS NULL),
    COUNT(*) FILTER (WHERE data_envio_aceite IS NULL AND status_operacional = 'Fechado'),
    COUNT(*) FILTER (WHERE data_envio_aceite IS NOT NULL AND data_abertura IS NOT NULL AND data_envio_aceite::date < data_abertura::date)
  INTO v_total_base, v_sem_aceite, v_sem_aceite_fechados, v_data_invertida
  FROM oraculo_chamados c
  WHERE (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
    AND (p_equipe IS NULL OR c.designado_localizacao = p_equipe);

  SELECT INTO v_iqr_upper
    percentile_cont(0.75) WITHIN GROUP (ORDER BY tempo_dias)
    + 1.5 * (
      percentile_cont(0.75) WITHIN GROUP (ORDER BY tempo_dias)
      - percentile_cont(0.25) WITHIN GROUP (ORDER BY tempo_dias)
    )
  FROM (
    SELECT (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC AS tempo_dias
    FROM oraculo_chamados c
    WHERE c.data_envio_aceite IS NOT NULL
      AND c.data_abertura IS NOT NULL
      AND c.data_envio_aceite::date >= c.data_abertura::date
      AND (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
      AND (p_equipe IS NULL OR c.designado_localizacao = p_equipe)
  ) sub;

  IF v_iqr_upper IS NULL THEN
    RETURN jsonb_build_object(
      'total_tickets', 0,
      'histograma', '[]'::JSONB,
      'evolucao_percentis', '[]'::JSONB,
      'distribuicao_equipes', '[]'::JSONB,
      'resumo', jsonb_build_object('p50_dias', 0, 'p75_dias', 0, 'p90_dias', 0, 'media_dias', 0),
      'diagnostico', jsonb_build_object(
        'total_base', v_total_base,
        'sem_aceite', v_sem_aceite,
        'sem_aceite_fechados', v_sem_aceite_fechados,
        'sem_aceite_em_andamento', v_sem_aceite - v_sem_aceite_fechados,
        'data_invertida', v_data_invertida,
        'outliers_removidos', 0,
        'iqr_threshold_dias', 0
      )
    );
  END IF;

  IF v_iqr_upper < 1 THEN
    v_iqr_upper := 30;
  END IF;

  SELECT COUNT(*) INTO v_outliers
  FROM oraculo_chamados c
  WHERE c.data_envio_aceite IS NOT NULL
    AND c.data_abertura IS NOT NULL
    AND c.data_envio_aceite::date >= c.data_abertura::date
    AND (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC > v_iqr_upper
    AND (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
    AND (p_equipe IS NULL OR c.designado_localizacao = p_equipe);

  SELECT INTO v_result jsonb_build_object(
    'total_tickets', (
      SELECT COUNT(*)
      FROM oraculo_chamados c
      WHERE c.data_envio_aceite IS NOT NULL
        AND c.data_abertura IS NOT NULL
        AND c.data_envio_aceite::date >= c.data_abertura::date
        AND (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC <= v_iqr_upper
        AND (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
        AND (p_equipe IS NULL OR c.designado_localizacao = p_equipe)
    ),
    'resumo', (
      SELECT jsonb_build_object(
        'p50_dias', ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY tempo_dias)::NUMERIC, 1),
        'p75_dias', ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY tempo_dias)::NUMERIC, 1),
        'p90_dias', ROUND(percentile_cont(0.90) WITHIN GROUP (ORDER BY tempo_dias)::NUMERIC, 1),
        'media_dias', ROUND(AVG(tempo_dias)::NUMERIC, 1)
      )
      FROM (
        SELECT (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC AS tempo_dias
        FROM oraculo_chamados c
        WHERE c.data_envio_aceite IS NOT NULL
          AND c.data_abertura IS NOT NULL
          AND c.data_envio_aceite::date >= c.data_abertura::date
          AND (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC <= v_iqr_upper
          AND (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
          AND (p_equipe IS NULL OR c.designado_localizacao = p_equipe)
      ) sub
    ),
    'histograma', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object('faixa', faixa, 'faixa_ordem', faixa_ordem, 'total', total)
        ORDER BY faixa_ordem
      ), '[]'::JSONB)
      FROM (
        SELECT
          CASE
            WHEN tempo_dias = 0 THEN 'Mesmo dia'
            WHEN tempo_dias = 1 THEN '1 dia'
            WHEN tempo_dias <= 3 THEN '2-3 dias'
            WHEN tempo_dias <= 7 THEN '4-7 dias'
            ELSE '8+ dias'
          END AS faixa,
          CASE
            WHEN tempo_dias = 0 THEN 1
            WHEN tempo_dias = 1 THEN 2
            WHEN tempo_dias <= 3 THEN 3
            WHEN tempo_dias <= 7 THEN 4
            ELSE 5
          END AS faixa_ordem,
          COUNT(*)::INTEGER AS total
        FROM (
          SELECT (c.data_envio_aceite::date - c.data_abertura::date)::INTEGER AS tempo_dias
          FROM oraculo_chamados c
          WHERE c.data_envio_aceite IS NOT NULL
            AND c.data_abertura IS NOT NULL
            AND c.data_envio_aceite::date >= c.data_abertura::date
            AND (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC <= v_iqr_upper
            AND (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
            AND (p_equipe IS NULL OR c.designado_localizacao = p_equipe)
        ) sub
        GROUP BY faixa, faixa_ordem
      ) agg
    ),
    'evolucao_percentis', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object('periodo', periodo, 'p50', p50, 'p75', p75, 'p90', p90, 'total', total)
        ORDER BY min_data
      ), '[]'::JSONB)
      FROM (
        SELECT
          CASE
            WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
            WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
            ELSE TO_CHAR(c.data_abertura, 'DD/MM')
          END AS periodo,
          MIN(c.data_abertura) AS min_data,
          ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC)::NUMERIC, 1) AS p50,
          ROUND(percentile_cont(0.75) WITHIN GROUP (ORDER BY (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC)::NUMERIC, 1) AS p75,
          ROUND(percentile_cont(0.90) WITHIN GROUP (ORDER BY (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC)::NUMERIC, 1) AS p90,
          COUNT(*)::INTEGER AS total
        FROM oraculo_chamados c
        WHERE c.data_envio_aceite IS NOT NULL
          AND c.data_abertura IS NOT NULL
          AND c.data_envio_aceite::date >= c.data_abertura::date
          AND (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC <= v_iqr_upper
          AND (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
          AND (p_equipe IS NULL OR c.designado_localizacao = p_equipe)
        GROUP BY periodo
      ) agg
    ),
    'distribuicao_equipes', (
      SELECT COALESCE(jsonb_agg(
        jsonb_build_object(
          'equipe', equipe, 'nome', nome, 'total', total, 'p50_dias', p50,
          'mesmo_dia', mesmo_dia, 'um_dia', um_dia,
          'dois_tres_dias', dois_tres_dias, 'quatro_sete_dias', quatro_sete_dias,
          'oito_mais_dias', oito_mais_dias
        )
        ORDER BY p50, total DESC
      ), '[]'::JSONB)
      FROM (
        SELECT
          c.designado_localizacao AS equipe,
          CASE c.designado_localizacao
            WHEN '2.2.1' THEN '1ª Instância'
            WHEN '2.3.1' THEN '2ª Instância'
            WHEN '2.3.2' THEN 'Pub. Externo'
            WHEN 'IT2B' THEN 'IT2B'
          END AS nome,
          COUNT(*)::INTEGER AS total,
          ROUND(percentile_cont(0.50) WITHIN GROUP (ORDER BY (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC)::NUMERIC, 1) AS p50,
          SUM(CASE WHEN (c.data_envio_aceite::date - c.data_abertura::date) = 0 THEN 1 ELSE 0 END)::INTEGER AS mesmo_dia,
          SUM(CASE WHEN (c.data_envio_aceite::date - c.data_abertura::date) = 1 THEN 1 ELSE 0 END)::INTEGER AS um_dia,
          SUM(CASE WHEN (c.data_envio_aceite::date - c.data_abertura::date) BETWEEN 2 AND 3 THEN 1 ELSE 0 END)::INTEGER AS dois_tres_dias,
          SUM(CASE WHEN (c.data_envio_aceite::date - c.data_abertura::date) BETWEEN 4 AND 7 THEN 1 ELSE 0 END)::INTEGER AS quatro_sete_dias,
          SUM(CASE WHEN (c.data_envio_aceite::date - c.data_abertura::date) >= 8 THEN 1 ELSE 0 END)::INTEGER AS oito_mais_dias
        FROM oraculo_chamados c
        WHERE c.data_envio_aceite IS NOT NULL
          AND c.data_abertura IS NOT NULL
          AND c.data_envio_aceite::date >= c.data_abertura::date
          AND (c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC <= v_iqr_upper
          AND c.designado_localizacao IN ('2.2.1', '2.3.1', '2.3.2', 'IT2B')
          AND (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
        GROUP BY c.designado_localizacao
      ) agg
    ),
    'diagnostico', jsonb_build_object(
      'total_base', v_total_base,
      'sem_aceite', v_sem_aceite,
      'sem_aceite_fechados', v_sem_aceite_fechados,
      'sem_aceite_em_andamento', v_sem_aceite - v_sem_aceite_fechados,
      'data_invertida', v_data_invertida,
      'outliers_removidos', v_outliers,
      'iqr_threshold_dias', ROUND(v_iqr_upper::NUMERIC, 0)
    )
  );

  RETURN v_result;
END;
$function$;
-- =========================================================================
-- 2) obter_respondentes_mais_rapidos
-- =========================================================================
CREATE OR REPLACE FUNCTION public.obter_respondentes_mais_rapidos(p_limit integer DEFAULT 10, p_grupo_designado text DEFAULT NULL::text, p_dias integer DEFAULT NULL::integer)
 RETURNS TABLE(nome text, total_respostas bigint, tempo_medio_horas numeric, tempo_medio_dias numeric)
 LANGUAGE plpgsql
 STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    c.nome_designado AS nome,
    COUNT(*)::BIGINT AS total_respostas,
    ROUND(AVG((c.data_envio_aceite::date - c.data_abertura::date) * 24.0)::NUMERIC, 2) AS tempo_medio_horas,
    ROUND(AVG(c.data_envio_aceite::date - c.data_abertura::date)::NUMERIC, 2) AS tempo_medio_dias
  FROM oraculo_chamados c
  WHERE
    c.nome_designado IS NOT NULL
    AND TRIM(c.nome_designado) <> ''
    AND c.data_envio_aceite IS NOT NULL
    AND c.data_abertura IS NOT NULL
    AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado)
    AND (p_dias IS NULL OR c.data_envio_aceite >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
  GROUP BY c.nome_designado
  HAVING COUNT(*) >= 3
  ORDER BY tempo_medio_dias ASC
  LIMIT p_limit;
END;
$function$;

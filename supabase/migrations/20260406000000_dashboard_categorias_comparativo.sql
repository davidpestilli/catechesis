-- =====================================================
-- MIGRATION 123: Adiciona parâmetro p_incluir_comparativo à RPC
-- Data: 2026-04-06
-- Motivo: Permitir comparação período-sobre-período no Dashboard
--         de Categorias (Distribuição). Quando ativado, retorna
--         campo extra "comparativo" com stats do período anterior.
-- Pré-requisito: 122 aplicado
-- =====================================================

-- Drop da versão anterior com 3 params para recriar com 4
DROP FUNCTION IF EXISTS public.obter_estatisticas_categorias(UUID, TEXT, TEXT);
CREATE OR REPLACE FUNCTION public.obter_estatisticas_categorias(
  p_equipe_id UUID DEFAULT NULL,
  p_periodo TEXT DEFAULT 'all',
  p_gse TEXT DEFAULT NULL,
  p_incluir_comparativo BOOLEAN DEFAULT FALSE
)
RETURNS JSONB AS $$
DECLARE
  v_total_analisados INT;
  v_total_categorizados INT;
  v_total_sem_categoria INT;
  v_categorias JSONB;
  v_por_origem JSONB;
  v_data_inicio TIMESTAMP;
  v_data_fim TIMESTAMP;
  v_now TIMESTAMP := (NOW() AT TIME ZONE 'America/Sao_Paulo')::TIMESTAMP;
  v_usa_hierarquico BOOLEAN := FALSE;
  v_resultado JSONB;
  -- Comparativo
  v_prev_data_inicio TIMESTAMP;
  v_prev_data_fim TIMESTAMP;
  v_prev_total_analisados INT;
  v_prev_total_categorizados INT;
  v_prev_total_sem_categoria INT;
  v_prev_categorias JSONB;
  v_prev_por_origem JSONB;
  v_comparativo JSONB;
BEGIN
  -- Detectar se a equipe usa o sistema hierárquico
  IF p_equipe_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM categorias_equipe 
      WHERE equipe_id = p_equipe_id AND ativo = TRUE
      LIMIT 1
    ) INTO v_usa_hierarquico;
  END IF;

  -- Janela fechada [v_data_inicio, v_data_fim) com fronteiras truncadas
  CASE p_periodo
    WHEN '24h' THEN
      v_data_inicio := date_trunc('hour', v_now - INTERVAL '24 hours');
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
    WHEN '48h' THEN
      v_data_inicio := date_trunc('hour', v_now - INTERVAL '48 hours');
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
    WHEN '72h' THEN
      v_data_inicio := date_trunc('hour', v_now - INTERVAL '72 hours');
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
    WHEN '7d'  THEN
      v_data_inicio := date_trunc('day',  v_now - INTERVAL '7 days');
      v_data_fim    := date_trunc('day',  v_now) + INTERVAL '1 day';
    WHEN '30d' THEN
      v_data_inicio := date_trunc('day',  v_now - INTERVAL '30 days');
      v_data_fim    := date_trunc('day',  v_now) + INTERVAL '1 day';
    WHEN 'all' THEN
      v_data_inicio := '2020-01-01'::TIMESTAMP;
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
    ELSE
      v_data_inicio := '2020-01-01'::TIMESTAMP;
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
  END CASE;

  IF v_usa_hierarquico THEN
    -- ============ SISTEMA HIERÁRQUICO ============
    SELECT 
      COUNT(*),
      COUNT(CASE WHEN ta.categoria_equipe_id IS NOT NULL THEN 1 END),
      COUNT(CASE WHEN ta.categoria_equipe_id IS NULL THEN 1 END)
    INTO 
      v_total_analisados,
      v_total_categorizados,
      v_total_sem_categoria
    FROM ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    WHERE t.tempo_espera_origem >= v_data_inicio
      AND t.tempo_espera_origem < v_data_fim
      AND (
        CASE
          WHEN p_gse IS NOT NULL THEN t.gse = p_gse
          WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
            SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
          )
          ELSE TRUE
        END
      );

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'slug', ce.slug,
          'id', ce.id,
          'nome', ce.nome,
          'cor', ce.cor_hex,
          'icone', ce.icone,
          'total', COALESCE(cat_count.total, 0),
          'percentual', ROUND(COALESCE(cat_count.total, 0)::numeric / NULLIF(v_total_analisados, 0)::numeric * 100, 1)
        ) ORDER BY COALESCE(cat_count.total, 0) DESC
      ),
      '[]'::jsonb
    )
    INTO v_categorias
    FROM categorias_equipe ce
    LEFT JOIN (
      SELECT 
        ta.categoria_equipe_id,
        COUNT(*) as total
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE ta.categoria_equipe_id IS NOT NULL
        AND t.tempo_espera_origem >= v_data_inicio
        AND t.tempo_espera_origem < v_data_fim
        AND (
          CASE
            WHEN p_gse IS NOT NULL THEN t.gse = p_gse
            WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
              SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
            )
            ELSE TRUE
          END
        )
      GROUP BY ta.categoria_equipe_id
    ) cat_count ON ce.id = cat_count.categoria_equipe_id
    WHERE ce.equipe_id = p_equipe_id AND ce.ativo = TRUE;

    SELECT jsonb_build_object(
      'ia', COUNT(CASE WHEN ta.cat_hierarquica_origem IN ('ia', 'script') THEN 1 END),
      'manual', COUNT(CASE WHEN ta.cat_hierarquica_origem = 'manual' THEN 1 END)
    )
    INTO v_por_origem
    FROM ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    WHERE ta.categoria_equipe_id IS NOT NULL
      AND t.tempo_espera_origem >= v_data_inicio
      AND t.tempo_espera_origem < v_data_fim
      AND (
        CASE
          WHEN p_gse IS NOT NULL THEN t.gse = p_gse
          WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
            SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
          )
          ELSE TRUE
        END
      );

  ELSE
    -- ============ SISTEMA ANTIGO (flat) ============
    SELECT 
      COUNT(*),
      COUNT(CASE WHEN ta.categoria_slug IS NOT NULL THEN 1 END),
      COUNT(CASE WHEN ta.categoria_slug IS NULL THEN 1 END)
    INTO 
      v_total_analisados,
      v_total_categorizados,
      v_total_sem_categoria
    FROM ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    WHERE (ta.categoria_slug IS NULL OR ta.categoria_slug != 'indefinido')
      AND t.tempo_espera_origem >= v_data_inicio
      AND t.tempo_espera_origem < v_data_fim
      AND (
        CASE
          WHEN p_gse IS NOT NULL THEN t.gse = p_gse
          WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
            SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
          )
          ELSE TRUE
        END
      );

    SELECT COALESCE(
      jsonb_agg(
        jsonb_build_object(
          'slug', cc.slug,
          'nome', cc.nome,
          'cor', cc.cor_hex,
          'icone', cc.icone,
          'total', COALESCE(cat_count.total, 0),
          'percentual', ROUND(COALESCE(cat_count.total, 0)::numeric / NULLIF(v_total_analisados, 0)::numeric * 100, 1)
        ) ORDER BY COALESCE(cat_count.total, 0) DESC
      ),
      '[]'::jsonb
    )
    INTO v_categorias
    FROM categorias_chamado cc
    LEFT JOIN (
      SELECT 
        ta.categoria_slug,
        COUNT(*) as total
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE ta.categoria_slug != 'indefinido'
        AND t.tempo_espera_origem >= v_data_inicio
        AND t.tempo_espera_origem < v_data_fim
        AND (
          CASE
            WHEN p_gse IS NOT NULL THEN t.gse = p_gse
            WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
              SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
            )
            ELSE TRUE
          END
        )
      GROUP BY ta.categoria_slug
    ) cat_count ON cc.slug = cat_count.categoria_slug
    WHERE cc.slug != 'indefinido';

    SELECT jsonb_build_object(
      'ia', COUNT(CASE WHEN ta.categoria_origem = 'ia' THEN 1 END),
      'manual', COUNT(CASE WHEN ta.categoria_origem = 'manual' THEN 1 END)
    )
    INTO v_por_origem
    FROM ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    WHERE ta.categoria_slug IS NOT NULL
      AND ta.categoria_slug != 'indefinido'
      AND t.tempo_espera_origem >= v_data_inicio
      AND t.tempo_espera_origem < v_data_fim
      AND (
        CASE
          WHEN p_gse IS NOT NULL THEN t.gse = p_gse
          WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
            SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
          )
          ELSE TRUE
        END
      );
  END IF;

  -- Montar resultado base
  v_resultado := jsonb_build_object(
    'total_analisados', v_total_analisados,
    'total_categorizados', v_total_categorizados,
    'total_sem_categoria', v_total_sem_categoria,
    'por_categoria', v_categorias,
    'por_origem', v_por_origem,
    'filtro_equipe_aplicado', (p_equipe_id IS NOT NULL),
    'filtro_gse_aplicado', (p_gse IS NOT NULL),
    'usa_hierarquico', v_usa_hierarquico
  );

  -- ============================================================
  -- COMPARATIVO: stats do período anterior equivalente
  -- ============================================================
  IF p_incluir_comparativo AND p_periodo != 'all' THEN
    -- Calcular janela do período anterior (imediatamente antes do atual)
    v_prev_data_fim := v_data_inicio;
    CASE p_periodo
      WHEN '24h' THEN v_prev_data_inicio := v_prev_data_fim - INTERVAL '24 hours';
      WHEN '48h' THEN v_prev_data_inicio := v_prev_data_fim - INTERVAL '48 hours';
      WHEN '72h' THEN v_prev_data_inicio := v_prev_data_fim - INTERVAL '72 hours';
      WHEN '7d'  THEN v_prev_data_inicio := v_prev_data_fim - INTERVAL '7 days';
      WHEN '30d' THEN v_prev_data_inicio := v_prev_data_fim - INTERVAL '30 days';
      ELSE v_prev_data_inicio := v_prev_data_fim - INTERVAL '7 days';
    END CASE;

    IF v_usa_hierarquico THEN
      -- Totais do período anterior (hierárquico)
      SELECT
        COUNT(*),
        COUNT(CASE WHEN ta.categoria_equipe_id IS NOT NULL THEN 1 END),
        COUNT(CASE WHEN ta.categoria_equipe_id IS NULL THEN 1 END)
      INTO
        v_prev_total_analisados,
        v_prev_total_categorizados,
        v_prev_total_sem_categoria
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE t.tempo_espera_origem >= v_prev_data_inicio
        AND t.tempo_espera_origem < v_prev_data_fim
        AND (
          CASE
            WHEN p_gse IS NOT NULL THEN t.gse = p_gse
            WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
              SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
            )
            ELSE TRUE
          END
        );

      -- Categorias do período anterior (hierárquico)
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'slug', ce.slug,
            'id', ce.id,
            'nome', ce.nome,
            'total', COALESCE(cat_count.total, 0),
            'percentual', ROUND(COALESCE(cat_count.total, 0)::numeric / NULLIF(v_prev_total_analisados, 0)::numeric * 100, 1)
          ) ORDER BY COALESCE(cat_count.total, 0) DESC
        ),
        '[]'::jsonb
      )
      INTO v_prev_categorias
      FROM categorias_equipe ce
      LEFT JOIN (
        SELECT ta.categoria_equipe_id, COUNT(*) as total
        FROM ticket_analises ta
        JOIN public.tickets t ON t.id = ta.ticket_id
        WHERE ta.categoria_equipe_id IS NOT NULL
          AND t.tempo_espera_origem >= v_prev_data_inicio
          AND t.tempo_espera_origem < v_prev_data_fim
          AND (
            CASE
              WHEN p_gse IS NOT NULL THEN t.gse = p_gse
              WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
                SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
              )
              ELSE TRUE
            END
          )
        GROUP BY ta.categoria_equipe_id
      ) cat_count ON ce.id = cat_count.categoria_equipe_id
      WHERE ce.equipe_id = p_equipe_id AND ce.ativo = TRUE;

      -- Origem do período anterior (hierárquico)
      SELECT jsonb_build_object(
        'ia', COUNT(CASE WHEN ta.cat_hierarquica_origem IN ('ia', 'script') THEN 1 END),
        'manual', COUNT(CASE WHEN ta.cat_hierarquica_origem = 'manual' THEN 1 END)
      )
      INTO v_prev_por_origem
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE ta.categoria_equipe_id IS NOT NULL
        AND t.tempo_espera_origem >= v_prev_data_inicio
        AND t.tempo_espera_origem < v_prev_data_fim
        AND (
          CASE
            WHEN p_gse IS NOT NULL THEN t.gse = p_gse
            WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
              SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
            )
            ELSE TRUE
          END
        );
    ELSE
      -- Totais do período anterior (flat)
      SELECT
        COUNT(*),
        COUNT(CASE WHEN ta.categoria_slug IS NOT NULL THEN 1 END),
        COUNT(CASE WHEN ta.categoria_slug IS NULL THEN 1 END)
      INTO
        v_prev_total_analisados,
        v_prev_total_categorizados,
        v_prev_total_sem_categoria
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE (ta.categoria_slug IS NULL OR ta.categoria_slug != 'indefinido')
        AND t.tempo_espera_origem >= v_prev_data_inicio
        AND t.tempo_espera_origem < v_prev_data_fim
        AND (
          CASE
            WHEN p_gse IS NOT NULL THEN t.gse = p_gse
            WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
              SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
            )
            ELSE TRUE
          END
        );

      -- Categorias do período anterior (flat)
      SELECT COALESCE(
        jsonb_agg(
          jsonb_build_object(
            'slug', cc.slug,
            'nome', cc.nome,
            'total', COALESCE(cat_count.total, 0),
            'percentual', ROUND(COALESCE(cat_count.total, 0)::numeric / NULLIF(v_prev_total_analisados, 0)::numeric * 100, 1)
          ) ORDER BY COALESCE(cat_count.total, 0) DESC
        ),
        '[]'::jsonb
      )
      INTO v_prev_categorias
      FROM categorias_chamado cc
      LEFT JOIN (
        SELECT ta.categoria_slug, COUNT(*) as total
        FROM ticket_analises ta
        JOIN public.tickets t ON t.id = ta.ticket_id
        WHERE ta.categoria_slug != 'indefinido'
          AND t.tempo_espera_origem >= v_prev_data_inicio
          AND t.tempo_espera_origem < v_prev_data_fim
          AND (
            CASE
              WHEN p_gse IS NOT NULL THEN t.gse = p_gse
              WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
                SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
              )
              ELSE TRUE
            END
          )
        GROUP BY ta.categoria_slug
      ) cat_count ON cc.slug = cat_count.categoria_slug
      WHERE cc.slug != 'indefinido';

      -- Origem do período anterior (flat)
      SELECT jsonb_build_object(
        'ia', COUNT(CASE WHEN ta.categoria_origem = 'ia' THEN 1 END),
        'manual', COUNT(CASE WHEN ta.categoria_origem = 'manual' THEN 1 END)
      )
      INTO v_prev_por_origem
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE ta.categoria_slug IS NOT NULL
        AND ta.categoria_slug != 'indefinido'
        AND t.tempo_espera_origem >= v_prev_data_inicio
        AND t.tempo_espera_origem < v_prev_data_fim
        AND (
          CASE
            WHEN p_gse IS NOT NULL THEN t.gse = p_gse
            WHEN p_equipe_id IS NOT NULL THEN t.gse IN (
              SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id
            )
            ELSE TRUE
          END
        );
    END IF;

    v_comparativo := jsonb_build_object(
      'total_analisados', v_prev_total_analisados,
      'total_categorizados', v_prev_total_categorizados,
      'total_sem_categoria', v_prev_total_sem_categoria,
      'por_categoria', v_prev_categorias,
      'por_origem', v_prev_por_origem,
      'data_inicio', v_prev_data_inicio,
      'data_fim', v_prev_data_fim
    );

    v_resultado := v_resultado || jsonb_build_object('comparativo', v_comparativo);
  END IF;

  RETURN v_resultado;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- Drop old 1-param overload if it exists (from pre-122 migrations)
DROP FUNCTION IF EXISTS public.obter_estatisticas_categorias(UUID);
-- Grants para nova assinatura
GRANT EXECUTE ON FUNCTION public.obter_estatisticas_categorias(UUID, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_estatisticas_categorias(UUID, TEXT, TEXT, BOOLEAN) TO service_role;

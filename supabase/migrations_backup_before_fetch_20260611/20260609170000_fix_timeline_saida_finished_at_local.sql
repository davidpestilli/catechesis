-- Alinha a aba "Linha do Tempo: Saída" com a aba "Métricas".
-- O campo tickets.finished_at é armazenado como timestamp local (sem timezone),
-- então a conversão UTC -> America/Sao_Paulo adiantava os dados em 3 horas.

CREATE OR REPLACE FUNCTION public.obter_categorias_temporais_saida(
  p_periodo TEXT DEFAULT '7d',
  p_equipe_id UUID DEFAULT NULL,
  p_categoria_slug TEXT DEFAULT NULL,
  p_categoria_equipe_id UUID DEFAULT NULL,
  p_atendentes UUID[] DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_data_inicio TIMESTAMP;
  v_data_fim TIMESTAMP;
  v_intervalo TEXT;
  v_formato_label TEXT;
  v_resultado JSONB;
  v_items TEXT[];
  v_items_uuid UUID[];
  v_now TIMESTAMP := (NOW() AT TIME ZONE 'America/Sao_Paulo')::TIMESTAMP;
  v_modo_subcategoria BOOLEAN;
  v_usa_hierarquico BOOLEAN := FALSE;
  v_tem_filtro_atendentes BOOLEAN := (p_atendentes IS NOT NULL AND array_length(p_atendentes, 1) > 0);
  v_total_geral BIGINT := 0;
BEGIN
  IF p_equipe_id IS NOT NULL THEN
    SELECT EXISTS(
      SELECT 1 FROM categorias_equipe
      WHERE equipe_id = p_equipe_id AND ativo = TRUE
      LIMIT 1
    ) INTO v_usa_hierarquico;
  END IF;

  CASE p_periodo
    WHEN '24h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '24 hours';
      v_intervalo := '1 hour';
      v_formato_label := 'HH24:00';
    WHEN '48h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '48 hours';
      v_intervalo := '2 hours';
      v_formato_label := 'DD/MM HH24h';
    WHEN '72h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '72 hours';
      v_intervalo := '3 hours';
      v_formato_label := 'DD/MM HH24h';
    WHEN '7d' THEN
      v_data_inicio := date_trunc('day', v_now - INTERVAL '7 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 day';
      v_formato_label := 'DD/MM';
    WHEN '30d' THEN
      v_data_inicio := date_trunc('day', v_now - INTERVAL '30 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 week';
      v_formato_label := 'DD/MM';
    WHEN 'all' THEN
      v_data_inicio := '2020-01-01'::TIMESTAMP;
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 month';
      v_formato_label := 'MM/YYYY';
    ELSE
      v_data_inicio := date_trunc('day', v_now - INTERVAL '7 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 day';
      v_formato_label := 'DD/MM';
  END CASE;

  IF v_usa_hierarquico THEN
    v_modo_subcategoria := (p_categoria_equipe_id IS NOT NULL);

    IF v_modo_subcategoria THEN
      SELECT COUNT(*) INTO v_total_geral
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      JOIN subcategorias_gse sg ON ta.subcategoria_gse_id = sg.id
      JOIN categorias_gse cg ON sg.categoria_gse_id = cg.id
      WHERE cg.categoria_equipe_id = p_categoria_equipe_id
        AND ta.subcategoria_gse_id IS NOT NULL
        AND t.finished_at IS NOT NULL
        AND t.status = 'finalizado'
        AND t.usuario_atual IS NOT NULL
        AND t.finished_at >= v_data_inicio
        AND t.finished_at < v_data_fim
        AND (p_equipe_id IS NULL OR t.gse IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id))
        AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes));
    ELSE
      SELECT COUNT(*) INTO v_total_geral
      FROM public.tickets t
      WHERE t.finished_at IS NOT NULL
        AND t.status = 'finalizado'
        AND t.usuario_atual IS NOT NULL
        AND t.finished_at >= v_data_inicio
        AND t.finished_at < v_data_fim
        AND (p_equipe_id IS NULL OR t.gse IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id))
        AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes));
    END IF;

    IF v_modo_subcategoria THEN
      SELECT ARRAY_AGG(sub_id ORDER BY cnt DESC)
      INTO v_items_uuid
      FROM (
        SELECT ta.subcategoria_gse_id AS sub_id, COUNT(*) AS cnt
        FROM ticket_analises ta
        JOIN public.tickets t ON t.id = ta.ticket_id
        JOIN subcategorias_gse sg ON ta.subcategoria_gse_id = sg.id
        JOIN categorias_gse cg ON sg.categoria_gse_id = cg.id
        WHERE cg.categoria_equipe_id = p_categoria_equipe_id
          AND ta.subcategoria_gse_id IS NOT NULL
          AND t.finished_at IS NOT NULL
          AND t.status = 'finalizado'
          AND t.usuario_atual IS NOT NULL
          AND t.finished_at >= v_data_inicio
          AND t.finished_at < v_data_fim
          AND (p_equipe_id IS NULL OR t.gse IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id))
          AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
        GROUP BY ta.subcategoria_gse_id
        ORDER BY cnt DESC
        LIMIT 8
      ) top;
    ELSE
      SELECT ARRAY_AGG(cat_id ORDER BY cnt DESC)
      INTO v_items_uuid
      FROM (
        SELECT ta.categoria_equipe_id AS cat_id, COUNT(*) AS cnt
        FROM ticket_analises ta
        JOIN public.tickets t ON t.id = ta.ticket_id
        WHERE ta.categoria_equipe_id IS NOT NULL
          AND t.finished_at IS NOT NULL
          AND t.status = 'finalizado'
          AND t.usuario_atual IS NOT NULL
          AND t.finished_at >= v_data_inicio
          AND t.finished_at < v_data_fim
          AND (p_equipe_id IS NULL OR t.gse IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id))
          AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
        GROUP BY ta.categoria_equipe_id
        ORDER BY cnt DESC
        LIMIT 5
      ) top;
    END IF;

    IF v_items_uuid IS NULL OR array_length(v_items_uuid, 1) = 0 THEN
      RETURN jsonb_build_object(
        'periodo', p_periodo,
        'data_inicio', v_data_inicio,
        'data_fim', v_data_fim,
        'intervalo', v_intervalo,
        'categorias', '[]'::jsonb,
        'series', '{}'::jsonb,
        'labels', '[]'::jsonb,
        'modo', CASE WHEN v_modo_subcategoria THEN 'subcategoria' ELSE 'categoria' END,
        'categoria_filtro', p_categoria_equipe_id,
        'usa_hierarquico', true,
        'total_geral', v_total_geral
      );
    END IF;

    WITH base_data AS MATERIALIZED (
      SELECT
        ta.categoria_equipe_id,
        ta.subcategoria_gse_id,
        t.finished_at AS finished_at_sp
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE ta.categoria_equipe_id IS NOT NULL
        AND t.finished_at IS NOT NULL
        AND t.status = 'finalizado'
        AND t.usuario_atual IS NOT NULL
        AND t.finished_at >= v_data_inicio
        AND t.finished_at < v_data_fim
        AND (p_equipe_id IS NULL OR t.gse IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id))
        AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
        AND (
          CASE WHEN v_modo_subcategoria
            THEN ta.subcategoria_gse_id = ANY(v_items_uuid)
            ELSE ta.categoria_equipe_id = ANY(v_items_uuid)
          END
        )
    ),
    periodos AS (
      SELECT
        generate_series(
          date_trunc(
            CASE v_intervalo
              WHEN '1 hour'  THEN 'hour'
              WHEN '2 hours' THEN 'hour'
              WHEN '3 hours' THEN 'hour'
              WHEN '1 day'   THEN 'day'
              WHEN '1 week'  THEN 'week'
              WHEN '1 month' THEN 'month'
            END,
            v_data_inicio
          ),
          v_data_fim - v_intervalo::INTERVAL,
          v_intervalo::INTERVAL
        ) AS periodo_inicio
    ),
    contagens AS (
      SELECT
        p.periodo_inicio,
        items.item_id,
        COUNT(b.finished_at_sp) AS total
      FROM periodos p
      CROSS JOIN (SELECT UNNEST(v_items_uuid) AS item_id) items
      LEFT JOIN base_data b
        ON b.finished_at_sp >= p.periodo_inicio
        AND b.finished_at_sp < p.periodo_inicio + v_intervalo::INTERVAL
        AND (
          CASE WHEN v_modo_subcategoria
            THEN b.subcategoria_gse_id = items.item_id
            ELSE b.categoria_equipe_id = items.item_id
          END
        )
      GROUP BY p.periodo_inicio, items.item_id
    ),
    series_data AS (
      SELECT
        item_id,
        jsonb_agg(
          jsonb_build_object(
            'periodo', to_char(periodo_inicio, v_formato_label),
            'timestamp', periodo_inicio,
            'total', COALESCE(total, 0)
          ) ORDER BY periodo_inicio
        ) AS dados
      FROM contagens
      WHERE item_id IS NOT NULL
      GROUP BY item_id
    ),
    labels_data AS (
      SELECT jsonb_agg(
        DISTINCT to_char(periodo_inicio, v_formato_label)
        ORDER BY to_char(periodo_inicio, v_formato_label)
      ) AS labels
      FROM periodos
    )
    SELECT jsonb_build_object(
      'periodo', p_periodo,
      'data_inicio', v_data_inicio,
      'data_fim', v_data_fim,
      'intervalo', v_intervalo,
      'modo', CASE WHEN v_modo_subcategoria THEN 'subcategoria' ELSE 'categoria' END,
      'categoria_filtro', p_categoria_equipe_id,
      'usa_hierarquico', true,
      'total_geral', v_total_geral,
      'categorias', CASE
        WHEN v_modo_subcategoria THEN (
          SELECT COALESCE(jsonb_agg(
            jsonb_build_object('id', sg.id, 'nome', sg.nome, 'cor', NULL, 'icone', NULL)
          ), '[]'::jsonb)
          FROM subcategorias_gse sg
          WHERE sg.id = ANY(v_items_uuid)
        )
        ELSE (
          SELECT COALESCE(jsonb_agg(
            jsonb_build_object('id', ce.id, 'nome', ce.nome, 'cor', ce.cor_hex, 'icone', ce.icone)
          ), '[]'::jsonb)
          FROM categorias_equipe ce
          WHERE ce.id = ANY(v_items_uuid)
        )
      END,
      'series', (
        SELECT COALESCE(jsonb_object_agg(item_id::text, dados), '{}'::jsonb)
        FROM series_data
      ),
      'labels', (SELECT labels FROM labels_data)
    )
    INTO v_resultado;

    RETURN v_resultado;

  ELSE
    v_modo_subcategoria := (p_categoria_slug IS NOT NULL);

    IF v_modo_subcategoria THEN
      SELECT COUNT(*) INTO v_total_geral
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE ta.categoria_slug = p_categoria_slug
        AND ta.subcategoria_slug IS NOT NULL
        AND t.finished_at IS NOT NULL
        AND t.status = 'finalizado'
        AND t.usuario_atual IS NOT NULL
        AND t.finished_at >= v_data_inicio
        AND t.finished_at < v_data_fim
        AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes));
    ELSE
      SELECT COUNT(*) INTO v_total_geral
      FROM public.tickets t
      WHERE t.finished_at IS NOT NULL
        AND t.status = 'finalizado'
        AND t.usuario_atual IS NOT NULL
        AND t.finished_at >= v_data_inicio
        AND t.finished_at < v_data_fim
        AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes));
    END IF;

    IF v_modo_subcategoria THEN
      SELECT ARRAY_AGG(subcategoria_slug ORDER BY cnt DESC)
      INTO v_items
      FROM (
        SELECT ta.subcategoria_slug, COUNT(*) AS cnt
        FROM ticket_analises ta
        JOIN public.tickets t ON t.id = ta.ticket_id
        WHERE ta.categoria_slug = p_categoria_slug
          AND ta.subcategoria_slug IS NOT NULL
          AND t.finished_at IS NOT NULL
          AND t.status = 'finalizado'
          AND t.usuario_atual IS NOT NULL
          AND t.finished_at >= v_data_inicio
          AND t.finished_at < v_data_fim
          AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
        GROUP BY ta.subcategoria_slug
        ORDER BY cnt DESC
        LIMIT 8
      ) top;
    ELSE
      SELECT ARRAY_AGG(categoria_slug ORDER BY cnt DESC)
      INTO v_items
      FROM (
        SELECT ta.categoria_slug, COUNT(*) AS cnt
        FROM ticket_analises ta
        JOIN public.tickets t ON t.id = ta.ticket_id
        WHERE ta.categoria_slug IS NOT NULL
          AND ta.categoria_slug != 'indefinido'
          AND t.finished_at IS NOT NULL
          AND t.status = 'finalizado'
          AND t.usuario_atual IS NOT NULL
          AND t.finished_at >= v_data_inicio
          AND t.finished_at < v_data_fim
          AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
        GROUP BY ta.categoria_slug
        ORDER BY cnt DESC
        LIMIT 5
      ) top;
    END IF;

    IF v_items IS NULL OR array_length(v_items, 1) = 0 THEN
      RETURN jsonb_build_object(
        'periodo', p_periodo,
        'data_inicio', v_data_inicio,
        'data_fim', v_data_fim,
        'intervalo', v_intervalo,
        'categorias', '[]'::jsonb,
        'series', '{}'::jsonb,
        'labels', '[]'::jsonb,
        'modo', CASE WHEN v_modo_subcategoria THEN 'subcategoria' ELSE 'categoria' END,
        'categoria_filtro', p_categoria_slug,
        'total_geral', v_total_geral
      );
    END IF;

    WITH base_data AS MATERIALIZED (
      SELECT
        ta.categoria_slug,
        ta.subcategoria_slug,
        t.finished_at AS finished_at_sp
      FROM ticket_analises ta
      JOIN public.tickets t ON t.id = ta.ticket_id
      WHERE ta.categoria_slug IS NOT NULL
        AND ta.categoria_slug != 'indefinido'
        AND t.finished_at IS NOT NULL
        AND t.status = 'finalizado'
        AND t.usuario_atual IS NOT NULL
        AND t.finished_at >= v_data_inicio
        AND t.finished_at < v_data_fim
        AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
        AND (
          CASE WHEN v_modo_subcategoria
            THEN ta.categoria_slug = p_categoria_slug
                 AND ta.subcategoria_slug = ANY(v_items)
            ELSE ta.categoria_slug = ANY(v_items)
          END
        )
    ),
    periodos AS (
      SELECT
        generate_series(
          date_trunc(
            CASE v_intervalo
              WHEN '1 hour'  THEN 'hour'
              WHEN '2 hours' THEN 'hour'
              WHEN '3 hours' THEN 'hour'
              WHEN '1 day'   THEN 'day'
              WHEN '1 week'  THEN 'week'
              WHEN '1 month' THEN 'month'
            END,
            v_data_inicio
          ),
          v_data_fim - v_intervalo::INTERVAL,
          v_intervalo::INTERVAL
        ) AS periodo_inicio
    ),
    contagens AS (
      SELECT
        p.periodo_inicio,
        items.item_slug,
        COUNT(b.finished_at_sp) AS total
      FROM periodos p
      CROSS JOIN (SELECT UNNEST(v_items) AS item_slug) items
      LEFT JOIN base_data b
        ON b.finished_at_sp >= p.periodo_inicio
        AND b.finished_at_sp < p.periodo_inicio + v_intervalo::INTERVAL
        AND (
          CASE WHEN v_modo_subcategoria
            THEN b.subcategoria_slug = items.item_slug
            ELSE b.categoria_slug = items.item_slug
          END
        )
      GROUP BY p.periodo_inicio, items.item_slug
    ),
    series_data AS (
      SELECT
        item_slug,
        jsonb_agg(
          jsonb_build_object(
            'periodo', to_char(periodo_inicio, v_formato_label),
            'timestamp', periodo_inicio,
            'total', COALESCE(total, 0)
          ) ORDER BY periodo_inicio
        ) AS dados
      FROM contagens
      WHERE item_slug IS NOT NULL
      GROUP BY item_slug
    ),
    labels_data AS (
      SELECT jsonb_agg(
        DISTINCT to_char(periodo_inicio, v_formato_label)
        ORDER BY to_char(periodo_inicio, v_formato_label)
      ) AS labels
      FROM periodos
    )
    SELECT jsonb_build_object(
      'periodo', p_periodo,
      'data_inicio', v_data_inicio,
      'data_fim', v_data_fim,
      'intervalo', v_intervalo,
      'modo', CASE WHEN v_modo_subcategoria THEN 'subcategoria' ELSE 'categoria' END,
      'categoria_filtro', p_categoria_slug,
      'total_geral', v_total_geral,
      'categorias', CASE
        WHEN v_modo_subcategoria THEN (
          SELECT COALESCE(jsonb_agg(
            jsonb_build_object('slug', sc.slug, 'nome', sc.nome, 'cor', sc.cor_hex, 'icone', sc.icone)
          ), '[]'::jsonb)
          FROM subcategorias_chamado sc
          WHERE sc.slug = ANY(v_items) AND sc.categoria_slug = p_categoria_slug
        )
        ELSE (
          SELECT COALESCE(jsonb_agg(
            jsonb_build_object('slug', cc.slug, 'nome', cc.nome, 'cor', cc.cor_hex, 'icone', cc.icone)
          ), '[]'::jsonb)
          FROM categorias_chamado cc
          WHERE cc.slug = ANY(v_items)
        )
      END,
      'series', (
        SELECT COALESCE(jsonb_object_agg(item_slug, dados), '{}'::jsonb)
        FROM series_data
      ),
      'labels', (SELECT labels FROM labels_data)
    )
    INTO v_resultado;

    RETURN v_resultado;
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.obter_categorias_temporais_saida(TEXT, UUID, TEXT, UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_categorias_temporais_saida(TEXT, UUID, TEXT, UUID, UUID[]) TO service_role;
CREATE OR REPLACE FUNCTION public.obter_distribuicao_tempo_espera_saida(
  p_periodo TEXT DEFAULT '7d',
  p_equipe_id UUID DEFAULT NULL,
  p_atendentes UUID[] DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_data_inicio TIMESTAMP;
  v_data_fim TIMESTAMP;
  v_intervalo TEXT;
  v_formato_label TEXT;
  v_now TIMESTAMP := (NOW() AT TIME ZONE 'America/Sao_Paulo')::TIMESTAMP;
  v_resultado JSONB;
  v_tem_filtro_atendentes BOOLEAN := (p_atendentes IS NOT NULL AND array_length(p_atendentes, 1) > 0);
BEGIN
  CASE p_periodo
    WHEN '24h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '24 hours';
      v_intervalo := '1 hour';
      v_formato_label := 'HH24:00';
    WHEN '48h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '48 hours';
      v_intervalo := '2 hours';
      v_formato_label := 'DD/MM HH24h';
    WHEN '72h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '72 hours';
      v_intervalo := '3 hours';
      v_formato_label := 'DD/MM HH24h';
    WHEN '7d' THEN
      v_data_inicio := date_trunc('day', v_now - INTERVAL '7 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 day';
      v_formato_label := 'DD/MM';
    WHEN '30d' THEN
      v_data_inicio := date_trunc('day', v_now - INTERVAL '30 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 week';
      v_formato_label := 'DD/MM';
    WHEN 'all' THEN
      v_data_inicio := '2020-01-01'::TIMESTAMP;
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 month';
      v_formato_label := 'MM/YYYY';
    ELSE
      v_data_inicio := date_trunc('day', v_now - INTERVAL '7 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
      v_intervalo := '1 day';
      v_formato_label := 'DD/MM';
  END CASE;

  WITH base_data AS MATERIALIZED (
    SELECT
      t.finished_at AS finished_at_sp,
      EXTRACT(EPOCH FROM (t.finished_at - t.tempo_espera_origem)) / 3600.0 AS espera_horas
    FROM public.tickets t
    WHERE t.finished_at IS NOT NULL
      AND t.status = 'finalizado'
      AND t.usuario_atual IS NOT NULL
      AND t.tempo_espera_origem IS NOT NULL
      AND t.finished_at >= v_data_inicio
      AND t.finished_at < v_data_fim
      AND (p_equipe_id IS NULL OR t.gse IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id))
      AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
  ),
  classificado AS (
    SELECT
      finished_at_sp,
      CASE
        WHEN espera_horas < 24 THEN 'ate_24h'
        WHEN espera_horas < 48 THEN '24_48h'
        WHEN espera_horas < 72 THEN '48_72h'
        WHEN espera_horas < 168 THEN '72_168h'
        ELSE 'acima_168h'
      END AS bucket
    FROM base_data
  ),
  buckets_def AS (
    SELECT * FROM (VALUES
      ('ate_24h',    'até 24h',         0,    24,  '#34D399', 1),
      ('24_48h',     '24h – 48h',      24,    48,  '#FBBF24', 2),
      ('48_72h',     '48h – 72h',      48,    72,  '#FB923C', 3),
      ('72_168h',    '3 – 7 dias',     72,   168,  '#F87171', 4),
      ('acima_168h', 'mais de 7 dias', 168, 9999,  '#A855F7', 5)
    ) AS b(id, label, horas_min, horas_max, cor, ord)
  ),
  periodos AS (
    SELECT
      generate_series(
        date_trunc(
          CASE v_intervalo
            WHEN '1 hour'  THEN 'hour'
            WHEN '2 hours' THEN 'hour'
            WHEN '3 hours' THEN 'hour'
            WHEN '1 day'   THEN 'day'
            WHEN '1 week'  THEN 'week'
            WHEN '1 month' THEN 'month'
          END,
          v_data_inicio
        ),
        v_data_fim - v_intervalo::INTERVAL,
        v_intervalo::INTERVAL
      ) AS periodo_inicio
  ),
  contagens AS (
    SELECT
      p.periodo_inicio,
      b.id AS bucket_id,
      COUNT(c.finished_at_sp) AS total
    FROM periodos p
    CROSS JOIN buckets_def b
    LEFT JOIN classificado c
      ON c.bucket = b.id
     AND c.finished_at_sp >= p.periodo_inicio
     AND c.finished_at_sp < p.periodo_inicio + v_intervalo::INTERVAL
    GROUP BY p.periodo_inicio, b.id
  ),
  series_data AS (
    SELECT
      bucket_id,
      jsonb_agg(
        jsonb_build_object(
          'periodo', to_char(periodo_inicio, v_formato_label),
          'timestamp', periodo_inicio,
          'total', COALESCE(total, 0)
        ) ORDER BY periodo_inicio
      ) AS dados
    FROM contagens
    GROUP BY bucket_id
  ),
  totais AS (
    SELECT bucket_id, SUM(total) AS total
    FROM contagens
    GROUP BY bucket_id
  ),
  labels_data AS (
    SELECT jsonb_agg(
      DISTINCT to_char(periodo_inicio, v_formato_label)
      ORDER BY to_char(periodo_inicio, v_formato_label)
    ) AS labels
    FROM periodos
  )
  SELECT jsonb_build_object(
    'periodo', p_periodo,
    'data_inicio', v_data_inicio,
    'data_fim', v_data_fim,
    'intervalo', v_intervalo,
    'buckets', (
      SELECT jsonb_agg(jsonb_build_object(
        'id', id, 'label', label, 'horas_min', horas_min,
        'horas_max', horas_max, 'cor', cor
      ) ORDER BY ord)
      FROM buckets_def
    ),
    'series', (
      SELECT COALESCE(jsonb_object_agg(bucket_id, dados), '{}'::jsonb)
      FROM series_data
    ),
    'totais', (
      SELECT COALESCE(jsonb_object_agg(bucket_id, total), '{}'::jsonb)
      FROM totais
    ),
    'total_geral', (SELECT COALESCE(SUM(total), 0)::BIGINT FROM totais),
    'labels', (SELECT labels FROM labels_data)
  )
  INTO v_resultado;

  RETURN v_resultado;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.obter_distribuicao_tempo_espera_saida(TEXT, UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_distribuicao_tempo_espera_saida(TEXT, UUID, UUID[]) TO service_role;
CREATE OR REPLACE FUNCTION public.obter_atendentes_por_bucket_espera(
  p_periodo TEXT DEFAULT '24h',
  p_equipe_id UUID DEFAULT NULL,
  p_bucket TEXT DEFAULT 'todos',
  p_atendentes UUID[] DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_data_inicio TIMESTAMP;
  v_data_fim TIMESTAMP;
  v_now TIMESTAMP := (NOW() AT TIME ZONE 'America/Sao_Paulo')::TIMESTAMP;
  v_resultado JSONB;
  v_tem_filtro_atendentes BOOLEAN := (p_atendentes IS NOT NULL AND array_length(p_atendentes, 1) > 0);
BEGIN
  CASE p_periodo
    WHEN '24h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '24 hours';
    WHEN '48h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '48 hours';
    WHEN '72h' THEN
      v_data_fim    := date_trunc('hour', v_now) + INTERVAL '1 hour';
      v_data_inicio := v_data_fim - INTERVAL '72 hours';
    WHEN '7d' THEN
      v_data_inicio := date_trunc('day', v_now - INTERVAL '7 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
    WHEN '30d' THEN
      v_data_inicio := date_trunc('day', v_now - INTERVAL '30 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
    WHEN 'all' THEN
      v_data_inicio := '2020-01-01'::TIMESTAMP;
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
    ELSE
      v_data_inicio := date_trunc('day', v_now - INTERVAL '7 days');
      v_data_fim    := date_trunc('day', v_now) + INTERVAL '1 day';
  END CASE;

  WITH filtrado AS MATERIALIZED (
    SELECT
      t.usuario_atual,
      EXTRACT(EPOCH FROM (t.finished_at - t.tempo_espera_origem)) / 3600.0 AS espera_horas
    FROM public.tickets t
    WHERE t.finished_at IS NOT NULL
      AND t.status = 'finalizado'
      AND t.usuario_atual IS NOT NULL
      AND t.tempo_espera_origem IS NOT NULL
      AND t.finished_at >= v_data_inicio
      AND t.finished_at < v_data_fim
      AND (p_equipe_id IS NULL OR t.gse IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = p_equipe_id))
      AND (NOT v_tem_filtro_atendentes OR t.usuario_atual = ANY(p_atendentes))
  ),
  classificado AS (
    SELECT
      usuario_atual,
      CASE
        WHEN espera_horas < 24 THEN 'ate_24h'
        WHEN espera_horas < 48 THEN '24_48h'
        WHEN espera_horas < 72 THEN '48_72h'
        WHEN espera_horas < 168 THEN '72_168h'
        ELSE 'acima_168h'
      END AS bucket
    FROM filtrado
  ),
  bucket_filtrado AS (
    SELECT usuario_atual
    FROM classificado
    WHERE p_bucket = 'todos' OR bucket = p_bucket
  ),
  por_atendente AS (
    SELECT
      usuario_atual AS usuario_id,
      COUNT(*) AS total
    FROM bucket_filtrado
    GROUP BY usuario_atual
  )
  SELECT
    jsonb_build_object(
      'bucket', p_bucket,
      'periodo', p_periodo,
      'total', COALESCE((SELECT SUM(total) FROM por_atendente), 0),
      'atendentes', COALESCE((
        SELECT jsonb_agg(
          jsonb_build_object(
            'usuario_id', pa.usuario_id,
            'nome', COALESCE(u.nome, u.email, pa.usuario_id::text),
            'total', pa.total,
            'pct', CASE
              WHEN (SELECT SUM(total) FROM por_atendente) > 0
              THEN ROUND((pa.total::numeric / (SELECT SUM(total) FROM por_atendente)) * 100, 1)
              ELSE 0
            END
          ) ORDER BY pa.total DESC
        )
        FROM por_atendente pa
        LEFT JOIN public.users u ON u.id = pa.usuario_id
      ), '[]'::jsonb)
    )
  INTO v_resultado;

  RETURN v_resultado;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.obter_atendentes_por_bucket_espera(TEXT, UUID, TEXT, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_atendentes_por_bucket_espera(TEXT, UUID, TEXT, UUID[]) TO service_role;

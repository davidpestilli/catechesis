-- Elimina fan-out de RPCs no gráfico "Entrada vs Saída" e no modal
-- correspondente, permitindo filtro multi-localização em uma única chamada.
-- Também adiciona um índice funcional para os filtros de saída baseados em
-- COALESCE(data_envio_aceite, data_abertura).

CREATE INDEX IF NOT EXISTS idx_oraculo_chamados_saida_bucket_localizacao
  ON public.oraculo_chamados (
    COALESCE(data_envio_aceite, data_abertura),
    grupo_designado,
    designado_localizacao
  )
  WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado');
CREATE OR REPLACE FUNCTION public.obter_entrada_vs_resposta_oraculo_multi(
  p_dias integer DEFAULT NULL,
  p_localizacoes text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_resultado JSONB;
  v_now_local TIMESTAMP;
  v_data_inicio TIMESTAMP;
  v_data_fim TIMESTAMP;
  v_bucket INTERVAL;
  v_format TEXT;
  v_use_month BOOLEAN := false;
  v_anchor TIMESTAMP := TIMESTAMP '2000-01-01 00:00:00';
  v_named_localizacoes TEXT[];
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_include_it2b BOOLEAN := false;
  v_include_outros BOOLEAN := false;
BEGIN
  v_now_local := (NOW() AT TIME ZONE 'America/Sao_Paulo');

  IF p_dias IS NOT NULL AND p_dias <= 6 THEN
    v_data_fim := date_trunc('hour', v_now_local) + INTERVAL '1 hour';
    v_data_inicio := v_data_fim - (p_dias || ' days')::INTERVAL;
  ELSE
    v_data_fim := date_trunc('day', v_now_local) + INTERVAL '1 day';
    IF p_dias IS NOT NULL THEN
      v_data_inicio := date_trunc('day', v_now_local) - ((p_dias - 1) || ' days')::INTERVAL;
    ELSE
      SELECT date_trunc('month', COALESCE(MIN(c.data_abertura), v_now_local - INTERVAL '30 days'))
        INTO v_data_inicio
        FROM public.oraculo_chamados c;
    END IF;
  END IF;

  IF p_dias = 1 THEN
    v_bucket := INTERVAL '1 hour';   v_format := 'DD/MM HH24"h"';
  ELSIF p_dias = 2 THEN
    v_bucket := INTERVAL '2 hours';  v_format := 'DD/MM HH24"h"';
  ELSIF p_dias = 3 THEN
    v_bucket := INTERVAL '3 hours';  v_format := 'DD/MM HH24"h"';
  ELSIF p_dias IS NOT NULL AND p_dias <= 6 THEN
    v_bucket := INTERVAL '6 hours';  v_format := 'DD/MM HH24"h"';
  ELSIF p_dias IS NOT NULL AND p_dias <= 90 THEN
    v_bucket := INTERVAL '1 day';    v_format := 'DD/MM';
  ELSE
    v_use_month := true;             v_format := 'Mon/YY';
  END IF;

  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM public.gse_equipes ge;

  IF p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) > 0 THEN
    v_include_it2b := 'IT2B' = ANY(p_localizacoes);
    v_include_outros := 'Outros' = ANY(p_localizacoes);

    SELECT ARRAY_AGG(loc)
      INTO v_named_localizacoes
      FROM unnest(p_localizacoes) loc
      WHERE loc IS NOT NULL
        AND loc <> 'IT2B'
        AND loc <> 'Outros';

    IF COALESCE(cardinality(v_named_localizacoes), 0) > 0 THEN
      SELECT ARRAY_AGG(ge.gse)
        INTO v_gses
        FROM public.gse_equipes ge
        JOIN public.equipes e ON ge.equipe_id = e.id
       WHERE e.nome = ANY(v_named_localizacoes);
    END IF;
  END IF;

  WITH filtered AS (
    SELECT c.data_abertura, c.data_envio_aceite, c.status_operacional, c.nome_designado, c.grupo_designado, c.designado_localizacao
    FROM public.oraculo_chamados c
    WHERE (
      p_localizacoes IS NULL
      OR cardinality(p_localizacoes) = 0
      OR (COALESCE(cardinality(v_gses), 0) > 0 AND c.grupo_designado = ANY(v_gses))
      OR (v_include_it2b
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND c.designado_localizacao = 'IT2B')
      OR (v_include_outros
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  totais AS (
    SELECT
      COUNT(*) FILTER (WHERE data_abertura >= v_data_inicio AND data_abertura < v_data_fim) AS entrada_periodo,
      COUNT(*) FILTER (
        WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
          AND COALESCE(data_envio_aceite, data_abertura) >= v_data_inicio
          AND COALESCE(data_envio_aceite, data_abertura) < v_data_fim
      ) AS respondidos_periodo,
      COUNT(DISTINCT nome_designado) FILTER (
        WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
          AND nome_designado IS NOT NULL
          AND COALESCE(data_envio_aceite, data_abertura) >= v_data_inicio
          AND COALESCE(data_envio_aceite, data_abertura) < v_data_fim
      ) AS analistas_ativos_periodo
    FROM filtered
  ),
  bucketed_entrada AS (
    SELECT
      CASE
        WHEN v_use_month THEN date_trunc('month', data_abertura)
        ELSE date_bin(v_bucket, data_abertura, v_anchor)
      END AS bucket,
      COUNT(*)::INT AS entrada
    FROM filtered
    WHERE data_abertura >= v_data_inicio AND data_abertura < v_data_fim
    GROUP BY 1
  ),
  bucketed_saida AS (
    SELECT
      CASE
        WHEN v_use_month THEN date_trunc('month', COALESCE(data_envio_aceite, data_abertura))
        ELSE date_bin(v_bucket, COALESCE(data_envio_aceite, data_abertura), v_anchor)
      END AS bucket,
      COUNT(*)::INT AS resposta,
      COUNT(DISTINCT nome_designado)::INT AS analistas
    FROM filtered
    WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
      AND COALESCE(data_envio_aceite, data_abertura) >= v_data_inicio
      AND COALESCE(data_envio_aceite, data_abertura) < v_data_fim
    GROUP BY 1
  ),
  serie AS (
    SELECT s AS bucket
    FROM generate_series(
      CASE
        WHEN v_use_month THEN date_trunc('month', v_data_inicio)
        ELSE date_bin(v_bucket, v_data_inicio, v_anchor)
      END,
      v_data_fim - INTERVAL '1 microsecond',
      CASE WHEN v_use_month THEN INTERVAL '1 month' ELSE v_bucket END
    ) s
  ),
  analise AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia', to_char(s.bucket, 'YYYY-MM-DD'),
        'dia_fim', to_char(
          CASE
            WHEN v_use_month THEN (s.bucket + INTERVAL '1 month' - INTERVAL '1 day')
            ELSE s.bucket
          END,
          'YYYY-MM-DD'
        ),
        'bucket_inicio', to_char(s.bucket, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'bucket_fim', to_char(
          CASE
            WHEN v_use_month THEN (s.bucket + INTERVAL '1 month')
            ELSE (s.bucket + v_bucket)
          END,
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'periodo', to_char(s.bucket, v_format),
        'entrada', COALESCE(e.entrada, 0),
        'resposta', COALESCE(r.resposta, 0),
        'analistas', COALESCE(r.analistas, 0)
      ) ORDER BY s.bucket
    ) AS dados
    FROM serie s
    LEFT JOIN bucketed_entrada e ON e.bucket = s.bucket
    LEFT JOIN bucketed_saida r ON r.bucket = s.bucket
  ),
  localizacoes_disponiveis AS (
    SELECT jsonb_agg(item ORDER BY item->>'codigo') AS lista
    FROM (
      SELECT jsonb_build_object(
        'codigo', sub.equipe,
        'nome', CASE sub.equipe
          WHEN '2.2.1' THEN '1ª Instância'
          WHEN '2.3.1' THEN '2ª Instância'
          WHEN '2.3.2' THEN 'Externo'
          ELSE sub.equipe
        END,
        'total', sub.total
      ) AS item
      FROM (
        SELECT
          CASE
            WHEN e.nome IS NOT NULL THEN e.nome::text
            WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
            ELSE 'Outros'
          END AS equipe,
          COUNT(*)::INT AS total
        FROM public.oraculo_chamados c
        LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
        LEFT JOIN public.equipes e ON ge.equipe_id = e.id
        WHERE c.data_abertura >= v_data_inicio AND c.data_abertura < v_data_fim
        GROUP BY 1
      ) sub
    ) sub2
  )
  SELECT jsonb_build_object(
    'periodo_dias', p_dias,
    'localizacao', CASE
      WHEN p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) = 1 THEN p_localizacoes[1]
      ELSE NULL
    END,
    'entrada_periodo', COALESCE(t.entrada_periodo, 0),
    'respondidos_periodo', COALESCE(t.respondidos_periodo, 0),
    'saldo_periodo', COALESCE(t.respondidos_periodo, 0) - COALESCE(t.entrada_periodo, 0),
    'analistas_ativos_periodo', COALESCE(t.analistas_ativos_periodo, 0),
    'analise_diaria', COALESCE(a.dados, '[]'::jsonb),
    'localizacoes_disponiveis', COALESCE(ld.lista, '[]'::jsonb)
  )
  INTO v_resultado
  FROM totais t, analise a, localizacoes_disponiveis ld;

  RETURN v_resultado;
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_entrada_vs_resposta_oraculo_range_multi(
  p_data_inicio date,
  p_data_fim date,
  p_localizacoes text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_resultado JSONB;
  v_dias INT;
  v_inicio TIMESTAMP;
  v_fim TIMESTAMP;
  v_bucket INTERVAL;
  v_format TEXT;
  v_use_month BOOLEAN := false;
  v_anchor TIMESTAMP := TIMESTAMP '2000-01-01 00:00:00';
  v_named_localizacoes TEXT[];
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_include_it2b BOOLEAN := false;
  v_include_outros BOOLEAN := false;
BEGIN
  IF p_data_inicio IS NULL OR p_data_fim IS NULL THEN
    RAISE EXCEPTION 'p_data_inicio e p_data_fim são obrigatórios';
  END IF;

  v_dias := (p_data_fim - p_data_inicio) + 1;
  v_inicio := p_data_inicio::timestamp;
  v_fim := (p_data_fim + 1)::timestamp;

  IF v_dias = 1 THEN
    v_bucket := INTERVAL '1 hour';   v_format := 'DD/MM HH24"h"';
  ELSIF v_dias = 2 THEN
    v_bucket := INTERVAL '2 hours';  v_format := 'DD/MM HH24"h"';
  ELSIF v_dias = 3 THEN
    v_bucket := INTERVAL '3 hours';  v_format := 'DD/MM HH24"h"';
  ELSIF v_dias <= 6 THEN
    v_bucket := INTERVAL '6 hours';  v_format := 'DD/MM HH24"h"';
  ELSIF v_dias <= 90 THEN
    v_bucket := INTERVAL '1 day';    v_format := 'DD/MM';
  ELSE
    v_use_month := true;             v_format := 'Mon/YY';
  END IF;

  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM public.gse_equipes ge;

  IF p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) > 0 THEN
    v_include_it2b := 'IT2B' = ANY(p_localizacoes);
    v_include_outros := 'Outros' = ANY(p_localizacoes);

    SELECT ARRAY_AGG(loc)
      INTO v_named_localizacoes
      FROM unnest(p_localizacoes) loc
      WHERE loc IS NOT NULL
        AND loc <> 'IT2B'
        AND loc <> 'Outros';

    IF COALESCE(cardinality(v_named_localizacoes), 0) > 0 THEN
      SELECT ARRAY_AGG(ge.gse)
        INTO v_gses
        FROM public.gse_equipes ge
        JOIN public.equipes e ON ge.equipe_id = e.id
       WHERE e.nome = ANY(v_named_localizacoes);
    END IF;
  END IF;

  WITH filtered AS (
    SELECT c.data_abertura, c.data_envio_aceite, c.status_operacional, c.nome_designado, c.grupo_designado, c.designado_localizacao
    FROM public.oraculo_chamados c
    WHERE (
      p_localizacoes IS NULL
      OR cardinality(p_localizacoes) = 0
      OR (COALESCE(cardinality(v_gses), 0) > 0 AND c.grupo_designado = ANY(v_gses))
      OR (v_include_it2b
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND c.designado_localizacao = 'IT2B')
      OR (v_include_outros
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  totais AS (
    SELECT
      COUNT(*) FILTER (WHERE data_abertura >= v_inicio AND data_abertura < v_fim) AS entrada_periodo,
      COUNT(*) FILTER (
        WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
          AND COALESCE(data_envio_aceite, data_abertura) >= v_inicio
          AND COALESCE(data_envio_aceite, data_abertura) < v_fim
      ) AS respondidos_periodo,
      COUNT(DISTINCT nome_designado) FILTER (
        WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
          AND nome_designado IS NOT NULL
          AND COALESCE(data_envio_aceite, data_abertura) >= v_inicio
          AND COALESCE(data_envio_aceite, data_abertura) < v_fim
      ) AS analistas_ativos_periodo
    FROM filtered
  ),
  bucketed_entrada AS (
    SELECT
      CASE
        WHEN v_use_month THEN date_trunc('month', data_abertura)
        ELSE date_bin(v_bucket, data_abertura, v_anchor)
      END AS bucket,
      COUNT(*)::INT AS entrada
    FROM filtered
    WHERE data_abertura >= v_inicio AND data_abertura < v_fim
    GROUP BY 1
  ),
  bucketed_saida AS (
    SELECT
      CASE
        WHEN v_use_month THEN date_trunc('month', COALESCE(data_envio_aceite, data_abertura))
        ELSE date_bin(v_bucket, COALESCE(data_envio_aceite, data_abertura), v_anchor)
      END AS bucket,
      COUNT(*)::INT AS resposta,
      COUNT(DISTINCT nome_designado)::INT AS analistas
    FROM filtered
    WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
      AND COALESCE(data_envio_aceite, data_abertura) >= v_inicio
      AND COALESCE(data_envio_aceite, data_abertura) < v_fim
    GROUP BY 1
  ),
  serie AS (
    SELECT s AS bucket
    FROM generate_series(
      CASE
        WHEN v_use_month THEN date_trunc('month', v_inicio)
        ELSE date_bin(v_bucket, v_inicio, v_anchor)
      END,
      v_fim - INTERVAL '1 microsecond',
      CASE WHEN v_use_month THEN INTERVAL '1 month' ELSE v_bucket END
    ) s
  ),
  analise AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia', to_char(s.bucket, 'YYYY-MM-DD'),
        'dia_fim', to_char(
          CASE
            WHEN v_use_month THEN (s.bucket + INTERVAL '1 month' - INTERVAL '1 day')
            ELSE s.bucket
          END,
          'YYYY-MM-DD'
        ),
        'bucket_inicio', to_char(s.bucket, 'YYYY-MM-DD"T"HH24:MI:SS'),
        'bucket_fim', to_char(
          CASE
            WHEN v_use_month THEN (s.bucket + INTERVAL '1 month')
            ELSE (s.bucket + v_bucket)
          END,
          'YYYY-MM-DD"T"HH24:MI:SS'
        ),
        'periodo', to_char(s.bucket, v_format),
        'entrada', COALESCE(e.entrada, 0),
        'resposta', COALESCE(r.resposta, 0),
        'analistas', COALESCE(r.analistas, 0)
      ) ORDER BY s.bucket
    ) AS dados
    FROM serie s
    LEFT JOIN bucketed_entrada e ON e.bucket = s.bucket
    LEFT JOIN bucketed_saida r ON r.bucket = s.bucket
  ),
  localizacoes_disponiveis AS (
    SELECT jsonb_agg(item ORDER BY item->>'codigo') AS lista
    FROM (
      SELECT jsonb_build_object(
        'codigo', sub.equipe,
        'nome', CASE sub.equipe
          WHEN '2.2.1' THEN '1ª Instância'
          WHEN '2.3.1' THEN '2ª Instância'
          WHEN '2.3.2' THEN 'Externo'
          ELSE sub.equipe
        END,
        'total', sub.total
      ) AS item
      FROM (
        SELECT
          CASE
            WHEN e.nome IS NOT NULL THEN e.nome::text
            WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
            ELSE 'Outros'
          END AS equipe,
          COUNT(*)::INT AS total
        FROM public.oraculo_chamados c
        LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
        LEFT JOIN public.equipes e ON ge.equipe_id = e.id
        WHERE c.data_abertura >= v_inicio AND c.data_abertura < v_fim
        GROUP BY 1
      ) sub
    ) sub2
  )
  SELECT jsonb_build_object(
    'periodo_dias', v_dias,
    'localizacao', CASE
      WHEN p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) = 1 THEN p_localizacoes[1]
      ELSE NULL
    END,
    'entrada_periodo', COALESCE(t.entrada_periodo, 0),
    'respondidos_periodo', COALESCE(t.respondidos_periodo, 0),
    'saldo_periodo', COALESCE(t.respondidos_periodo, 0) - COALESCE(t.entrada_periodo, 0),
    'analistas_ativos_periodo', COALESCE(t.analistas_ativos_periodo, 0),
    'analise_diaria', COALESCE(a.dados, '[]'::jsonb),
    'localizacoes_disponiveis', COALESCE(ld.lista, '[]'::jsonb)
  )
  INTO v_resultado
  FROM totais t, analise a, localizacoes_disponiveis ld;

  RETURN v_resultado;
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_distribuicao_entrada_saida_por_localizacao_multi(
  p_data_inicio date,
  p_data_fim date DEFAULT NULL::date,
  p_localizacoes text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_resultado JSONB;
  v_inicio TIMESTAMP;
  v_fim TIMESTAMP;
  v_named_localizacoes TEXT[];
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_include_it2b BOOLEAN := false;
  v_include_outros BOOLEAN := false;
BEGIN
  v_inicio := p_data_inicio::timestamp;
  v_fim := (COALESCE(p_data_fim, p_data_inicio) + 1)::timestamp;

  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM public.gse_equipes ge;

  IF p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) > 0 THEN
    v_include_it2b := 'IT2B' = ANY(p_localizacoes);
    v_include_outros := 'Outros' = ANY(p_localizacoes);

    SELECT ARRAY_AGG(loc)
      INTO v_named_localizacoes
      FROM unnest(p_localizacoes) loc
      WHERE loc IS NOT NULL
        AND loc <> 'IT2B'
        AND loc <> 'Outros';

    IF COALESCE(cardinality(v_named_localizacoes), 0) > 0 THEN
      SELECT ARRAY_AGG(ge.gse)
        INTO v_gses
        FROM public.gse_equipes ge
        JOIN public.equipes e ON ge.equipe_id = e.id
       WHERE e.nome = ANY(v_named_localizacoes);
    END IF;
  END IF;

  WITH filtered AS (
    SELECT c.data_abertura, c.data_envio_aceite, c.status_operacional,
           c.nome_designado, c.grupo_designado, c.designado_localizacao,
           e.nome AS equipe_nome
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE (
      p_localizacoes IS NULL
      OR cardinality(p_localizacoes) = 0
      OR (COALESCE(cardinality(v_gses), 0) > 0 AND c.grupo_designado = ANY(v_gses))
      OR (v_include_it2b
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND c.designado_localizacao = 'IT2B')
      OR (v_include_outros
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  entrada AS (
    SELECT
      CASE
        WHEN equipe_nome IS NOT NULL THEN equipe_nome
        WHEN designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS localizacao,
      COUNT(*)::INT AS total
    FROM filtered
    WHERE data_abertura >= v_inicio AND data_abertura < v_fim
    GROUP BY 1
  ),
  saida AS (
    SELECT
      CASE
        WHEN equipe_nome IS NOT NULL THEN equipe_nome
        WHEN designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS localizacao,
      COUNT(*)::INT AS total
    FROM filtered
    WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
      AND COALESCE(data_envio_aceite, data_abertura) >= v_inicio
      AND COALESCE(data_envio_aceite, data_abertura) < v_fim
    GROUP BY 1
  ),
  analistas AS (
    SELECT
      nome_designado AS nome,
      COUNT(*)::INT AS total,
      CASE
        WHEN equipe_nome IS NOT NULL THEN equipe_nome
        WHEN designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS localizacao
    FROM filtered
    WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
      AND nome_designado IS NOT NULL
      AND nome_designado <> ''
      AND COALESCE(data_envio_aceite, data_abertura) >= v_inicio
      AND COALESCE(data_envio_aceite, data_abertura) < v_fim
    GROUP BY nome_designado, 3
  )
  SELECT jsonb_build_object(
    'data_inicio', p_data_inicio::TEXT,
    'data_fim', COALESCE(p_data_fim, p_data_inicio)::TEXT,
    'localizacao', CASE
      WHEN p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) = 1 THEN p_localizacoes[1]
      ELSE NULL
    END,
    'entrada', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('localizacao', en.localizacao, 'total', en.total) ORDER BY en.total DESC) FROM entrada en),
      '[]'::jsonb
    ),
    'saida', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('localizacao', sa.localizacao, 'total', sa.total) ORDER BY sa.total DESC) FROM saida sa),
      '[]'::jsonb
    ),
    'analistas', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('nome', an.nome, 'total', an.total, 'localizacao', an.localizacao) ORDER BY an.total DESC, an.nome ASC) FROM analistas an),
      '[]'::jsonb
    ),
    'total_entrada', COALESCE((SELECT SUM(en.total) FROM entrada en), 0),
    'total_saida', COALESCE((SELECT SUM(sa.total) FROM saida sa), 0),
    'total_analistas', COALESCE((SELECT COUNT(DISTINCT an.nome) FROM analistas an), 0)
  ) INTO v_resultado;

  RETURN v_resultado;
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_distribuicao_entrada_saida_localizacao_intervalo_multi(
  p_inicio timestamp,
  p_fim timestamp,
  p_localizacoes text[] DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_resultado JSONB;
  v_named_localizacoes TEXT[];
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_include_it2b BOOLEAN := false;
  v_include_outros BOOLEAN := false;
BEGIN
  IF p_inicio IS NULL OR p_fim IS NULL OR p_fim <= p_inicio THEN
    RAISE EXCEPTION 'p_inicio e p_fim são obrigatórios e p_fim deve ser > p_inicio';
  END IF;

  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM public.gse_equipes ge;

  IF p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) > 0 THEN
    v_include_it2b := 'IT2B' = ANY(p_localizacoes);
    v_include_outros := 'Outros' = ANY(p_localizacoes);

    SELECT ARRAY_AGG(loc)
      INTO v_named_localizacoes
      FROM unnest(p_localizacoes) loc
      WHERE loc IS NOT NULL
        AND loc <> 'IT2B'
        AND loc <> 'Outros';

    IF COALESCE(cardinality(v_named_localizacoes), 0) > 0 THEN
      SELECT ARRAY_AGG(ge.gse)
        INTO v_gses
        FROM public.gse_equipes ge
        JOIN public.equipes e ON ge.equipe_id = e.id
       WHERE e.nome = ANY(v_named_localizacoes);
    END IF;
  END IF;

  WITH filtered AS (
    SELECT c.data_abertura, c.data_envio_aceite, c.status_operacional,
           c.nome_designado, c.grupo_designado, c.designado_localizacao,
           e.nome AS equipe_nome
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE (
      p_localizacoes IS NULL
      OR cardinality(p_localizacoes) = 0
      OR (COALESCE(cardinality(v_gses), 0) > 0 AND c.grupo_designado = ANY(v_gses))
      OR (v_include_it2b
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND c.designado_localizacao = 'IT2B')
      OR (v_include_outros
          AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses))
          AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  entrada AS (
    SELECT
      CASE
        WHEN equipe_nome IS NOT NULL THEN equipe_nome
        WHEN designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS localizacao,
      COUNT(*)::INT AS total
    FROM filtered
    WHERE data_abertura >= p_inicio AND data_abertura < p_fim
    GROUP BY 1
  ),
  saida AS (
    SELECT
      CASE
        WHEN equipe_nome IS NOT NULL THEN equipe_nome
        WHEN designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS localizacao,
      COUNT(*)::INT AS total
    FROM filtered
    WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
      AND COALESCE(data_envio_aceite, data_abertura) >= p_inicio
      AND COALESCE(data_envio_aceite, data_abertura) < p_fim
    GROUP BY 1
  ),
  analistas AS (
    SELECT
      nome_designado AS nome,
      COUNT(*)::INT AS total,
      CASE
        WHEN equipe_nome IS NOT NULL THEN equipe_nome
        WHEN designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS localizacao
    FROM filtered
    WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
      AND nome_designado IS NOT NULL
      AND nome_designado <> ''
      AND COALESCE(data_envio_aceite, data_abertura) >= p_inicio
      AND COALESCE(data_envio_aceite, data_abertura) < p_fim
    GROUP BY nome_designado, 3
  )
  SELECT jsonb_build_object(
    'inicio', to_char(p_inicio, 'YYYY-MM-DD"T"HH24:MI:SS'),
    'fim', to_char(p_fim, 'YYYY-MM-DD"T"HH24:MI:SS'),
    'localizacao', CASE
      WHEN p_localizacoes IS NOT NULL AND cardinality(p_localizacoes) = 1 THEN p_localizacoes[1]
      ELSE NULL
    END,
    'entrada', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('localizacao', en.localizacao, 'total', en.total) ORDER BY en.total DESC) FROM entrada en),
      '[]'::jsonb
    ),
    'saida', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('localizacao', sa.localizacao, 'total', sa.total) ORDER BY sa.total DESC) FROM saida sa),
      '[]'::jsonb
    ),
    'analistas', COALESCE(
      (SELECT jsonb_agg(jsonb_build_object('nome', an.nome, 'total', an.total, 'localizacao', an.localizacao) ORDER BY an.total DESC, an.nome ASC) FROM analistas an),
      '[]'::jsonb
    ),
    'total_entrada', COALESCE((SELECT SUM(en.total) FROM entrada en), 0),
    'total_saida', COALESCE((SELECT SUM(sa.total) FROM saida sa), 0),
    'total_analistas', COALESCE((SELECT COUNT(DISTINCT an.nome) FROM analistas an), 0)
  ) INTO v_resultado;

  RETURN v_resultado;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.obter_entrada_vs_resposta_oraculo_multi(integer, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_entrada_vs_resposta_oraculo_multi(integer, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.obter_entrada_vs_resposta_oraculo_range_multi(date, date, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_entrada_vs_resposta_oraculo_range_multi(date, date, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.obter_distribuicao_entrada_saida_por_localizacao_multi(date, date, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_distribuicao_entrada_saida_por_localizacao_multi(date, date, text[]) TO service_role;
GRANT EXECUTE ON FUNCTION public.obter_distribuicao_entrada_saida_localizacao_intervalo_multi(timestamp, timestamp, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_distribuicao_entrada_saida_localizacao_intervalo_multi(timestamp, timestamp, text[]) TO service_role;

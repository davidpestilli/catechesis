-- Bucketing dinâmico para Entrada vs Saída do Oráculo
-- Após migração de data_abertura/data_envio_aceite para TIMESTAMP, o GROUP BY por
-- coluna timestamp criava uma linha por hora/segundo no gráfico. Esta migration:
--   1. Bucketiza dinamicamente (hora/2h/3h/6h/dia/mês) baseado em p_dias.
--   2. Usa generate_series para zero-fill (gráfico contínuo).
--   3. Mantém compatibilidade: campo `dia` continua YYYY-MM-DD (data do bucket).
--      Adiciona `dia_fim` para buckets mensais (último dia do mês).

CREATE OR REPLACE FUNCTION public.obter_entrada_vs_resposta_oraculo(
  p_dias integer DEFAULT NULL,
  p_localizacao text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_resultado JSONB;
  v_data_inicio TIMESTAMP;
  v_data_fim TIMESTAMP;
  v_bucket INTERVAL;
  v_format TEXT;
  v_use_month BOOLEAN := false;
  v_anchor TIMESTAMP := TIMESTAMP '2000-01-01 00:00:00';
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_filter_mode TEXT;
BEGIN
  -- Janela temporal
  v_data_fim := date_trunc('day', NOW()) + INTERVAL '1 day';
  IF p_dias IS NOT NULL THEN
    v_data_inicio := date_trunc('day', NOW()) - ((p_dias - 1) || ' days')::INTERVAL;
  ELSE
    SELECT date_trunc('month', COALESCE(MIN(c.data_abertura), NOW() - INTERVAL '30 days'))
      INTO v_data_inicio
      FROM public.oraculo_chamados c;
  END IF;

  -- Granularidade dinâmica baseada na largura do período
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

  -- Filtro de localização (mantido do original)
  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM gse_equipes ge;
  IF p_localizacao IS NOT NULL THEN
    IF p_localizacao = 'IT2B' THEN v_filter_mode := 'it2b';
    ELSIF p_localizacao = 'Outros' THEN v_filter_mode := 'outros';
    ELSE
      v_filter_mode := 'gse';
      SELECT ARRAY_AGG(ge.gse) INTO v_gses
        FROM gse_equipes ge JOIN equipes e ON ge.equipe_id = e.id
        WHERE e.nome = p_localizacao;
    END IF;
  END IF;

  WITH filtered AS (
    SELECT c.data_abertura, c.data_envio_aceite, c.status_operacional, c.nome_designado, c.grupo_designado, c.designado_localizacao
    FROM public.oraculo_chamados c
    WHERE (
      v_filter_mode IS NULL
      OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
      OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
      OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  totais AS (
    SELECT
      COUNT(*) FILTER (WHERE data_abertura >= v_data_inicio AND data_abertura < v_data_fim) AS entrada_periodo,
      COUNT(*) FILTER (WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
                          AND COALESCE(data_envio_aceite, data_abertura) >= v_data_inicio
                          AND COALESCE(data_envio_aceite, data_abertura) < v_data_fim) AS respondidos_periodo,
      COUNT(DISTINCT nome_designado) FILTER (WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
                          AND nome_designado IS NOT NULL
                          AND COALESCE(data_envio_aceite, data_abertura) >= v_data_inicio
                          AND COALESCE(data_envio_aceite, data_abertura) < v_data_fim) AS analistas_ativos_periodo
    FROM filtered
  ),
  bucketed_entrada AS (
    SELECT
      CASE WHEN v_use_month THEN date_trunc('month', data_abertura)
           ELSE date_bin(v_bucket, data_abertura, v_anchor) END AS bucket,
      COUNT(*)::INT AS entrada
    FROM filtered
    WHERE data_abertura >= v_data_inicio AND data_abertura < v_data_fim
    GROUP BY 1
  ),
  bucketed_saida AS (
    SELECT
      CASE WHEN v_use_month THEN date_trunc('month', COALESCE(data_envio_aceite, data_abertura))
           ELSE date_bin(v_bucket, COALESCE(data_envio_aceite, data_abertura), v_anchor) END AS bucket,
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
      CASE WHEN v_use_month THEN date_trunc('month', v_data_inicio)
           ELSE date_bin(v_bucket, v_data_inicio, v_anchor) END,
      v_data_fim - INTERVAL '1 microsecond',
      CASE WHEN v_use_month THEN INTERVAL '1 month' ELSE v_bucket END
    ) s
  ),
  analise AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia', to_char(s.bucket, 'YYYY-MM-DD'),
        'dia_fim', to_char(
          CASE WHEN v_use_month THEN (s.bucket + INTERVAL '1 month' - INTERVAL '1 day')
               ELSE s.bucket END,
          'YYYY-MM-DD'
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
          ELSE sub.equipe END,
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
        LEFT JOIN gse_equipes ge ON c.grupo_designado = ge.gse
        LEFT JOIN equipes e ON ge.equipe_id = e.id
        WHERE c.data_abertura >= v_data_inicio AND c.data_abertura < v_data_fim
        GROUP BY 1
      ) sub
    ) sub2
  )
  SELECT jsonb_build_object(
    'periodo_dias', p_dias,
    'localizacao', p_localizacao,
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
CREATE OR REPLACE FUNCTION public.obter_entrada_vs_resposta_oraculo_range(
  p_data_inicio date,
  p_data_fim date,
  p_localizacao text DEFAULT NULL
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
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_filter_mode TEXT;
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

  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM gse_equipes ge;
  IF p_localizacao IS NOT NULL THEN
    IF p_localizacao = 'IT2B' THEN v_filter_mode := 'it2b';
    ELSIF p_localizacao = 'Outros' THEN v_filter_mode := 'outros';
    ELSE
      v_filter_mode := 'gse';
      SELECT ARRAY_AGG(ge.gse) INTO v_gses
        FROM gse_equipes ge JOIN equipes e ON ge.equipe_id = e.id
        WHERE e.nome = p_localizacao;
    END IF;
  END IF;

  WITH filtered AS (
    SELECT c.data_abertura, c.data_envio_aceite, c.status_operacional, c.nome_designado, c.grupo_designado, c.designado_localizacao
    FROM public.oraculo_chamados c
    WHERE (
      v_filter_mode IS NULL
      OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
      OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
      OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  totais AS (
    SELECT
      COUNT(*) FILTER (WHERE data_abertura >= v_inicio AND data_abertura < v_fim) AS entrada_periodo,
      COUNT(*) FILTER (WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
                          AND COALESCE(data_envio_aceite, data_abertura) >= v_inicio
                          AND COALESCE(data_envio_aceite, data_abertura) < v_fim) AS respondidos_periodo,
      COUNT(DISTINCT nome_designado) FILTER (WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
                          AND nome_designado IS NOT NULL
                          AND COALESCE(data_envio_aceite, data_abertura) >= v_inicio
                          AND COALESCE(data_envio_aceite, data_abertura) < v_fim) AS analistas_ativos_periodo
    FROM filtered
  ),
  bucketed_entrada AS (
    SELECT
      CASE WHEN v_use_month THEN date_trunc('month', data_abertura)
           ELSE date_bin(v_bucket, data_abertura, v_anchor) END AS bucket,
      COUNT(*)::INT AS entrada
    FROM filtered
    WHERE data_abertura >= v_inicio AND data_abertura < v_fim
    GROUP BY 1
  ),
  bucketed_saida AS (
    SELECT
      CASE WHEN v_use_month THEN date_trunc('month', COALESCE(data_envio_aceite, data_abertura))
           ELSE date_bin(v_bucket, COALESCE(data_envio_aceite, data_abertura), v_anchor) END AS bucket,
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
      CASE WHEN v_use_month THEN date_trunc('month', v_inicio)
           ELSE date_bin(v_bucket, v_inicio, v_anchor) END,
      v_fim - INTERVAL '1 microsecond',
      CASE WHEN v_use_month THEN INTERVAL '1 month' ELSE v_bucket END
    ) s
  ),
  analise AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia', to_char(s.bucket, 'YYYY-MM-DD'),
        'dia_fim', to_char(
          CASE WHEN v_use_month THEN (s.bucket + INTERVAL '1 month' - INTERVAL '1 day')
               ELSE s.bucket END,
          'YYYY-MM-DD'
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
          ELSE sub.equipe END,
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
        LEFT JOIN gse_equipes ge ON c.grupo_designado = ge.gse
        LEFT JOIN equipes e ON ge.equipe_id = e.id
        WHERE c.data_abertura >= v_inicio AND c.data_abertura < v_fim
        GROUP BY 1
      ) sub
    ) sub2
  )
  SELECT jsonb_build_object(
    'periodo_dias', v_dias,
    'localizacao', p_localizacao,
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

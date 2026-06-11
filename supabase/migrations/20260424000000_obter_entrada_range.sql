-- ============================================================================
-- Migration: obter_entrada_vs_resposta_oraculo_range
-- Adiciona variante por intervalo arbitrário [p_data_inicio, p_data_fim] da
-- função `obter_entrada_vs_resposta_oraculo`, mantendo o mesmo agrupamento
-- combinado de equipes (1ª Instância / 2ª Instância / Externo / IT2B / Outros)
-- via JOIN em gse_equipes/equipes.
--
-- Também (re)cria a versão original com (INT, TEXT) — sem mudança lógica —
-- para sincronizar bancos locais que não tenham recebido a fix
-- `fix_entrada_saida_it2b_outros.sql`.
-- ============================================================================

-- (1) Versão original (idempotente — produção já possui)
CREATE OR REPLACE FUNCTION public.obter_entrada_vs_resposta_oraculo(
  p_dias INTEGER DEFAULT NULL,
  p_localizacao TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_resultado JSONB;
  v_data_inicio DATE;
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_filter_mode TEXT;
BEGIN
  IF p_dias IS NOT NULL THEN
    v_data_inicio := CURRENT_DATE - (p_dias || ' days')::INTERVAL;
  END IF;

  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM gse_equipes ge;

  IF p_localizacao IS NOT NULL THEN
    IF p_localizacao = 'IT2B' THEN
      v_filter_mode := 'it2b';
    ELSIF p_localizacao = 'Outros' THEN
      v_filter_mode := 'outros';
    ELSE
      v_filter_mode := 'gse';
      SELECT ARRAY_AGG(ge.gse)
      INTO v_gses
      FROM gse_equipes ge
      JOIN equipes e ON ge.equipe_id = e.id
      WHERE e.nome = p_localizacao;
    END IF;
  END IF;

  WITH totais AS (
    SELECT
      COUNT(*) FILTER (
        WHERE (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
      ) AS entrada_periodo,
      COUNT(*) FILTER (
        WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND (v_data_inicio IS NULL OR COALESCE(c.data_envio_aceite, c.data_abertura) >= v_data_inicio)
      ) AS respondidos_periodo,
      COUNT(DISTINCT c.nome_designado) FILTER (
        WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND c.nome_designado IS NOT NULL
        AND (v_data_inicio IS NULL OR COALESCE(c.data_envio_aceite, c.data_abertura) >= v_data_inicio)
      ) AS analistas_ativos_periodo
    FROM public.oraculo_chamados c
    WHERE (
      v_filter_mode IS NULL
      OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
      OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
      OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  analise_diaria AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia', dias_unicos.dia::text,
        'periodo', TO_CHAR(dias_unicos.dia,
          CASE
            WHEN p_dias IS NULL OR p_dias > 90 THEN 'Mon/YY'
            WHEN p_dias > 30 THEN 'DD/Mon'
            ELSE 'DD/MM'
          END
        ),
        'entrada', COALESCE(ent.entrada, 0),
        'resposta', COALESCE(resp.resposta, 0),
        'analistas', COALESCE(an.analistas, 0)
      ) ORDER BY dias_unicos.dia
    ) AS dados
    FROM (
      SELECT DISTINCT d.dia FROM (
        SELECT data_abertura AS dia FROM public.oraculo_chamados c
        WHERE (v_data_inicio IS NULL OR data_abertura >= v_data_inicio)
          AND (
            v_filter_mode IS NULL
            OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
            OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
            OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
          )
        UNION
        SELECT COALESCE(data_envio_aceite, data_abertura) AS dia FROM public.oraculo_chamados c
        WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
          AND (v_data_inicio IS NULL OR COALESCE(data_envio_aceite, data_abertura) >= v_data_inicio)
          AND (
            v_filter_mode IS NULL
            OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
            OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
            OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
          )
      ) d
      WHERE d.dia IS NOT NULL
    ) dias_unicos
    LEFT JOIN (
      SELECT c.data_abertura AS dia, COUNT(*)::INT AS entrada
      FROM public.oraculo_chamados c
      WHERE (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
        AND (
          v_filter_mode IS NULL
          OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
          OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
          OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
        )
      GROUP BY c.data_abertura
    ) ent ON ent.dia = dias_unicos.dia
    LEFT JOIN (
      SELECT COALESCE(c.data_envio_aceite, c.data_abertura) AS dia, COUNT(*)::INT AS resposta
      FROM public.oraculo_chamados c
      WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND (v_data_inicio IS NULL OR COALESCE(c.data_envio_aceite, c.data_abertura) >= v_data_inicio)
        AND (
          v_filter_mode IS NULL
          OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
          OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
          OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
        )
      GROUP BY COALESCE(c.data_envio_aceite, c.data_abertura)
    ) resp ON resp.dia = dias_unicos.dia
    LEFT JOIN (
      SELECT COALESCE(c.data_envio_aceite, c.data_abertura) AS dia, COUNT(DISTINCT c.nome_designado)::INT AS analistas
      FROM public.oraculo_chamados c
      WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND c.nome_designado IS NOT NULL
        AND (v_data_inicio IS NULL OR COALESCE(c.data_envio_aceite, c.data_abertura) >= v_data_inicio)
        AND (
          v_filter_mode IS NULL
          OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
          OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
          OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
        )
      GROUP BY COALESCE(c.data_envio_aceite, c.data_abertura)
    ) an ON an.dia = dias_unicos.dia
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
        LEFT JOIN gse_equipes ge ON c.grupo_designado = ge.gse
        LEFT JOIN equipes e ON ge.equipe_id = e.id
        WHERE (v_data_inicio IS NULL OR c.data_abertura >= v_data_inicio)
        GROUP BY
          CASE
            WHEN e.nome IS NOT NULL THEN e.nome::text
            WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
            ELSE 'Outros'
          END
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
    'analise_diaria', COALESCE(ad.dados, '[]'::jsonb),
    'localizacoes_disponiveis', COALESCE(ld.lista, '[]'::jsonb)
  )
  INTO v_resultado
  FROM totais t, analise_diaria ad, localizacoes_disponiveis ld;

  RETURN v_resultado;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.obter_entrada_vs_resposta_oraculo(INTEGER, TEXT) TO authenticated;
-- (2) Variante por intervalo arbitrário
CREATE OR REPLACE FUNCTION public.obter_entrada_vs_resposta_oraculo_range(
  p_data_inicio DATE,
  p_data_fim DATE,
  p_localizacao TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_resultado JSONB;
  v_dias INT;
  v_gses TEXT[];
  v_all_mapped_gses TEXT[];
  v_filter_mode TEXT;
BEGIN
  IF p_data_inicio IS NULL OR p_data_fim IS NULL THEN
    RAISE EXCEPTION 'p_data_inicio e p_data_fim são obrigatórios';
  END IF;

  v_dias := (p_data_fim - p_data_inicio) + 1;

  SELECT ARRAY_AGG(ge.gse) INTO v_all_mapped_gses FROM gse_equipes ge;

  IF p_localizacao IS NOT NULL THEN
    IF p_localizacao = 'IT2B' THEN
      v_filter_mode := 'it2b';
    ELSIF p_localizacao = 'Outros' THEN
      v_filter_mode := 'outros';
    ELSE
      v_filter_mode := 'gse';
      SELECT ARRAY_AGG(ge.gse)
      INTO v_gses
      FROM gse_equipes ge
      JOIN equipes e ON ge.equipe_id = e.id
      WHERE e.nome = p_localizacao;
    END IF;
  END IF;

  WITH totais AS (
    SELECT
      COUNT(*) FILTER (
        WHERE c.data_abertura BETWEEN p_data_inicio AND p_data_fim
      ) AS entrada_periodo,
      COUNT(*) FILTER (
        WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND COALESCE(c.data_envio_aceite, c.data_abertura) BETWEEN p_data_inicio AND p_data_fim
      ) AS respondidos_periodo,
      COUNT(DISTINCT c.nome_designado) FILTER (
        WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND c.nome_designado IS NOT NULL
        AND COALESCE(c.data_envio_aceite, c.data_abertura) BETWEEN p_data_inicio AND p_data_fim
      ) AS analistas_ativos_periodo
    FROM public.oraculo_chamados c
    WHERE (
      v_filter_mode IS NULL
      OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
      OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
      OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
    )
  ),
  analise_diaria AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia', dias_unicos.dia::text,
        'periodo', TO_CHAR(dias_unicos.dia,
          CASE
            WHEN v_dias > 90 THEN 'Mon/YY'
            WHEN v_dias > 30 THEN 'DD/Mon'
            ELSE 'DD/MM'
          END
        ),
        'entrada', COALESCE(ent.entrada, 0),
        'resposta', COALESCE(resp.resposta, 0),
        'analistas', COALESCE(an.analistas, 0)
      ) ORDER BY dias_unicos.dia
    ) AS dados
    FROM (
      SELECT DISTINCT d.dia FROM (
        SELECT data_abertura AS dia FROM public.oraculo_chamados c
        WHERE data_abertura BETWEEN p_data_inicio AND p_data_fim
          AND (
            v_filter_mode IS NULL
            OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
            OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
            OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
          )
        UNION
        SELECT COALESCE(data_envio_aceite, data_abertura) AS dia FROM public.oraculo_chamados c
        WHERE (data_envio_aceite IS NOT NULL OR status_operacional = 'Fechado')
          AND COALESCE(data_envio_aceite, data_abertura) BETWEEN p_data_inicio AND p_data_fim
          AND (
            v_filter_mode IS NULL
            OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
            OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
            OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
          )
      ) d
      WHERE d.dia IS NOT NULL
    ) dias_unicos
    LEFT JOIN (
      SELECT c.data_abertura AS dia, COUNT(*)::INT AS entrada
      FROM public.oraculo_chamados c
      WHERE c.data_abertura BETWEEN p_data_inicio AND p_data_fim
        AND (
          v_filter_mode IS NULL
          OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
          OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
          OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
        )
      GROUP BY c.data_abertura
    ) ent ON ent.dia = dias_unicos.dia
    LEFT JOIN (
      SELECT COALESCE(c.data_envio_aceite, c.data_abertura) AS dia, COUNT(*)::INT AS resposta
      FROM public.oraculo_chamados c
      WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND COALESCE(c.data_envio_aceite, c.data_abertura) BETWEEN p_data_inicio AND p_data_fim
        AND (
          v_filter_mode IS NULL
          OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
          OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
          OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
        )
      GROUP BY COALESCE(c.data_envio_aceite, c.data_abertura)
    ) resp ON resp.dia = dias_unicos.dia
    LEFT JOIN (
      SELECT COALESCE(c.data_envio_aceite, c.data_abertura) AS dia, COUNT(DISTINCT c.nome_designado)::INT AS analistas
      FROM public.oraculo_chamados c
      WHERE (c.data_envio_aceite IS NOT NULL OR c.status_operacional = 'Fechado')
        AND c.nome_designado IS NOT NULL
        AND COALESCE(c.data_envio_aceite, c.data_abertura) BETWEEN p_data_inicio AND p_data_fim
        AND (
          v_filter_mode IS NULL
          OR (v_filter_mode = 'gse' AND c.grupo_designado = ANY(v_gses))
          OR (v_filter_mode = 'it2b' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND c.designado_localizacao = 'IT2B')
          OR (v_filter_mode = 'outros' AND (v_all_mapped_gses IS NULL OR c.grupo_designado != ALL(v_all_mapped_gses)) AND (c.designado_localizacao IS NULL OR c.designado_localizacao != 'IT2B'))
        )
      GROUP BY COALESCE(c.data_envio_aceite, c.data_abertura)
    ) an ON an.dia = dias_unicos.dia
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
        LEFT JOIN gse_equipes ge ON c.grupo_designado = ge.gse
        LEFT JOIN equipes e ON ge.equipe_id = e.id
        WHERE c.data_abertura BETWEEN p_data_inicio AND p_data_fim
        GROUP BY
          CASE
            WHEN e.nome IS NOT NULL THEN e.nome::text
            WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
            ELSE 'Outros'
          END
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
    'analise_diaria', COALESCE(ad.dados, '[]'::jsonb),
    'localizacoes_disponiveis', COALESCE(ld.lista, '[]'::jsonb)
  )
  INTO v_resultado
  FROM totais t, analise_diaria ad, localizacoes_disponiveis ld;

  RETURN v_resultado;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.obter_entrada_vs_resposta_oraculo_range(DATE, DATE, TEXT) TO authenticated;
COMMENT ON FUNCTION public.obter_entrada_vs_resposta_oraculo_range(DATE, DATE, TEXT) IS
  'Variante de obter_entrada_vs_resposta_oraculo que aceita intervalo arbitrário [p_data_inicio, p_data_fim]. Mantém o agrupamento combinado de equipes (1ª Instância, 2ª Instância, Externo, IT2B, Outros) via gse_equipes/equipes.';

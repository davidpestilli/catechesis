-- =====================================================================
-- Migration: recategoriza rejeites e chamados antigos como unidades
-- Data: 2026-05-17
--
-- Objetivos:
--   1. Manter os tipos analise_rejeites e analise_chamados_antigos.
--   2. Atualizar as estatisticas completas para contabiliza-los em unidades.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.obter_servicos_estatisticas_completas(
  p_equipe_id UUID,
  p_periodo   TEXT DEFAULT '30d'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_data_inicio TIMESTAMPTZ;
  v_resultado   JSONB;
BEGIN
  v_data_inicio := CASE p_periodo
    WHEN '24h' THEN NOW() - INTERVAL '24 hours'
    WHEN '48h' THEN NOW() - INTERVAL '48 hours'
    WHEN '72h' THEN NOW() - INTERVAL '72 hours'
    WHEN '7d'  THEN NOW() - INTERVAL '7 days'
    WHEN '30d' THEN NOW() - INTERVAL '30 days'
    WHEN 'all' THEN NULL
    ELSE             NOW() - INTERVAL '30 days'
  END;

  WITH filtrado AS (
    SELECT *
    FROM public.servicos
    WHERE equipe_id = p_equipe_id
      AND (v_data_inicio IS NULL OR data_execucao >= v_data_inicio)
  ),

  kpis AS (
    SELECT jsonb_build_object(
      'total_registros', COUNT(*),
      'total_horas', COALESCE(SUM(quantidade) FILTER (
        WHERE tipo IN ('homologacao','reuniao_interna','reuniao_externa','ouvidoria','cpa','dev_aplicacao',
                        'resp_chamado_complexo','criacao_apresentacao',
                        'elaboracao_relatorio','agendamento_visitas',
                        'visitas_virtuais','visitas_presenciais','estudos_atualizacao')
      ), 0),
      'total_unidades', COALESCE(SUM(quantidade) FILTER (
        WHERE tipo IN ('email','chamado_smax','criacao_script',
                        'atendimento_teams','atendimento_balcao',
                        'analise_rejeites','analise_chamados_antigos',
                        'configuracao_sistema','lotacao_usuarios',
                        'cadastro_radar','cadastro_melhoria')
      ), 0),
      'primeiro_registro', MIN(data_execucao),
      'ultimo_registro', MAX(data_execucao),
      'membros_distintos', COUNT(DISTINCT usuario_id)
    ) AS val FROM filtrado
  ),

  por_tipo AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'tipo', tipo,
        'total_qtd', total_qtd,
        'total_regs', total_regs
      )
      ORDER BY total_qtd DESC
    ) AS val
    FROM (
      SELECT tipo,
             SUM(quantidade)::INTEGER AS total_qtd,
             COUNT(*)::INTEGER AS total_regs
      FROM filtrado
      GROUP BY tipo
    ) sub
  ),

  por_membro AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'usuario_id', usuario_id,
        'usuario_nome', usuario_nome,
        'total_qtd', total_qtd,
        'total_regs', total_regs,
        'tipos_distintos', tipos_distintos
      )
      ORDER BY total_qtd DESC
    ) AS val
    FROM (
      SELECT usuario_id,
             usuario_nome,
             SUM(quantidade)::INTEGER AS total_qtd,
             COUNT(*)::INTEGER AS total_regs,
             COUNT(DISTINCT tipo)::INTEGER AS tipos_distintos
      FROM filtrado
      GROUP BY usuario_id, usuario_nome
    ) sub
  ),

  por_dia_semana AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia_semana', dia,
        'dia_label', CASE dia
          WHEN 0 THEN 'Dom' WHEN 1 THEN 'Seg' WHEN 2 THEN 'Ter'
          WHEN 3 THEN 'Qua' WHEN 4 THEN 'Qui' WHEN 5 THEN 'Sex'
          WHEN 6 THEN 'Sáb'
        END,
        'total_qtd', total_qtd,
        'total_regs', total_regs
      )
      ORDER BY dia
    ) AS val
    FROM (
      SELECT EXTRACT(DOW FROM data_execucao AT TIME ZONE 'America/Sao_Paulo')::INTEGER AS dia,
             SUM(quantidade)::INTEGER AS total_qtd,
             COUNT(*)::INTEGER AS total_regs
      FROM filtrado
      GROUP BY dia
    ) sub
  ),

  por_faixa_horaria AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'dia_semana', dia,
        'faixa', faixa,
        'faixa_label', CASE faixa
          WHEN 0 THEN 'Madrugada (0h-6h)'
          WHEN 1 THEN 'Manhã (6h-12h)'
          WHEN 2 THEN 'Tarde (12h-18h)'
          WHEN 3 THEN 'Noite (18h-24h)'
        END,
        'total_qtd', total_qtd
      )
      ORDER BY dia, faixa
    ) AS val
    FROM (
      SELECT
        EXTRACT(DOW FROM data_execucao AT TIME ZONE 'America/Sao_Paulo')::INTEGER AS dia,
        (EXTRACT(HOUR FROM data_execucao AT TIME ZONE 'America/Sao_Paulo')::INTEGER / 6) AS faixa,
        SUM(quantidade)::INTEGER AS total_qtd
      FROM filtrado
      GROUP BY dia, faixa
    ) sub
  ),

  serie_temporal AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'periodo', periodo_key,
        'tipo', tipo,
        'usuario_id', usuario_id,
        'usuario_nome', usuario_nome,
        'total_quantidade', total_quantidade
      )
      ORDER BY periodo_key, usuario_nome
    ) AS val
    FROM (
      SELECT
        CASE
          WHEN p_periodo IN ('24h', '48h', '72h') THEN
            TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24"h"')
          ELSE
            TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM')
        END AS periodo_key,
        tipo,
        usuario_id,
        usuario_nome,
        SUM(quantidade)::INTEGER AS total_quantidade
      FROM filtrado
      GROUP BY periodo_key, tipo, usuario_id, usuario_nome
    ) sub
  ),

  volume_diario AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'data', dia,
        'total_qtd', total_qtd,
        'total_regs', total_regs
      )
      ORDER BY dia
    ) AS val
    FROM (
      SELECT
        TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD') AS dia,
        SUM(quantidade)::INTEGER AS total_qtd,
        COUNT(*)::INTEGER AS total_regs
      FROM filtrado
      GROUP BY dia
    ) sub
  )

  SELECT jsonb_build_object(
    'sucesso', true,
    'periodo', p_periodo,
    'kpis', (SELECT val FROM kpis),
    'por_tipo', COALESCE((SELECT val FROM por_tipo), '[]'::jsonb),
    'por_membro', COALESCE((SELECT val FROM por_membro), '[]'::jsonb),
    'por_dia_semana', COALESCE((SELECT val FROM por_dia_semana), '[]'::jsonb),
    'por_faixa_horaria', COALESCE((SELECT val FROM por_faixa_horaria), '[]'::jsonb),
    'serie_temporal', COALESCE((SELECT val FROM serie_temporal), '[]'::jsonb),
    'volume_diario', COALESCE((SELECT val FROM volume_diario), '[]'::jsonb)
  )
  INTO v_resultado;

  RETURN v_resultado;

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Erro ao obter estatísticas completas de serviços: ' || SQLERRM
    );
END;
$$;
GRANT EXECUTE ON FUNCTION public.obter_servicos_estatisticas_completas(UUID, TEXT) TO authenticated;

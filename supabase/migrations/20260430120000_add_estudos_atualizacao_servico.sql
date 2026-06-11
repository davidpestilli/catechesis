-- ============================================================
-- Migração: Adicionar tipo de serviço "Estudos/Atualização"
-- Data: 2026-04-30
-- Descrição:
--   Adiciona o novo tipo `estudos_atualizacao` ao sistema de
--   Outros Serviços. Unidade de medida: horas (arredondar p/ cima).
--
--   Atualiza:
--     1. CHECK constraint `servicos_tipo_check`
--     2. Função `criar_servico`        (lista interna de tipos)
--     3. Função `atualizar_servico`    (lista interna de tipos)
--     4. Função `obter_servicos_estatisticas_completas`
--        — categoriza `estudos_atualizacao` em `total_horas`.
--
--   Idempotente: também garante a presença dos 4 tipos da Fase 3
--   (configuracao_sistema, lotacao_usuarios, cadastro_radar,
--    cadastro_melhoria) caso o ambiente esteja desatualizado.
-- ============================================================

-- ── 1. Atualizar CHECK constraint ──────────────────────────

ALTER TABLE servicos DROP CONSTRAINT IF EXISTS servicos_tipo_check;
ALTER TABLE servicos ADD CONSTRAINT servicos_tipo_check CHECK (tipo IN (
  'email',
  'homologacao',
  'ouvidoria',
  'cpa',
  'chamado_smax',
  'criacao_script',
  'agendamento_visitas',
  'visitas_virtuais',
  'visitas_presenciais',
  'atendimento_teams',
  'atendimento_balcao',
  'dev_aplicacao',
  'resp_chamado_complexo',
  'criacao_apresentacao',
  'configuracao_sistema',
  'lotacao_usuarios',
  'cadastro_radar',
  'cadastro_melhoria',
  'estudos_atualizacao'
));
COMMENT ON COLUMN servicos.tipo IS
  'Tipo: email, homologacao, ouvidoria, cpa, chamado_smax, criacao_script, '
  'agendamento_visitas, visitas_virtuais, visitas_presenciais, '
  'atendimento_teams, atendimento_balcao, dev_aplicacao, resp_chamado_complexo, '
  'criacao_apresentacao, configuracao_sistema, lotacao_usuarios, cadastro_radar, '
  'cadastro_melhoria, estudos_atualizacao';
-- ── 2. Atualizar criar_servico ─────────────────────────────

CREATE OR REPLACE FUNCTION criar_servico(
  p_tipo          TEXT,
  p_quantidade    INTEGER,
  p_usuario_id    UUID,
  p_equipe_id     UUID,
  p_observacao    TEXT        DEFAULT NULL,
  p_data_execucao TIMESTAMPTZ DEFAULT NULL,
  p_descricao     TEXT        DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_servico_id   UUID;
  v_usuario_nome TEXT;
  v_data_exec    TIMESTAMPTZ;
BEGIN
  -- Validar tipo
  IF p_tipo NOT IN (
    'email','homologacao','ouvidoria','cpa','chamado_smax','criacao_script',
    'agendamento_visitas','visitas_virtuais','visitas_presenciais',
    'atendimento_teams','atendimento_balcao','dev_aplicacao','resp_chamado_complexo','criacao_apresentacao',
    'configuracao_sistema','lotacao_usuarios','cadastro_radar','cadastro_melhoria',
    'estudos_atualizacao'
  ) THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de serviço inválido.');
  END IF;

  -- Validar quantidade
  IF p_quantidade IS NULL OR p_quantidade < 1 THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Quantidade deve ser um número inteiro maior ou igual a 1');
  END IF;

  -- Validar equipe
  IF p_equipe_id IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Equipe é obrigatória');
  END IF;

  -- Validar data de execução (não pode ser futura)
  v_data_exec := COALESCE(p_data_execucao, NOW());
  IF v_data_exec > NOW() + INTERVAL '1 minute' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'A data de execução não pode ser no futuro');
  END IF;

  -- Buscar nome do usuário
  SELECT COALESCE(nome, email, 'Usuário') INTO v_usuario_nome
  FROM public.users
  WHERE id = p_usuario_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário não encontrado');
  END IF;

  -- Inserir registro
  INSERT INTO servicos (tipo, quantidade, usuario_id, usuario_nome, equipe_id, observacao, data_execucao, descricao)
  VALUES (p_tipo, p_quantidade, p_usuario_id, v_usuario_nome, p_equipe_id, p_observacao, v_data_exec, p_descricao)
  RETURNING id INTO v_servico_id;

  RETURN jsonb_build_object(
    'sucesso',     true,
    'servico_id',  v_servico_id,
    'mensagem',    'Serviço registrado com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados inválidos: verifique tipo e quantidade.');
  WHEN foreign_key_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário ou equipe não encontrados.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao registrar serviço. Tente novamente.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- ── 3. Atualizar atualizar_servico ─────────────────────────

CREATE OR REPLACE FUNCTION atualizar_servico(
  p_servico_id    UUID,
  p_tipo          TEXT        DEFAULT NULL,
  p_quantidade    INTEGER     DEFAULT NULL,
  p_observacao    TEXT        DEFAULT NULL,
  p_data_execucao TIMESTAMPTZ DEFAULT NULL,
  p_descricao     TEXT        DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_user_id    UUID := auth.uid();
  v_user_role  TEXT;
  v_servico    RECORD;
  v_alteracoes JSONB := '{}';
BEGIN
  -- Buscar registro
  SELECT * INTO v_servico FROM servicos WHERE id = p_servico_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Serviço não encontrado');
  END IF;

  -- Verificar permissão
  SELECT role INTO v_user_role FROM public.users WHERE id = v_user_id;

  IF v_servico.usuario_id != v_user_id AND COALESCE(v_user_role, 'user') != 'admin' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsável ou administrador pode editar o serviço');
  END IF;

  -- Atualizar tipo se fornecido
  IF p_tipo IS NOT NULL AND p_tipo != v_servico.tipo THEN
    IF p_tipo NOT IN (
      'email','homologacao','ouvidoria','cpa','chamado_smax','criacao_script',
      'agendamento_visitas','visitas_virtuais','visitas_presenciais',
      'atendimento_teams','atendimento_balcao','dev_aplicacao','resp_chamado_complexo','criacao_apresentacao',
      'configuracao_sistema','lotacao_usuarios','cadastro_radar','cadastro_melhoria',
      'estudos_atualizacao'
    ) THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de serviço inválido');
    END IF;
    UPDATE servicos SET tipo = p_tipo, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('tipo', true);
  END IF;

  -- Atualizar quantidade se fornecida
  IF p_quantidade IS NOT NULL AND p_quantidade != v_servico.quantidade THEN
    IF p_quantidade < 1 THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'Quantidade deve ser um número inteiro maior ou igual a 1');
    END IF;
    UPDATE servicos SET quantidade = p_quantidade, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('quantidade', true);
  END IF;

  -- Atualizar observação se fornecida
  IF p_observacao IS NOT NULL AND COALESCE(p_observacao, '') != COALESCE(v_servico.observacao, '') THEN
    UPDATE servicos SET observacao = p_observacao, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('observacao', true);
  END IF;

  -- Atualizar data_execucao se fornecida
  IF p_data_execucao IS NOT NULL AND p_data_execucao != v_servico.data_execucao THEN
    IF p_data_execucao > NOW() + INTERVAL '1 minute' THEN
      RETURN jsonb_build_object('sucesso', false, 'erro', 'A data de execução não pode ser no futuro');
    END IF;
    UPDATE servicos SET data_execucao = p_data_execucao, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('data_execucao', true);
  END IF;

  -- Atualizar descricao se fornecida
  IF p_descricao IS NOT NULL AND COALESCE(p_descricao, '') != COALESCE(v_servico.descricao, '') THEN
    UPDATE servicos SET descricao = p_descricao, atualizado_em = NOW() WHERE id = p_servico_id;
    v_alteracoes := v_alteracoes || jsonb_build_object('descricao', true);
  END IF;

  RETURN jsonb_build_object(
    'sucesso',    true,
    'alteracoes', v_alteracoes,
    'mensagem',   'Serviço atualizado com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados inválidos: verifique tipo e quantidade.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao atualizar serviço. Tente novamente.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- ── 4. Atualizar obter_servicos_estatisticas_completas ─────
--    (categoriza estudos_atualizacao como horas)

CREATE OR REPLACE FUNCTION obter_servicos_estatisticas_completas(
  p_equipe_id UUID,
  p_periodo   TEXT DEFAULT '30d'
)
RETURNS JSONB AS $$
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
    FROM servicos
    WHERE equipe_id = p_equipe_id
      AND (v_data_inicio IS NULL OR data_execucao >= v_data_inicio)
  ),

  kpis AS (
    SELECT jsonb_build_object(
      'total_registros',     COUNT(*),
      'total_horas',         COALESCE(SUM(quantidade) FILTER (
        WHERE tipo IN ('homologacao','ouvidoria','cpa','dev_aplicacao',
                        'resp_chamado_complexo','criacao_apresentacao',
                        'agendamento_visitas','visitas_virtuais','visitas_presenciais',
                        'estudos_atualizacao')
      ), 0),
      'total_unidades',      COALESCE(SUM(quantidade) FILTER (
        WHERE tipo IN ('email','chamado_smax','criacao_script',
                        'atendimento_teams','atendimento_balcao',
                        'configuracao_sistema','lotacao_usuarios',
                        'cadastro_radar','cadastro_melhoria')
      ), 0),
      'primeiro_registro',   MIN(data_execucao),
      'ultimo_registro',     MAX(data_execucao),
      'membros_distintos',   COUNT(DISTINCT usuario_id)
    ) AS val FROM filtrado
  ),

  por_tipo AS (
    SELECT jsonb_agg(
      jsonb_build_object(
        'tipo',       tipo,
        'total_qtd',  total_qtd,
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
        'usuario_id',      usuario_id,
        'usuario_nome',    usuario_nome,
        'total_qtd',       total_qtd,
        'total_regs',      total_regs,
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
        'dia_label',  CASE dia
          WHEN 0 THEN 'Dom' WHEN 1 THEN 'Seg' WHEN 2 THEN 'Ter'
          WHEN 3 THEN 'Qua' WHEN 4 THEN 'Qui' WHEN 5 THEN 'Sex'
          WHEN 6 THEN 'Sáb'
        END,
        'total_qtd',  total_qtd,
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
        'dia_semana',    dia,
        'faixa',         faixa,
        'faixa_label',   CASE faixa
          WHEN 0 THEN 'Madrugada (0h-6h)'
          WHEN 1 THEN 'Manhã (6h-12h)'
          WHEN 2 THEN 'Tarde (12h-18h)'
          WHEN 3 THEN 'Noite (18h-24h)'
        END,
        'total_qtd',     total_qtd
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
        'periodo',          periodo_key,
        'tipo',             tipo,
        'usuario_id',       usuario_id,
        'usuario_nome',     usuario_nome,
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
        'data',       dia,
        'total_qtd',  total_qtd,
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
    'sucesso',           true,
    'periodo',           p_periodo,
    'kpis',              (SELECT val FROM kpis),
    'por_tipo',          COALESCE((SELECT val FROM por_tipo), '[]'::jsonb),
    'por_membro',        COALESCE((SELECT val FROM por_membro), '[]'::jsonb),
    'por_dia_semana',    COALESCE((SELECT val FROM por_dia_semana), '[]'::jsonb),
    'por_faixa_horaria', COALESCE((SELECT val FROM por_faixa_horaria), '[]'::jsonb),
    'serie_temporal',    COALESCE((SELECT val FROM serie_temporal), '[]'::jsonb),
    'volume_diario',     COALESCE((SELECT val FROM volume_diario), '[]'::jsonb)
  )
  INTO v_resultado;

  RETURN v_resultado;

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro',    'Erro ao obter estatísticas completas de serviços: ' || SQLERRM
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION obter_servicos_estatisticas_completas TO authenticated;
GRANT EXECUTE ON FUNCTION criar_servico(text, integer, uuid, uuid, text, timestamptz, text) TO authenticated;
GRANT EXECUTE ON FUNCTION atualizar_servico(uuid, text, integer, text, timestamptz, text) TO authenticated;

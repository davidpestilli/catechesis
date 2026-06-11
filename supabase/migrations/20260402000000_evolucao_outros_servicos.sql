-- ============================================================
-- Migração: Evolução do Sistema de Outros Serviços
-- Data: 2026-04-02
-- Descrição:
--   1. Novos tipos de serviço: atendimento_teams, atendimento_balcao,
--      dev_aplicacao, resp_chamado_complexo, criacao_apresentacao
--   2. Alterar unidade de agendamento_visitas de 'unidades' para 'horas' (somente frontend)
--   3. Remover subtipos de 'desenvolvimento' do select (Aplicação, Chamado Complexo, Apresentação)
--      — São migrados para tipos standalone
--   4. Coluna 'descricao' para conteúdo rico (HTML) substituindo 'observacao' no UI
--   5. Corrigir obter_servicos_estatisticas para usar data_execucao em vez de criado_em
-- ============================================================

-- ============================================================
-- 1. ATUALIZAR CHECK CONSTRAINT DA TABELA
--    Adicionar novos tipos: atendimento_teams, atendimento_balcao,
--    dev_aplicacao, resp_chamado_complexo, criacao_apresentacao
-- ============================================================

ALTER TABLE servicos DROP CONSTRAINT IF EXISTS servicos_tipo_check;
ALTER TABLE servicos ADD CONSTRAINT servicos_tipo_check CHECK (tipo IN (
  'email',
  'homologacao',
  'ouvidoria',
  'cpa',
  'chamado_smax',
  'criacao_script',
  'desenvolvimento',
  'agendamento_visitas',
  'visitas_virtuais',
  'visitas_presenciais',
  'atendimento_teams',
  'atendimento_balcao',
  'dev_aplicacao',
  'resp_chamado_complexo',
  'criacao_apresentacao'
));
-- Atualizar comentários
COMMENT ON COLUMN servicos.tipo IS 'Tipo: email, homologacao, ouvidoria, cpa, chamado_smax, criacao_script, desenvolvimento, agendamento_visitas, visitas_virtuais, visitas_presenciais, atendimento_teams, atendimento_balcao, dev_aplicacao, resp_chamado_complexo, criacao_apresentacao';
-- ============================================================
-- 2. ADICIONAR COLUNA descricao (HTML rico)
-- ============================================================

ALTER TABLE servicos ADD COLUMN IF NOT EXISTS descricao TEXT;
COMMENT ON COLUMN servicos.descricao IS 'Descrição em HTML (editor rico). Substitui observacao para conteúdos formatados com texto rico e imagens.';
-- ============================================================
-- 3. MIGRAÇÃO DE DADOS
--    Converter registros com tipo='desenvolvimento' e observacao=subtipo
--    para os novos tipos standalone.
--    Mapeamento:
--      observacao='aplicacao'        → tipo='dev_aplicacao'
--      observacao='chamado_complexo' → tipo='resp_chamado_complexo'
--      observacao='apresentacao'     → tipo='criacao_apresentacao'
-- ============================================================

-- Migrar 'aplicacao' → 'dev_aplicacao'
UPDATE servicos
SET tipo = 'dev_aplicacao',
    observacao = NULL,
    atualizado_em = NOW()
WHERE tipo = 'desenvolvimento'
  AND observacao = 'aplicacao';
-- Migrar 'chamado_complexo' → 'resp_chamado_complexo'
UPDATE servicos
SET tipo = 'resp_chamado_complexo',
    observacao = NULL,
    atualizado_em = NOW()
WHERE tipo = 'desenvolvimento'
  AND observacao = 'chamado_complexo';
-- Migrar 'apresentacao' → 'criacao_apresentacao'
UPDATE servicos
SET tipo = 'criacao_apresentacao',
    observacao = NULL,
    atualizado_em = NOW()
WHERE tipo = 'desenvolvimento'
  AND observacao = 'apresentacao';
-- Verificar se restaram registros 'desenvolvimento' sem migrar
-- (registros com observacao diferente dos subtipos conhecidos ficam intactos)
DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count
  FROM servicos
  WHERE tipo = 'desenvolvimento';

  IF v_count > 0 THEN
    RAISE NOTICE 'AVISO: % registros com tipo=desenvolvimento ainda existem (sem subtipo mapeado).', v_count;
  ELSE
    RAISE NOTICE 'OK: Todos os registros de desenvolvimento foram migrados com sucesso.';
  END IF;
END $$;
-- ============================================================
-- 4. ATUALIZAR LISTA DE TIPOS NA VALIDAÇÃO DAS RPCs
-- ============================================================

-- Lista completa de tipos válidos (constante para uso nas funções)
-- 'email','homologacao','ouvidoria','cpa','chamado_smax','criacao_script',
-- 'desenvolvimento','agendamento_visitas','visitas_virtuais','visitas_presenciais',
-- 'atendimento_teams','atendimento_balcao','dev_aplicacao','resp_chamado_complexo','criacao_apresentacao'

-- ============================================================
-- 4.0 DROPAR OVERLOADS ANTIGOS (evitar ambiguidade)
-- ============================================================

DROP FUNCTION IF EXISTS criar_servico(text, integer, uuid, uuid, text);
DROP FUNCTION IF EXISTS criar_servico(text, integer, uuid, uuid, text, timestamptz);
DROP FUNCTION IF EXISTS atualizar_servico(uuid, text, integer, text);
DROP FUNCTION IF EXISTS atualizar_servico(uuid, text, integer, text, timestamptz);
-- ============================================================
-- 4.1 ATUALIZAR FUNÇÃO criar_servico
-- ============================================================

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
    'desenvolvimento','agendamento_visitas','visitas_virtuais','visitas_presenciais',
    'atendimento_teams','atendimento_balcao','dev_aplicacao','resp_chamado_complexo','criacao_apresentacao'
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
-- ============================================================
-- 4.2 ATUALIZAR FUNÇÃO atualizar_servico
-- ============================================================

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
      'desenvolvimento','agendamento_visitas','visitas_virtuais','visitas_presenciais',
      'atendimento_teams','atendimento_balcao','dev_aplicacao','resp_chamado_complexo','criacao_apresentacao'
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

  -- Atualizar observação se fornecida (aceita string vazia para limpar)
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
-- ============================================================
-- 5. CORRIGIR obter_servicos_estatisticas
--    BUG: Usava criado_em ao invés de data_execucao
--    FIX: Trocar para data_execucao (consistente com filtros da aba)
-- ============================================================

CREATE OR REPLACE FUNCTION obter_servicos_estatisticas(
  p_equipe_id UUID,
  p_periodo   TEXT DEFAULT '30d'
)
RETURNS JSONB AS $$
DECLARE
  v_data_inicio TIMESTAMPTZ;
  v_resultados  JSONB;
BEGIN
  -- Calcular data de início
  v_data_inicio := CASE p_periodo
    WHEN '24h' THEN NOW() - INTERVAL '24 hours'
    WHEN '48h' THEN NOW() - INTERVAL '48 hours'
    WHEN '72h' THEN NOW() - INTERVAL '72 hours'
    WHEN '7d'  THEN NOW() - INTERVAL '7 days'
    WHEN '30d' THEN NOW() - INTERVAL '30 days'
    ELSE             NOW() - INTERVAL '30 days'
  END;

  -- Agregar por usuário, tipo e período
  -- FIX: Usar data_execucao (consistente com filtros das abas Serviços da Equipe e Meus Serviços)
  WITH periodos AS (
    SELECT
      usuario_nome,
      usuario_id,
      tipo,
      quantidade,
      CASE
        -- Para períodos curtos, agrupar por hora
        WHEN p_periodo IN ('24h', '48h', '72h') THEN
          TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24"h"')
        -- Para períodos longos, agrupar por dia
        ELSE
          TO_CHAR(data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM')
      END AS periodo_key
    FROM servicos
    WHERE
      equipe_id = p_equipe_id
      AND data_execucao >= v_data_inicio
  ),
  agrupado AS (
    SELECT
      usuario_nome,
      usuario_id,
      tipo,
      periodo_key,
      SUM(quantidade) AS total_quantidade
    FROM periodos
    GROUP BY usuario_nome, usuario_id, tipo, periodo_key
  )
  SELECT jsonb_agg(
    jsonb_build_object(
      'usuario_nome',    usuario_nome,
      'usuario_id',      usuario_id,
      'tipo',            tipo,
      'periodo',         periodo_key,
      'total_quantidade', total_quantidade
    )
    ORDER BY usuario_nome, periodo_key
  )
  INTO v_resultados
  FROM agrupado;

  RETURN jsonb_build_object(
    'sucesso', true,
    'dados',   COALESCE(v_resultados, '[]'::jsonb),
    'periodo', p_periodo
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao obter estatísticas de serviços. Tente novamente.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- ============================================================
-- 6. ÍNDICE PARA descricao (otimizar buscas futuras)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_servicos_data_execucao ON servicos(data_execucao DESC);
-- ============================================================
-- 7. VERIFICAÇÃO FINAL — Contar migração
-- ============================================================

DO $$
DECLARE
  v_dev_app INTEGER;
  v_resp_cc INTEGER;
  v_cria_ap INTEGER;
  v_restante INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_dev_app FROM servicos WHERE tipo = 'dev_aplicacao';
  SELECT COUNT(*) INTO v_resp_cc FROM servicos WHERE tipo = 'resp_chamado_complexo';
  SELECT COUNT(*) INTO v_cria_ap FROM servicos WHERE tipo = 'criacao_apresentacao';
  SELECT COUNT(*) INTO v_restante FROM servicos WHERE tipo = 'desenvolvimento';

  RAISE NOTICE '=== VERIFICAÇÃO DA MIGRAÇÃO ===';
  RAISE NOTICE 'dev_aplicacao: % registros', v_dev_app;
  RAISE NOTICE 'resp_chamado_complexo: % registros', v_resp_cc;
  RAISE NOTICE 'criacao_apresentacao: % registros', v_cria_ap;
  RAISE NOTICE 'desenvolvimento (restantes): % registros', v_restante;
  RAISE NOTICE '================================';
END $$;

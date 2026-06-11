-- ============================================================
-- Migração: Remover tipo 'desenvolvimento' do sistema
-- Data: 2026-04-02
-- Descrição:
--   Tipo 'desenvolvimento' já foi migrado para tipos standalone
--   (dev_aplicacao, resp_chamado_complexo, criacao_apresentacao).
--   Não há mais registros com tipo='desenvolvimento' no banco.
--   Remove de: CHECK constraint, criar_servico, atualizar_servico.
-- ============================================================

-- ── 1. Atualizar CHECK constraint (sem 'desenvolvimento') ──

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
  'criacao_apresentacao'
));
COMMENT ON COLUMN servicos.tipo IS 'Tipo: email, homologacao, ouvidoria, cpa, chamado_smax, criacao_script, agendamento_visitas, visitas_virtuais, visitas_presenciais, atendimento_teams, atendimento_balcao, dev_aplicacao, resp_chamado_complexo, criacao_apresentacao';
-- ── 2. Atualizar criar_servico (remove 'desenvolvimento' da validação) ──

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
-- ── 3. Atualizar atualizar_servico (remove 'desenvolvimento' da validação) ──

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
-- ── 4. Verificação ──

DO $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM servicos WHERE tipo = 'desenvolvimento';
  IF v_count > 0 THEN
    RAISE NOTICE 'AVISO: % registros ainda com tipo=desenvolvimento!', v_count;
  ELSE
    RAISE NOTICE 'OK: Nenhum registro com tipo=desenvolvimento. Tipo removido com sucesso.';
  END IF;
END $$;

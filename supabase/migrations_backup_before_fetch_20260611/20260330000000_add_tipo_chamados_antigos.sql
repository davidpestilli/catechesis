-- ============================================================
-- Migration: Adicionar tipo de tarefa 'chamados_antigos'
-- Data: 2026-03-30
-- ============================================================

-- 1. Atualizar constraint CHECK na tabela tarefas
ALTER TABLE tarefas DROP CONSTRAINT IF EXISTS tarefas_tipo_check;
ALTER TABLE tarefas ADD CONSTRAINT tarefas_tipo_check
  CHECK (tipo IN ('ouvidoria', 'cpa', 'email', 'aplicacao', 'chamado_complexo', 'homologacao', 'rejeites', 'chamados_antigos'));
-- 2. Atualizar RPC criar_tarefa
CREATE OR REPLACE FUNCTION criar_tarefa(
  p_titulo TEXT,
  p_descricao TEXT DEFAULT NULL,
  p_equipe_id UUID DEFAULT NULL,
  p_tipo TEXT DEFAULT NULL,
  p_data_limite TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
  v_tarefa_id UUID;
  v_user_id UUID := auth.uid();
  v_tipo_final TEXT;
BEGIN
  IF p_titulo IS NULL OR TRIM(p_titulo) = '' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Título é obrigatório');
  END IF;

  v_tipo_final := NULLIF(TRIM(COALESCE(p_tipo, '')), '');
  
  IF v_tipo_final IS NOT NULL AND v_tipo_final NOT IN ('ouvidoria', 'cpa', 'email', 'aplicacao', 'chamado_complexo', 'homologacao', 'rejeites', 'chamados_antigos') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo inválido.');
  END IF;

  IF p_data_limite IS NOT NULL AND p_data_limite <= NOW() THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'O prazo de entrega deve ser uma data futura.');
  END IF;

  INSERT INTO tarefas (titulo, descricao, dono_id, equipe_id, criado_por, tipo, data_limite)
  VALUES (TRIM(p_titulo), p_descricao, v_user_id, p_equipe_id, v_user_id, v_tipo_final, p_data_limite)
  RETURNING id INTO v_tarefa_id;

  INSERT INTO tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (
    v_tarefa_id, 
    v_user_id, 
    'criacao',
    jsonb_build_object(
      'titulo', p_titulo, 
      'descricao', p_descricao, 
      'tipo', v_tipo_final,
      'data_limite', p_data_limite
    )
  );

  RETURN jsonb_build_object(
    'sucesso', true,
    'tarefa_id', v_tarefa_id,
    'mensagem', 'Tarefa criada com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa inválido.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao criar tarefa. Tente novamente.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- 3. Atualizar RPC atualizar_tarefa
CREATE OR REPLACE FUNCTION atualizar_tarefa(
  p_tarefa_id UUID,
  p_titulo TEXT DEFAULT NULL,
  p_descricao TEXT DEFAULT NULL,
  p_tipo TEXT DEFAULT NULL,
  p_data_limite TIMESTAMPTZ DEFAULT NULL,
  p_remover_prazo BOOLEAN DEFAULT FALSE
)
RETURNS JSONB AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_tarefa RECORD;
BEGIN
  SELECT * INTO v_tarefa FROM tarefas WHERE id = p_tarefa_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa não encontrada');
  END IF;

  SELECT role INTO v_user_role FROM public.users WHERE id = v_user_id;

  IF v_tarefa.dono_id != v_user_id AND COALESCE(v_user_role, 'user') != 'admin' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Sem permissão para editar esta tarefa');
  END IF;

  IF p_tipo IS NOT NULL AND p_tipo NOT IN ('ouvidoria', 'cpa', 'email', 'aplicacao', 'chamado_complexo', 'homologacao', 'rejeites', 'chamados_antigos', '') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa inválido.');
  END IF;

  UPDATE tarefas SET
    titulo = COALESCE(NULLIF(TRIM(p_titulo), ''), titulo),
    descricao = CASE WHEN p_descricao IS NOT NULL THEN p_descricao ELSE descricao END,
    tipo = CASE WHEN p_tipo IS NOT NULL THEN NULLIF(TRIM(p_tipo), '') ELSE tipo END,
    data_limite = CASE 
      WHEN p_remover_prazo = TRUE THEN NULL
      WHEN p_data_limite IS NOT NULL THEN p_data_limite 
      ELSE data_limite 
    END,
    atualizado_em = NOW()
  WHERE id = p_tarefa_id;

  IF p_titulo IS NOT NULL AND TRIM(p_titulo) != '' AND TRIM(p_titulo) != v_tarefa.titulo THEN
    INSERT INTO tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_titulo',
      jsonb_build_object('titulo_anterior', v_tarefa.titulo, 'titulo_novo', TRIM(p_titulo)));
  END IF;

  IF p_descricao IS NOT NULL AND p_descricao IS DISTINCT FROM v_tarefa.descricao THEN
    INSERT INTO tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_descricao',
      jsonb_build_object('descricao_anterior', v_tarefa.descricao, 'descricao_nova', p_descricao));
  END IF;

  IF p_data_limite IS NOT NULL OR p_remover_prazo = TRUE THEN
    INSERT INTO tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_prazo',
      jsonb_build_object(
        'prazo_anterior', v_tarefa.data_limite,
        'prazo_novo', CASE WHEN p_remover_prazo THEN NULL ELSE p_data_limite END
      ));
  END IF;

  RETURN jsonb_build_object('sucesso', true, 'mensagem', 'Tarefa atualizada');

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao atualizar tarefa.');
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================================
-- Migration: Permitir que ADM gerencie fases de tarefas de outros usuários
-- Data: 30/04/2026
-- Motivo: Usuário com role 'admin' precisa poder criar fases (adicionar_fase)
--         e marcar/desmarcar fases como concluídas (toggle_fase_concluida)
--         em tarefas atribuídas a outros membros.
-- Já estava OK: editar_fase, vincular_usuario_fase, reordenar_fases,
--               atualizar_tarefa, transferir_tarefa, excluir_tarefa.
-- ============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- adicionar_fase: agora aceita dono OU admin
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.adicionar_fase(
  p_tarefa_id UUID,
  p_titulo TEXT,
  p_descricao TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_tarefa RECORD;
  v_fase_id UUID;
  v_ordem INTEGER;
BEGIN
  -- Validar título
  IF p_titulo IS NULL OR TRIM(p_titulo) = '' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Título da fase é obrigatório');
  END IF;

  -- Verificar permissão
  SELECT * INTO v_tarefa FROM tarefas WHERE id = p_tarefa_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa não encontrada');
  END IF;

  -- Buscar role do usuário
  SELECT role INTO v_user_role FROM public.users WHERE id = v_user_id;

  -- Verificar permissão: dono OU admin
  IF v_tarefa.dono_id != v_user_id AND COALESCE(v_user_role, 'user') != 'admin' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsável ou administrador pode gerenciar fases');
  END IF;

  -- Calcular próxima ordem
  SELECT COALESCE(MAX(ordem), -1) + 1 INTO v_ordem
  FROM tarefa_fases WHERE tarefa_id = p_tarefa_id;

  -- Inserir fase
  INSERT INTO tarefa_fases (tarefa_id, titulo, descricao, ordem)
  VALUES (p_tarefa_id, TRIM(p_titulo), p_descricao, v_ordem)
  RETURNING id INTO v_fase_id;

  -- Registrar no histórico
  INSERT INTO tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (p_tarefa_id, v_user_id, 'fase_criada',
    jsonb_build_object('fase_id', v_fase_id, 'titulo', p_titulo, 'ordem', v_ordem));

  -- Recalcular percentual
  PERFORM recalcular_percentual_tarefa(p_tarefa_id);

  RETURN jsonb_build_object(
    'sucesso', true,
    'fase_id', v_fase_id,
    'mensagem', 'Fase adicionada'
  );

EXCEPTION
  WHEN not_null_violation THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Dados obrigatórios faltando para criar a fase.'
    );
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Erro ao adicionar fase. Tente novamente.'
    );
END;
$$;
ALTER FUNCTION public.adicionar_fase(UUID, TEXT, TEXT) OWNER TO postgres;
GRANT ALL ON FUNCTION public.adicionar_fase(UUID, TEXT, TEXT) TO anon, authenticated, service_role;
-- ─────────────────────────────────────────────────────────────────────────────
-- toggle_fase_concluida: agora aceita dono OU admin
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.toggle_fase_concluida(
  p_fase_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_user_role TEXT;
  v_fase RECORD;
  v_tipo_evento TEXT;
BEGIN
  -- Buscar fase e tarefa
  SELECT f.*, t.dono_id, t.titulo as tarefa_titulo
  INTO v_fase
  FROM tarefa_fases f
  JOIN tarefas t ON f.tarefa_id = t.id
  WHERE f.id = p_fase_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Fase não encontrada');
  END IF;

  -- Buscar role do usuário
  SELECT role INTO v_user_role FROM public.users WHERE id = v_user_id;

  -- Verificar permissão: dono OU admin
  IF v_fase.dono_id != v_user_id AND COALESCE(v_user_role, 'user') != 'admin' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsável ou administrador pode concluir fases');
  END IF;

  -- Toggle estado
  IF v_fase.concluida THEN
    -- Reabrir
    UPDATE tarefa_fases
    SET concluida = false, concluida_em = NULL, concluida_por = NULL
    WHERE id = p_fase_id;
    v_tipo_evento := 'fase_reaberta';
  ELSE
    -- Concluir
    UPDATE tarefa_fases
    SET concluida = true, concluida_em = NOW(), concluida_por = v_user_id
    WHERE id = p_fase_id;
    v_tipo_evento := 'fase_concluida';
  END IF;

  -- Registrar no histórico
  INSERT INTO tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (v_fase.tarefa_id, v_user_id, v_tipo_evento,
    jsonb_build_object('fase_id', p_fase_id, 'fase_titulo', v_fase.titulo));

  -- Recalcular percentual
  PERFORM recalcular_percentual_tarefa(v_fase.tarefa_id);

  RETURN jsonb_build_object(
    'sucesso', true,
    'concluida', NOT v_fase.concluida,
    'mensagem', CASE WHEN v_fase.concluida THEN 'Fase reaberta' ELSE 'Fase concluída' END
  );
END;
$$;
ALTER FUNCTION public.toggle_fase_concluida(UUID) OWNER TO postgres;
GRANT ALL ON FUNCTION public.toggle_fase_concluida(UUID) TO anon, authenticated, service_role;
-- Forçar reload do schema do PostgREST
NOTIFY pgrst, 'reload schema';

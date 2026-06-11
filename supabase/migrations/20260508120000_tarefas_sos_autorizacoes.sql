-- ============================================================================
-- Autorizacoes: administracao de Tarefas e escrita SOS por permissao
-- Data: 2026-05-08
--
-- 1) Novo objeto no BossOnly > Autorizacoes:
--    tarefas.admin_acoes
-- 2) Acoes que antes dependiam de role admin em Tarefas passam a aceitar
--    public.tem_permissao('tarefas.admin_acoes'). Admin continua liberado
--    porque tem_permissao() retorna TRUE para role admin.
-- 3) O objeto existente distribuidor.sos_keywords passa a liberar tambem
--    listar/adicionar/remover/reavaliar palavras SOS no backend.
-- ============================================================================

BEGIN;
-- ---------------------------------------------------------------------------
-- Catalogo de permissoes
-- ---------------------------------------------------------------------------
INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem)
VALUES (
  'tarefas.admin_acoes',
  'Administracao completa de Tarefas',
  'Permite executar no sistema de Tarefas as acoes que eram exclusivas de administradores: editar, alterar estado, transferir, excluir, gerenciar fases e excluir comentarios de terceiros.',
  'tarefas',
  'src/components/TarefaDetalheModal.tsx'
)
ON CONFLICT (codigo) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  categoria = EXCLUDED.categoria,
  origem = EXCLUDED.origem;
-- ---------------------------------------------------------------------------
-- RLS: tabelas acessadas diretamente pelo frontend em Tarefas
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'tarefas' AND cmd IN ('UPDATE', 'DELETE')
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.tarefas', r.policyname);
  END LOOP;

  FOR r IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'tarefa_fases' AND cmd = 'ALL'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.tarefa_fases', r.policyname);
  END LOOP;

  FOR r IN
    SELECT policyname FROM pg_policies
    WHERE schemaname = 'public' AND tablename = 'tarefa_comentarios' AND cmd = 'DELETE'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.tarefa_comentarios', r.policyname);
  END LOOP;
END $$;
CREATE POLICY "tarefas_update_dono_ou_admin_acoes"
  ON public.tarefas
  FOR UPDATE
  TO authenticated
  USING (dono_id = auth.uid() OR public.tem_permissao('tarefas.admin_acoes'))
  WITH CHECK (dono_id = auth.uid() OR public.tem_permissao('tarefas.admin_acoes'));
CREATE POLICY "tarefas_delete_dono_ou_admin_acoes"
  ON public.tarefas
  FOR DELETE
  TO authenticated
  USING (dono_id = auth.uid() OR public.tem_permissao('tarefas.admin_acoes'));
CREATE POLICY "tarefa_fases_gerencia_dono_ou_admin_acoes"
  ON public.tarefa_fases
  FOR ALL
  TO authenticated
  USING (
    tarefa_id IN (
      SELECT t.id
      FROM public.tarefas t
      WHERE t.dono_id = auth.uid() OR public.tem_permissao('tarefas.admin_acoes')
    )
  )
  WITH CHECK (
    tarefa_id IN (
      SELECT t.id
      FROM public.tarefas t
      WHERE t.dono_id = auth.uid() OR public.tem_permissao('tarefas.admin_acoes')
    )
  );
CREATE POLICY "tarefa_comentarios_delete_autor_ou_admin_acoes"
  ON public.tarefa_comentarios
  FOR DELETE
  TO authenticated
  USING (autor_id = auth.uid() OR public.tem_permissao('tarefas.admin_acoes'));
-- ---------------------------------------------------------------------------
-- RLS SOS: escrita por quem tem distribuidor.sos_keywords
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS sos_palavras_admin_all ON public.sos_palavras_chave;
CREATE POLICY sos_palavras_admin_all ON public.sos_palavras_chave
  FOR ALL
  TO authenticated
  USING (public.tem_permissao('distribuidor.sos_keywords'))
  WITH CHECK (public.tem_permissao('distribuidor.sos_keywords'));
-- ---------------------------------------------------------------------------
-- SOS RPCs: backend respeita a mesma autorizacao da UI
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.sos_reavaliar_tickets_fila(p_equipe_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gses text[];
  v_count integer := 0;
BEGIN
  IF NOT public.tem_permissao('distribuidor.sos_keywords') THEN
    RAISE EXCEPTION 'Apenas usuarios autorizados podem reavaliar palavras SOS';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatorio para reavaliacao SOS';
  END IF;

  SELECT array_agg(gse) INTO v_gses
  FROM public.gse_equipes WHERE equipe_id = p_equipe_id;

  IF v_gses IS NULL OR array_length(v_gses, 1) IS NULL THEN
    RETURN 0;
  END IF;

  WITH alvo AS (
    SELECT id FROM public.tickets t
    WHERE t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND t.gse = ANY(v_gses)
  )
  UPDATE public.tickets t
     SET sos_palavras = public.sos_match_palavras(t.descricao, p_equipe_id),
         sos = CASE
                 WHEN t.sos_override IS TRUE THEN t.sos
                 ELSE COALESCE(array_length(public.sos_match_palavras(t.descricao, p_equipe_id), 1), 0) > 0
               END
   FROM alvo
   WHERE t.id = alvo.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
CREATE OR REPLACE FUNCTION public.sos_listar_palavras_admin(p_equipe_id uuid)
RETURNS TABLE(
  id uuid,
  palavra text,
  palavra_normalizada text,
  ativo boolean,
  total_tickets bigint,
  tickets_em_fila bigint,
  tickets_livres bigint,
  tickets_suspensos bigint,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gses text[];
BEGIN
  IF NOT public.tem_permissao('distribuidor.sos_keywords') THEN
    RAISE EXCEPTION 'Apenas usuarios autorizados podem listar palavras SOS';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatorio';
  END IF;

  SELECT array_agg(gse) INTO v_gses
  FROM public.gse_equipes WHERE equipe_id = p_equipe_id;

  RETURN QUERY
  SELECT
    p.id,
    p.palavra,
    p.palavra_normalizada,
    p.ativo,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS total_tickets,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_em_fila,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_livres,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = true
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_suspensos,
    p.created_at
  FROM public.sos_palavras_chave p
  WHERE p.equipe_id = p_equipe_id
  ORDER BY tickets_livres DESC, tickets_suspensos DESC, p.palavra ASC;
END;
$$;
CREATE OR REPLACE FUNCTION public.sos_adicionar_palavra(
  p_palavra text,
  p_equipe_id uuid,
  p_aplicar_retroativo boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_norm text;
BEGIN
  IF NOT public.tem_permissao('distribuidor.sos_keywords') THEN
    RAISE EXCEPTION 'Apenas usuarios autorizados podem adicionar palavras SOS';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatorio';
  END IF;

  IF p_palavra IS NULL OR length(trim(p_palavra)) < 2 THEN
    RAISE EXCEPTION 'Palavra deve ter pelo menos 2 caracteres';
  END IF;

  v_norm := lower(public.f_unaccent(trim(p_palavra)));

  SELECT id INTO v_id
  FROM public.sos_palavras_chave
  WHERE palavra_normalizada = v_norm AND equipe_id = p_equipe_id;

  IF v_id IS NOT NULL THEN
    UPDATE public.sos_palavras_chave SET ativo = true WHERE id = v_id;
  ELSE
    INSERT INTO public.sos_palavras_chave (palavra, equipe_id, criado_por)
    VALUES (trim(p_palavra), p_equipe_id, auth.uid())
    RETURNING id INTO v_id;
  END IF;

  IF p_aplicar_retroativo THEN
    PERFORM public.sos_reavaliar_tickets_fila(p_equipe_id);
  END IF;

  RETURN v_id;
END;
$$;
CREATE OR REPLACE FUNCTION public.sos_remover_palavra(p_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_equipe_id uuid;
BEGIN
  IF NOT public.tem_permissao('distribuidor.sos_keywords') THEN
    RAISE EXCEPTION 'Apenas usuarios autorizados podem remover palavras SOS';
  END IF;

  SELECT equipe_id INTO v_equipe_id
  FROM public.sos_palavras_chave
  WHERE id = p_id;

  DELETE FROM public.sos_palavras_chave WHERE id = p_id;

  IF v_equipe_id IS NOT NULL THEN
    PERFORM public.sos_reavaliar_tickets_fila(v_equipe_id);
  END IF;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_reavaliar_tickets_fila(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_listar_palavras_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_adicionar_palavra(text, uuid, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_remover_palavra(uuid) TO authenticated;
-- ---------------------------------------------------------------------------
-- Tarefas RPCs: dono ou tarefas.admin_acoes
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.atualizar_tarefa(
  p_tarefa_id uuid,
  p_titulo text DEFAULT NULL,
  p_descricao text DEFAULT NULL,
  p_tipo text DEFAULT NULL,
  p_data_limite timestamptz DEFAULT NULL,
  p_remover_prazo boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_tarefa record;
  v_tipos_permitidos CONSTANT text[] := ARRAY[
    'ouvidoria', 'cpa', 'email', 'aplicacao', 'chamado_complexo',
    'homologacao', 'rejeites', 'chamados_antigos', 'chamado_smax',
    'criacao_script', 'agendamento_visitas', 'visitas_virtuais',
    'visitas_presenciais', 'atendimento_teams', 'atendimento_balcao',
    'dev_aplicacao', 'resp_chamado_complexo', 'analise_rejeites',
    'analise_chamados_antigos', 'criacao_apresentacao', 'configuracao_sistema',
    'lotacao_usuarios', 'cadastro_radar', 'cadastro_melhoria', 'estudos_atualizacao'
  ];
BEGIN
  SELECT * INTO v_tarefa
  FROM public.tarefas
  WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Sem permissao para editar esta tarefa');
  END IF;

  IF p_tipo IS NOT NULL AND p_tipo <> '' AND NOT p_tipo = ANY(v_tipos_permitidos) THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa invalido.');
  END IF;

  UPDATE public.tarefas
  SET
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
    INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_titulo',
      jsonb_build_object('titulo_anterior', v_tarefa.titulo, 'titulo_novo', TRIM(p_titulo)));
  END IF;

  IF p_descricao IS NOT NULL AND p_descricao IS DISTINCT FROM v_tarefa.descricao THEN
    INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (p_tarefa_id, v_user_id, 'edicao_descricao',
      jsonb_build_object('descricao_anterior', v_tarefa.descricao, 'descricao_nova', p_descricao));
  END IF;

  IF p_data_limite IS NOT NULL OR p_remover_prazo = TRUE THEN
    INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
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
$$;
CREATE OR REPLACE FUNCTION public.alterar_estado_tarefa(
  p_tarefa_id uuid,
  p_novo_estado text,
  p_justificativa text DEFAULT NULL::text,
  p_resumo text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_nome text;
  v_tarefa record;
  v_tipo_evento text;
  v_participantes uuid[];
  v_resumo_normalizado text;
  v_justificativa_normalizada text;
BEGIN
  IF p_novo_estado NOT IN ('em_andamento', 'pausada', 'concluida', 'cancelada') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Estado invalido');
  END IF;

  SELECT COALESCE(nome, email) INTO v_user_nome
  FROM public.users
  WHERE id = v_user_id;

  SELECT * INTO v_tarefa
  FROM public.tarefas
  WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsavel ou usuario autorizado pode alterar o estado');
  END IF;

  v_resumo_normalizado := NULLIF(TRIM(COALESCE(p_resumo, '')), '');
  v_justificativa_normalizada := NULLIF(TRIM(COALESCE(p_justificativa, '')), '');

  IF p_novo_estado = 'pausada' THEN
    v_tipo_evento := 'estado_pausada';
  ELSIF p_novo_estado = 'cancelada' THEN
    v_tipo_evento := 'estado_cancelada';
  ELSIF p_novo_estado = 'concluida' THEN
    v_tipo_evento := 'estado_concluida';
  ELSIF p_novo_estado = 'em_andamento' THEN
    IF v_tarefa.estado IN ('pausada', 'cancelada') THEN
      v_tipo_evento := 'estado_reativada';
    ELSE
      v_tipo_evento := 'estado_em_andamento';
    END IF;
  END IF;

  UPDATE public.tarefas
  SET
    estado = p_novo_estado,
    resumo_conclusao = CASE WHEN p_novo_estado = 'concluida' THEN v_resumo_normalizado ELSE resumo_conclusao END,
    atualizado_em = NOW()
  WHERE id = p_tarefa_id;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados, justificativa, resumo)
  VALUES (
    p_tarefa_id,
    v_user_id,
    v_tipo_evento,
    jsonb_build_object('estado_anterior', v_tarefa.estado, 'estado_novo', p_novo_estado),
    v_justificativa_normalizada,
    CASE WHEN p_novo_estado = 'concluida' THEN v_resumo_normalizado ELSE NULL END
  );

  SELECT ARRAY_AGG(DISTINCT autor_id) INTO v_participantes
  FROM public.tarefa_threads
  WHERE tarefa_id = p_tarefa_id AND autor_id != v_user_id;

  IF v_participantes IS NOT NULL THEN
    INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
    SELECT
      p_tarefa_id,
      unnest(v_participantes),
      v_user_id,
      'tarefa_estado_alterado',
      jsonb_build_object(
        'estado_anterior', v_tarefa.estado,
        'estado_novo', p_novo_estado,
        'tarefa_titulo', v_tarefa.titulo,
        'remetente_nome', v_user_nome
      );
  END IF;

  RETURN jsonb_build_object(
    'sucesso', true,
    'estado', p_novo_estado,
    'mensagem', 'Estado alterado para ' || p_novo_estado
  );

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao alterar estado da tarefa. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.adicionar_fase(
  p_tarefa_id uuid,
  p_titulo text,
  p_descricao text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_tarefa record;
  v_fase_id uuid;
  v_ordem integer;
BEGIN
  IF p_titulo IS NULL OR TRIM(p_titulo) = '' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Titulo da fase e obrigatorio');
  END IF;

  SELECT * INTO v_tarefa FROM public.tarefas WHERE id = p_tarefa_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsavel ou usuario autorizado pode gerenciar fases');
  END IF;

  SELECT COALESCE(MAX(ordem), -1) + 1 INTO v_ordem
  FROM public.tarefa_fases WHERE tarefa_id = p_tarefa_id;

  INSERT INTO public.tarefa_fases (tarefa_id, titulo, descricao, ordem)
  VALUES (p_tarefa_id, TRIM(p_titulo), p_descricao, v_ordem)
  RETURNING id INTO v_fase_id;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (p_tarefa_id, v_user_id, 'fase_criada',
    jsonb_build_object('fase_id', v_fase_id, 'titulo', p_titulo, 'ordem', v_ordem));

  PERFORM public.recalcular_percentual_tarefa(p_tarefa_id);

  RETURN jsonb_build_object('sucesso', true, 'fase_id', v_fase_id, 'mensagem', 'Fase adicionada');

EXCEPTION
  WHEN not_null_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados obrigatorios faltando para criar a fase.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao adicionar fase. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.toggle_fase_concluida(p_fase_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_fase record;
  v_tipo_evento text;
BEGIN
  SELECT f.*, t.dono_id, t.titulo AS tarefa_titulo
  INTO v_fase
  FROM public.tarefa_fases f
  JOIN public.tarefas t ON f.tarefa_id = t.id
  WHERE f.id = p_fase_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Fase nao encontrada');
  END IF;

  IF v_fase.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsavel ou usuario autorizado pode concluir fases');
  END IF;

  IF v_fase.concluida THEN
    UPDATE public.tarefa_fases
    SET concluida = false, concluida_em = NULL, concluida_por = NULL
    WHERE id = p_fase_id;
    v_tipo_evento := 'fase_reaberta';
  ELSE
    UPDATE public.tarefa_fases
    SET concluida = true, concluida_em = NOW(), concluida_por = v_user_id
    WHERE id = p_fase_id;
    v_tipo_evento := 'fase_concluida';
  END IF;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (v_fase.tarefa_id, v_user_id, v_tipo_evento,
    jsonb_build_object('fase_id', p_fase_id, 'fase_titulo', v_fase.titulo));

  PERFORM public.recalcular_percentual_tarefa(v_fase.tarefa_id);

  RETURN jsonb_build_object(
    'sucesso', true,
    'concluida', NOT v_fase.concluida,
    'mensagem', CASE WHEN v_fase.concluida THEN 'Fase reaberta' ELSE 'Fase concluida' END
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.editar_fase(p_fase_id uuid, p_titulo text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_fase record;
  v_tarefa record;
  v_titulo_anterior text;
BEGIN
  IF p_titulo IS NULL OR TRIM(p_titulo) = '' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Titulo da fase e obrigatorio');
  END IF;

  SELECT * INTO v_fase FROM public.tarefa_fases WHERE id = p_fase_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Fase nao encontrada');
  END IF;

  SELECT * INTO v_tarefa FROM public.tarefas WHERE id = v_fase.tarefa_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsavel ou usuario autorizado pode editar fases');
  END IF;

  v_titulo_anterior := v_fase.titulo;

  UPDATE public.tarefa_fases SET titulo = TRIM(p_titulo) WHERE id = p_fase_id;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (v_fase.tarefa_id, v_user_id, 'fase_editada',
    jsonb_build_object(
      'fase_id', p_fase_id,
      'titulo_anterior', v_titulo_anterior,
      'titulo_novo', TRIM(p_titulo)
    ));

  UPDATE public.tarefas SET atualizado_em = NOW() WHERE id = v_fase.tarefa_id;

  RETURN jsonb_build_object('sucesso', true, 'mensagem', 'Fase atualizada');

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao editar fase. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.reordenar_fases(p_tarefa_id uuid, p_fases_ordenadas uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_tarefa record;
  v_fase_id uuid;
  v_posicao integer := 0;
BEGIN
  SELECT * INTO v_tarefa FROM public.tarefas WHERE id = p_tarefa_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Sem permissao para reordenar fases');
  END IF;

  FOREACH v_fase_id IN ARRAY p_fases_ordenadas
  LOOP
    UPDATE public.tarefa_fases
    SET ordem = v_posicao
    WHERE id = v_fase_id AND tarefa_id = p_tarefa_id;

    v_posicao := v_posicao + 1;
  END LOOP;

  UPDATE public.tarefas SET atualizado_em = NOW() WHERE id = p_tarefa_id;

  RETURN jsonb_build_object('sucesso', true, 'mensagem', 'Fases reordenadas');

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao reordenar fases. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.excluir_tarefa(p_tarefa_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_tarefa record;
BEGIN
  SELECT * INTO v_tarefa FROM public.tarefas WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsavel ou usuario autorizado pode excluir a tarefa');
  END IF;

  DELETE FROM public.tarefa_notificacoes WHERE tarefa_id = p_tarefa_id;
  DELETE FROM public.tarefa_thread_respostas WHERE thread_id IN (
    SELECT id FROM public.tarefa_threads WHERE tarefa_id = p_tarefa_id
  );
  DELETE FROM public.tarefa_threads WHERE tarefa_id = p_tarefa_id;
  DELETE FROM public.tarefa_documentos WHERE tarefa_id = p_tarefa_id;
  DELETE FROM public.tarefa_historico WHERE tarefa_id = p_tarefa_id;
  DELETE FROM public.tarefa_fases WHERE tarefa_id = p_tarefa_id;
  DELETE FROM public.tarefas WHERE id = p_tarefa_id;

  RETURN jsonb_build_object('sucesso', true, 'mensagem', 'Tarefa excluida com sucesso');

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao excluir tarefa. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.transferir_tarefa(p_tarefa_id uuid, p_novo_dono_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_nome text;
  v_tarefa record;
  v_novo_dono_nome text;
  v_dono_anterior_nome text;
BEGIN
  SELECT COALESCE(nome, email) INTO v_user_nome
  FROM public.users WHERE id = v_user_id;

  SELECT t.*, u.nome AS dono_nome
  INTO v_tarefa
  FROM public.tarefas t
  LEFT JOIN public.users u ON t.dono_id = u.id
  WHERE t.id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsavel ou usuario autorizado pode transferir a tarefa');
  END IF;

  SELECT nome INTO v_novo_dono_nome FROM public.users WHERE id = p_novo_dono_id;

  IF v_novo_dono_nome IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Novo responsavel nao encontrado');
  END IF;

  v_dono_anterior_nome := v_tarefa.dono_nome;

  UPDATE public.tarefas
  SET dono_id = p_novo_dono_id, atualizado_em = NOW()
  WHERE id = p_tarefa_id;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (
    p_tarefa_id,
    v_user_id,
    'mudanca_responsavel',
    jsonb_build_object(
      'dono_anterior_id', v_tarefa.dono_id,
      'dono_anterior_nome', v_dono_anterior_nome,
      'novo_dono_id', p_novo_dono_id,
      'novo_dono_nome', v_novo_dono_nome,
      'transferido_por_admin', v_tarefa.dono_id != v_user_id,
      'estado_no_momento', v_tarefa.estado
    )
  );

  IF v_tarefa.estado != 'concluida' THEN
    INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
    VALUES (
      p_tarefa_id,
      p_novo_dono_id,
      v_user_id,
      'tarefa_responsavel_alterado',
      jsonb_build_object(
        'tarefa_titulo', v_tarefa.titulo,
        'responsavel_anterior', v_dono_anterior_nome,
        'remetente_nome', v_user_nome
      )
    );

    IF v_tarefa.dono_id != v_user_id AND v_tarefa.dono_id != p_novo_dono_id THEN
      INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
      VALUES (
        p_tarefa_id,
        v_tarefa.dono_id,
        v_user_id,
        'tarefa_responsavel_alterado',
        jsonb_build_object(
          'tarefa_titulo', v_tarefa.titulo,
          'responsavel_anterior', v_dono_anterior_nome,
          'novo_responsavel', v_novo_dono_nome,
          'remetente_nome', v_user_nome,
          'transferido_por_admin', true
        )
      );
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'sucesso', true,
    'novo_dono_id', p_novo_dono_id,
    'novo_dono_nome', v_novo_dono_nome,
    'mensagem', 'Tarefa transferida para ' || v_novo_dono_nome
  );

EXCEPTION
  WHEN foreign_key_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Novo responsavel nao encontrado ou invalido.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao transferir tarefa. Tente novamente.');
END;
$$;
CREATE OR REPLACE FUNCTION public.excluir_comentario_tarefa(p_comentario_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe uuid;
  v_tarefa_equipe uuid;
  v_comentario record;
BEGIN
  SELECT * INTO v_comentario
  FROM public.tarefa_comentarios
  WHERE id = p_comentario_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Comentario nao encontrado');
  END IF;

  SELECT equipe_id INTO v_user_equipe
  FROM public.users
  WHERE id = v_user_id;

  SELECT t.equipe_id INTO v_tarefa_equipe
  FROM public.tarefas t
  WHERE t.id = v_comentario.tarefa_id;

  IF v_tarefa_equipe IS DISTINCT FROM v_user_equipe AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Sem permissao para excluir este comentario');
  END IF;

  IF v_comentario.autor_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Sem permissao para excluir este comentario');
  END IF;

  DELETE FROM public.tarefa_comentarios WHERE id = p_comentario_id;

  RETURN jsonb_build_object('sucesso', true, 'mensagem', 'Comentario excluido');

EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao excluir comentario.');
END;
$$;
CREATE OR REPLACE FUNCTION public.vincular_usuario_fase(p_fase_id uuid, p_usuario_id uuid DEFAULT NULL::uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_nome text;
  v_fase record;
  v_tarefa record;
  v_usuario_nome text;
  v_usuario_anterior_id uuid;
BEGIN
  SELECT COALESCE(nome, email) INTO v_user_nome
  FROM public.users WHERE id = v_user_id;

  SELECT * INTO v_fase FROM public.tarefa_fases WHERE id = p_fase_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Fase nao encontrada');
  END IF;

  SELECT * INTO v_tarefa FROM public.tarefas WHERE id = v_fase.tarefa_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa nao encontrada');
  END IF;

  IF v_tarefa.dono_id != v_user_id AND NOT public.tem_permissao('tarefas.admin_acoes') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas o responsavel ou usuario autorizado pode vincular usuarios a fases');
  END IF;

  v_usuario_anterior_id := v_fase.usuario_vinculado_id;

  IF p_usuario_id IS NULL THEN
    UPDATE public.tarefa_fases
    SET usuario_vinculado_id = NULL, usuario_vinculado_em = NULL
    WHERE id = p_fase_id;

    INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
    VALUES (v_fase.tarefa_id, v_user_id, 'fase_editada',
      jsonb_build_object(
        'fase_id', p_fase_id,
        'fase_titulo', v_fase.titulo,
        'acao', 'usuario_desvinculado',
        'usuario_anterior_id', v_usuario_anterior_id
      ));

    RETURN jsonb_build_object('sucesso', true, 'mensagem', 'Usuario desvinculado da fase');
  END IF;

  SELECT COALESCE(nome, email) INTO v_usuario_nome
  FROM public.users
  WHERE id = p_usuario_id;

  IF v_usuario_nome IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuario nao encontrado');
  END IF;

  UPDATE public.tarefa_fases
  SET usuario_vinculado_id = p_usuario_id, usuario_vinculado_em = NOW()
  WHERE id = p_fase_id;

  INSERT INTO public.tarefa_historico (tarefa_id, usuario_id, tipo_evento, dados)
  VALUES (v_fase.tarefa_id, v_user_id, 'fase_editada',
    jsonb_build_object(
      'fase_id', p_fase_id,
      'fase_titulo', v_fase.titulo,
      'acao', 'usuario_vinculado',
      'usuario_id', p_usuario_id,
      'usuario_nome', v_usuario_nome
    ));

  UPDATE public.tarefas SET atualizado_em = NOW() WHERE id = v_fase.tarefa_id;

  IF p_usuario_id != v_user_id THEN
    INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
    VALUES (
      v_fase.tarefa_id,
      p_usuario_id,
      v_user_id,
      'fase_usuario_vinculado',
      jsonb_build_object(
        'tarefa_titulo', v_tarefa.titulo,
        'fase_titulo', v_fase.titulo,
        'remetente_nome', v_user_nome
      )
    );
  END IF;

  RETURN jsonb_build_object(
    'sucesso', true,
    'usuario_nome', v_usuario_nome,
    'mensagem', v_usuario_nome || ' vinculado a fase "' || v_fase.titulo || '"'
  );

EXCEPTION
  WHEN foreign_key_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuario invalido.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao vincular usuario. Tente novamente.');
END;
$$;
GRANT EXECUTE ON FUNCTION public.atualizar_tarefa(uuid, text, text, text, timestamptz, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.alterar_estado_tarefa(uuid, text, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.adicionar_fase(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.toggle_fase_concluida(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.editar_fase(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reordenar_fases(uuid, uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.excluir_tarefa(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.transferir_tarefa(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.excluir_comentario_tarefa(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.vincular_usuario_fase(uuid, uuid) TO authenticated;
COMMIT;
NOTIFY pgrst, 'reload schema';

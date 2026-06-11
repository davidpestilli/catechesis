-- =====================================================================
-- Migração: Notificar supervisor da equipe ao concluir tarefa
-- Data: 2026-05-02
--
-- Objetivos:
--   1. Permitir funções adicionais por equipe sem alterar o role principal.
--   2. Criar notificação específica de tarefa concluída para supervisores.
--   3. Atualizar concluir_tarefa_com_servico para notificar supervisores.
-- =====================================================================

-- ── 1. Funções adicionais por equipe ─────────────────────────────────

CREATE TABLE IF NOT EXISTS public.usuario_funcoes_equipe (
  id         UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  equipe_id  UUID NOT NULL REFERENCES public.equipes(id) ON DELETE CASCADE,
  funcao     TEXT NOT NULL,
  ativo      BOOLEAN NOT NULL DEFAULT TRUE,
  criado_por UUID REFERENCES public.users(id) ON DELETE SET NULL,
  criado_em  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT usuario_funcoes_equipe_funcao_check CHECK (funcao IN ('supervisor')),
  CONSTRAINT usuario_funcoes_equipe_unique UNIQUE (user_id, equipe_id, funcao)
);
CREATE INDEX IF NOT EXISTS idx_usuario_funcoes_equipe_user
  ON public.usuario_funcoes_equipe (user_id)
  WHERE ativo = TRUE;
CREATE INDEX IF NOT EXISTS idx_usuario_funcoes_equipe_equipe_funcao
  ON public.usuario_funcoes_equipe (equipe_id, funcao)
  WHERE ativo = TRUE;
ALTER TABLE public.usuario_funcoes_equipe ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins gerenciam funcoes equipe" ON public.usuario_funcoes_equipe;
CREATE POLICY "Admins gerenciam funcoes equipe"
  ON public.usuario_funcoes_equipe
  FOR ALL
  TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
DROP POLICY IF EXISTS "Usuario ve suas funcoes equipe" ON public.usuario_funcoes_equipe;
CREATE POLICY "Usuario ve suas funcoes equipe"
  ON public.usuario_funcoes_equipe
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());
GRANT SELECT ON public.usuario_funcoes_equipe TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
-- Permite ao admin substituir, de forma atômica, as equipes em que um usuário
-- exerce a função adicional de supervisor.
CREATE OR REPLACE FUNCTION public.admin_set_usuario_supervisor_equipes(
  p_user_id UUID,
  p_equipe_ids UUID[] DEFAULT '{}'::UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total   INTEGER := 0;
  v_invalid INTEGER := 0;
BEGIN
  IF NOT public.is_admin() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado');
  END IF;

  IF p_user_id IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Usuário obrigatório');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Usuário não encontrado');
  END IF;

  WITH equipe_ids AS (
    SELECT DISTINCT equipe_id
    FROM unnest(COALESCE(p_equipe_ids, '{}'::UUID[])) AS equipe_id
    WHERE equipe_id IS NOT NULL
  )
  SELECT COUNT(*) INTO v_total
  FROM equipe_ids;

  WITH equipe_ids AS (
    SELECT DISTINCT equipe_id
    FROM unnest(COALESCE(p_equipe_ids, '{}'::UUID[])) AS equipe_id
    WHERE equipe_id IS NOT NULL
  )
  SELECT COUNT(*) INTO v_invalid
  FROM equipe_ids ids
  LEFT JOIN public.equipes e ON e.id = ids.equipe_id
  WHERE e.id IS NULL;

  IF v_invalid > 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Uma ou mais equipes informadas não existem');
  END IF;

  DELETE FROM public.usuario_funcoes_equipe
  WHERE user_id = p_user_id
    AND funcao = 'supervisor';

  INSERT INTO public.usuario_funcoes_equipe (user_id, equipe_id, funcao, ativo, criado_por)
  SELECT p_user_id, ids.equipe_id, 'supervisor', TRUE, auth.uid()
  FROM (
    SELECT DISTINCT equipe_id
    FROM unnest(COALESCE(p_equipe_ids, '{}'::UUID[])) AS equipe_id
    WHERE equipe_id IS NOT NULL
  ) ids;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Funções de supervisor atualizadas com sucesso',
    'total', v_total
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_usuario_supervisor_equipes(UUID, UUID[]) TO authenticated;
COMMENT ON TABLE public.usuario_funcoes_equipe IS
  'Funções adicionais por equipe. Permite, por exemplo, que um usuário admin também atue como supervisor de uma equipe sem alterar seu role principal.';
COMMENT ON FUNCTION public.admin_set_usuario_supervisor_equipes(UUID, UUID[]) IS
  'Define as equipes em que o usuário atua como supervisor adicional. Apenas role admin.';
-- Vínculo inicial solicitado: admin dpestilli também supervisor da equipe 2.3.2.
INSERT INTO public.usuario_funcoes_equipe (user_id, equipe_id, funcao, ativo, criado_por)
SELECT u.id, e.id, 'supervisor', TRUE, u.id
FROM public.users u
CROSS JOIN public.equipes e
WHERE LOWER(u.email) = 'dpestilli@tjsp.jus.br'
  AND e.nome = '2.3.2'
ON CONFLICT (user_id, equipe_id, funcao)
DO UPDATE SET ativo = TRUE, atualizado_em = NOW();
-- ── 2. Novo tipo de notificação ──────────────────────────────────────

ALTER TABLE public.tarefa_notificacoes DROP CONSTRAINT IF EXISTS tarefa_notificacoes_tipo_check;
ALTER TABLE public.tarefa_notificacoes ADD CONSTRAINT tarefa_notificacoes_tipo_check
CHECK (tipo IN (
  'tarefa_criada',
  'tarefa_estado_alterado',
  'tarefa_responsavel_alterado',
  'tarefa_concluida',
  'fase_concluida',
  'thread_criada',
  'thread_resposta',
  'mencao',
  'documento_adicionado',
  'comentario_fase',
  'comentario_documento',
  'fase_usuario_vinculado',
  'prazo_se_esgotando'
));
-- ── 3. Concluir tarefa, criar serviço e notificar supervisores ───────

CREATE OR REPLACE FUNCTION public.concluir_tarefa_com_servico(
  p_tarefa_id  UUID,
  p_resumo     TEXT,
  p_quantidade INTEGER
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id                  UUID := auth.uid();
  v_tarefa                   RECORD;
  v_tipo_servico             TEXT;
  v_usuario_nome             TEXT;
  v_finalizador_nome         TEXT;
  v_descricao_servico        TEXT;
  v_servico_id               UUID;
  v_estado_resultado         JSONB;
  v_supervisores_notificados INTEGER := 0;
BEGIN
  IF p_quantidade IS NULL OR p_quantidade < 1 THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Quantidade deve ser um número inteiro maior ou igual a 1');
  END IF;

  IF p_resumo IS NULL OR TRIM(p_resumo) = '' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Resumo obrigatório para concluir');
  END IF;

  SELECT COALESCE(nome, email, 'Usuário') INTO v_finalizador_nome
  FROM public.users
  WHERE id = v_user_id;

  IF v_finalizador_nome IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário autenticado não encontrado');
  END IF;

  SELECT * INTO v_tarefa
  FROM public.tarefas
  WHERE id = p_tarefa_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tarefa não encontrada');
  END IF;

  IF v_tarefa.estado != 'em_andamento' THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Apenas tarefas em andamento podem ser concluídas por este fluxo');
  END IF;

  IF v_tarefa.tipo IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Defina um tipo para a tarefa antes de concluir');
  END IF;

  IF v_tarefa.equipe_id IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'A tarefa precisa estar vinculada a uma equipe para gerar serviço');
  END IF;

  v_tipo_servico := CASE v_tarefa.tipo
    WHEN 'ouvidoria' THEN 'ouvidoria'
    WHEN 'cpa' THEN 'cpa'
    WHEN 'email' THEN 'email'
    WHEN 'aplicacao' THEN 'dev_aplicacao'
    WHEN 'chamado_complexo' THEN 'resp_chamado_complexo'
    WHEN 'homologacao' THEN 'homologacao'
    WHEN 'rejeites' THEN 'analise_rejeites'
    WHEN 'chamados_antigos' THEN 'analise_chamados_antigos'
    ELSE NULL
  END;

  IF v_tipo_servico IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Tipo de tarefa sem serviço equivalente');
  END IF;

  SELECT COALESCE(nome, email, 'Usuário') INTO v_usuario_nome
  FROM public.users
  WHERE id = v_tarefa.dono_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Responsável da tarefa não encontrado');
  END IF;

  v_descricao_servico := concat_ws(
    ' - ',
    NULLIF(TRIM(COALESCE(v_tarefa.titulo, '')), ''),
    NULLIF(TRIM(COALESCE(v_tarefa.descricao, '')), '')
  );

  v_estado_resultado := public.alterar_estado_tarefa(p_tarefa_id, 'concluida', NULL, p_resumo);

  IF COALESCE((v_estado_resultado->>'sucesso')::BOOLEAN, false) IS NOT TRUE THEN
    RETURN v_estado_resultado;
  END IF;

  INSERT INTO public.servicos (tipo, quantidade, usuario_id, usuario_nome, equipe_id, observacao, data_execucao, descricao)
  VALUES (v_tipo_servico, p_quantidade, v_tarefa.dono_id, v_usuario_nome, v_tarefa.equipe_id, NULL, NOW(), v_descricao_servico)
  RETURNING id INTO v_servico_id;

  WITH supervisores AS (
    SELECT DISTINCT u.id
    FROM public.users u
    WHERE u.ativo IS DISTINCT FROM FALSE
      AND u.id IS DISTINCT FROM v_user_id
      AND (
        (u.role = 'supervisor' AND u.equipe_id = v_tarefa.equipe_id)
        OR EXISTS (
          SELECT 1
          FROM public.usuario_funcoes_equipe ufe
          WHERE ufe.user_id = u.id
            AND ufe.equipe_id = v_tarefa.equipe_id
            AND ufe.funcao = 'supervisor'
            AND ufe.ativo = TRUE
        )
      )
  )
  INSERT INTO public.tarefa_notificacoes (tarefa_id, destinatario_id, remetente_id, tipo, dados)
  SELECT
    p_tarefa_id,
    supervisores.id,
    v_user_id,
    'tarefa_concluida',
    jsonb_build_object(
      'tarefa_titulo', v_tarefa.titulo,
      'remetente_nome', v_finalizador_nome,
      'estado_novo', 'concluida',
      'servico_id', v_servico_id,
      'tipo_servico', v_tipo_servico,
      'quantidade', p_quantidade
    )
  FROM supervisores;

  GET DIAGNOSTICS v_supervisores_notificados = ROW_COUNT;

  RETURN jsonb_build_object(
    'sucesso', true,
    'estado', 'concluida',
    'servico_id', v_servico_id,
    'tipo_servico', v_tipo_servico,
    'supervisores_notificados', v_supervisores_notificados,
    'mensagem', 'Tarefa concluída e serviço registrado com sucesso'
  );

EXCEPTION
  WHEN check_violation THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Dados inválidos: verifique tipo de serviço, notificação e quantidade.');
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao concluir tarefa e registrar serviço: ' || SQLERRM);
END;
$$;
GRANT EXECUTE ON FUNCTION public.concluir_tarefa_com_servico(UUID, TEXT, INTEGER) TO authenticated;
COMMENT ON FUNCTION public.concluir_tarefa_com_servico(UUID, TEXT, INTEGER) IS
  'Conclui tarefa, cria serviço equivalente e notifica supervisores da equipe da tarefa.';

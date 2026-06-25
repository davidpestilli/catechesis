ALTER TABLE public.chamados
ADD COLUMN IF NOT EXISTS ticket_id uuid;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chamados_ticket_id_fkey'
  ) THEN
    ALTER TABLE public.chamados
    ADD CONSTRAINT chamados_ticket_id_fkey
    FOREIGN KEY (ticket_id)
    REFERENCES public.tickets(id)
    ON DELETE SET NULL;
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_chamados_ticket_id
ON public.chamados (ticket_id)
WHERE ticket_id IS NOT NULL;
COMMENT ON COLUMN public.chamados.ticket_id
IS 'Vinculo opcional com o ticket do Distribuidor que originou este chamado registrado.';
UPDATE public.chamados AS ch
SET ticket_id = t.id
FROM public.tickets AS t
WHERE ch.ticket_id IS NULL
  AND ch.numero = t.numero_chamado;
CREATE OR REPLACE FUNCTION public.reativar_chamado_registrado(
  p_chamado_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_role public.user_role;
  v_user_equipe_id uuid;
  v_chamado public.chamados%ROWTYPE;
  v_ticket public.tickets%ROWTYPE;
  v_chamados_removidos integer := 0;
  v_has_fila_finalizacao_contexto boolean := false;
  v_sql text;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'usuario_nao_autenticado'
    );
  END IF;

  SELECT u.role, u.equipe_id
  INTO v_user_role, v_user_equipe_id
  FROM public.users AS u
  WHERE u.id = v_user_id
    AND u.ativo = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'usuario_sem_acesso'
    );
  END IF;

  SELECT *
  INTO v_chamado
  FROM public.chamados
  WHERE id = p_chamado_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'chamado_nao_encontrado'
    );
  END IF;

  IF COALESCE(v_chamado.solicitante, '') <> 'Sistema Distribuidor'
     OR COALESCE(v_chamado.funcionalidade, '') <> 'Distribuidor de Chamados' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'reativacao_disponivel_apenas_para_chamados_do_distribuidor'
    );
  END IF;

  IF v_user_role <> 'admin' AND v_user_equipe_id IS DISTINCT FROM v_chamado.equipe_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'sem_permissao'
    );
  END IF;

  IF v_chamado.ticket_id IS NOT NULL THEN
    SELECT *
    INTO v_ticket
    FROM public.tickets
    WHERE id = v_chamado.ticket_id
    FOR UPDATE;
  ELSE
    SELECT *
    INTO v_ticket
    FROM public.tickets
    WHERE numero_chamado = v_chamado.numero
    FOR UPDATE;
  END IF;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ticket_nao_encontrado'
    );
  END IF;

  IF v_ticket.status IS DISTINCT FROM 'finalizado' THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ticket_nao_esta_finalizado'
    );
  END IF;

  IF v_ticket.chamado_global_id IS NOT NULL
     OR EXISTS (
       SELECT 1
       FROM public.tickets_globais tg
       WHERE tg.ticket_id = v_ticket.id
     ) THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'ticket_anexado_a_global'
    );
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'tickets'
      AND column_name = 'fila_finalizacao_contexto'
  )
  INTO v_has_fila_finalizacao_contexto;

  v_sql := '
    UPDATE public.tickets
    SET
      usuario_atual = NULL,
      status = ''aguardando'',
      assigned_at = NULL,
      started_at = NULL,
      finished_at = NULL,
      mantido_por = NULL,
      mantido_at = NULL,
      suspenso = false,
      causa_suspensao = NULL,
      resposta_ia = NULL,
      resposta_ia_editado_por_id = NULL,
      resposta_ia_editado_por_nome = NULL,
      resposta_ia_editado_em = NULL,
      is_reopened = true,
      updated_at = NOW()';

  IF v_has_fila_finalizacao_contexto THEN
    v_sql := v_sql || ',
      fila_finalizacao_contexto = NULL';
  END IF;

  v_sql := v_sql || '
    WHERE id = $1';

  EXECUTE v_sql USING v_ticket.id;

  DELETE FROM public.chamados
  WHERE ticket_id = v_ticket.id
     OR (
       ticket_id IS NULL
       AND numero = v_ticket.numero_chamado
       AND COALESCE(solicitante, '') = 'Sistema Distribuidor'
       AND COALESCE(funcionalidade, '') = 'Distribuidor de Chamados'
       AND (
         v_chamado.equipe_id IS NULL
         OR equipe_id = v_chamado.equipe_id
       )
     );

  GET DIAGNOSTICS v_chamados_removidos = ROW_COUNT;

  IF v_chamados_removidos = 0 THEN
    DELETE FROM public.chamados
    WHERE id = p_chamado_id;

    GET DIAGNOSTICS v_chamados_removidos = ROW_COUNT;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'ticket_id', v_ticket.id,
    'numero_chamado', v_ticket.numero_chamado,
    'chamados_removidos', v_chamados_removidos,
    'message', 'Chamado reativado com sucesso'
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.reativar_chamado_registrado(uuid) TO authenticated;

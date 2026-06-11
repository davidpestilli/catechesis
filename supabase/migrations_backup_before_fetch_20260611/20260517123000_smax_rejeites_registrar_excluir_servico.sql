-- =====================================================================
-- SMAX Rejeites - Registrar servico e excluir rejeite
-- Cria uma acao atomica para registrar Resolucao de rejeites em
-- Outros Servicos e remover o ticket do snapshot atual.
-- =====================================================================

BEGIN;
CREATE OR REPLACE FUNCTION public.smax_rejeites_registrar_e_excluir(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_usuario_nome text;
  v_now timestamptz := now();
  v_descricao text;
  v_servico_id uuid;
  v_rejeite record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Rejeite obrigatorio';
  END IF;

  SELECT u.equipe_id,
         COALESCE(u.nome, u.email, 'Usuario')
    INTO v_user_equipe_id,
         v_usuario_nome
  FROM public.users u
  WHERE u.id = v_user_id;

  IF v_user_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao encontrado ou sem equipe';
  END IF;

  SELECT s.id,
         s.equipe_id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome AS mantido_por_nome,
         mantenedor.email AS mantido_por_email
    INTO v_rejeite
  FROM public.smax_rejeites_snapshot s
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.id = p_id
  FOR UPDATE OF s;

  IF v_rejeite.id IS NULL THEN
    RAISE EXCEPTION 'Rejeite nao encontrado';
  END IF;

  IF v_rejeite.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para registrar este rejeite';
  END IF;

  IF v_rejeite.mantido_por IS NOT NULL AND v_rejeite.mantido_por IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'mantido_por_outro',
      'id', v_rejeite.id,
      'ticket_numero', v_rejeite.ticket_numero,
      'mantido_por', v_rejeite.mantido_por,
      'mantido_at', v_rejeite.mantido_at,
      'mantido_por_nome', v_rejeite.mantido_por_nome,
      'mantido_por_email', v_rejeite.mantido_por_email
    );
  END IF;

  v_descricao := 'Respondi ao ticket ' || v_rejeite.ticket_numero;

  INSERT INTO public.servicos (
    tipo,
    quantidade,
    usuario_id,
    usuario_nome,
    equipe_id,
    observacao,
    data_execucao,
    descricao
  )
  VALUES (
    'analise_rejeites',
    1,
    v_user_id,
    v_usuario_nome,
    v_user_equipe_id,
    NULL,
    v_now,
    v_descricao
  )
  RETURNING id INTO v_servico_id;

  DELETE FROM public.smax_rejeites_snapshot s
  WHERE s.id = v_rejeite.id;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_rejeite.id,
    'ticket_numero', v_rejeite.ticket_numero,
    'servico_id', v_servico_id,
    'descricao', v_descricao,
    'data_execucao', v_now
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_rejeites_registrar_e_excluir(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_registrar_e_excluir(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

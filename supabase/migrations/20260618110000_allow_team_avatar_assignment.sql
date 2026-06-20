CREATE OR REPLACE FUNCTION public.definir_avatar_gamificacao_usuario(
  p_target_user_id uuid,
  p_gamificacao_avatar_id text DEFAULT NULL
)
RETURNS public.user_preferences
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $function$
DECLARE
  v_actor_id uuid;
  v_actor_role public.user_role;
  v_actor_equipe_id uuid;
  v_target_equipe_id uuid;
  v_result public.user_preferences;
BEGIN
  v_actor_id := auth.uid();

  IF v_actor_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado.';
  END IF;

  IF p_target_user_id IS NULL THEN
    RAISE EXCEPTION 'Membro de destino não informado.';
  END IF;

  IF p_target_user_id <> v_actor_id THEN
    SELECT u.role, u.equipe_id
    INTO v_actor_role, v_actor_equipe_id
    FROM public.users u
    WHERE u.id = v_actor_id
      AND (u.ativo IS NULL OR u.ativo = true);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Usuário atual não encontrado ou inativo.';
    END IF;

    SELECT u.equipe_id
    INTO v_target_equipe_id
    FROM public.users u
    WHERE u.id = p_target_user_id
      AND (u.ativo IS NULL OR u.ativo = true);

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Membro de destino não encontrado ou inativo.';
    END IF;

    IF v_actor_role NOT IN ('admin', 'supervisor', 'coordenador') THEN
      RAISE EXCEPTION 'Sem permissão para alterar o avatar de outro membro.';
    END IF;

    IF v_actor_equipe_id IS NULL OR v_actor_equipe_id <> v_target_equipe_id THEN
      RAISE EXCEPTION 'Só é permitido alterar o avatar de membros da mesma equipe.';
    END IF;
  END IF;

  INSERT INTO public.user_preferences (
    user_id,
    dark_mode,
    open_cards_in_new_tab,
    gamificacao_avatar_id
  )
  VALUES (
    p_target_user_id,
    false,
    false,
    p_gamificacao_avatar_id
  )
  ON CONFLICT (user_id)
  DO UPDATE SET
    gamificacao_avatar_id = EXCLUDED.gamificacao_avatar_id,
    updated_at = now()
  RETURNING * INTO v_result;

  RETURN v_result;
END;
$function$;
COMMENT ON FUNCTION public.definir_avatar_gamificacao_usuario(uuid, text)
IS 'Define o avatar da Arena para o próprio usuário ou, para perfis de liderança, para outro membro ativo da mesma equipe.';
GRANT EXECUTE ON FUNCTION public.definir_avatar_gamificacao_usuario(uuid, text) TO authenticated;

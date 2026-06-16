-- Corrige regressões introduzidas por migrations compartilhadas com o app Catechesis.
-- Problemas observados no gerenciador:
-- 1. public.is_admin() ficou ambígua após a criação de uma sobrecarga com argumento default.
-- 2. public.users passou a ter RLS de "próprio usuário ou admin", quebrando leituras
--    operacionais por equipe (ex.: reserva/vinculação no distribuidor).

-- 1) Normalizar as assinaturas de is_admin para evitar ambiguidade.
DROP POLICY IF EXISTS users_select_own_or_admin ON public.users;
DROP FUNCTION IF EXISTS public.is_admin(uuid);
CREATE OR REPLACE FUNCTION public.is_admin(p_user_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  select exists (
    select 1
    from public.users u
    where u.id = p_user_id
      and coalesce(u.ativo, true)
      and u.role = 'admin'
  );
$$;
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  select public.is_admin(auth.uid());
$$;
CREATE OR REPLACE FUNCTION public.is_boss()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
  select public.is_admin(auth.uid());
$$;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_admin(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_boss() TO authenticated;
COMMENT ON FUNCTION public.is_admin() IS
  'Verifica se o usuário autenticado possui role=admin na tabela public.users.';
COMMENT ON FUNCTION public.is_admin(uuid) IS
  'Verifica se o usuário informado possui role=admin na tabela public.users.';
COMMENT ON FUNCTION public.is_boss() IS
  'Alias retrocompatível de public.is_admin() para RPCs antigas do gerenciador.';
CREATE POLICY users_select_own_or_admin
ON public.users
FOR SELECT
TO authenticated
USING ((id = auth.uid()) OR public.is_admin(auth.uid()));
-- 2) Reabrir leitura operacional de usuários do gerenciador sem expor o escopo do Catechesis.
CREATE OR REPLACE FUNCTION public.can_read_operational_user(
  p_target_equipe_id uuid,
  p_target_setor_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_auth_user_id uuid := auth.uid();
  v_auth_equipe_id uuid;
  v_auth_setor_id uuid;
  v_auth_role public.user_role;
BEGIN
  IF v_auth_user_id IS NULL THEN
    RETURN false;
  END IF;

  IF public.is_admin(v_auth_user_id) THEN
    RETURN true;
  END IF;

  SELECT u.equipe_id, u.setor_id, u.role
    INTO v_auth_equipe_id, v_auth_setor_id, v_auth_role
  FROM public.users u
  WHERE u.id = v_auth_user_id;

  IF v_auth_equipe_id IS NOT NULL
     AND p_target_equipe_id IS NOT NULL
     AND v_auth_equipe_id = p_target_equipe_id THEN
    RETURN true;
  END IF;

  IF v_auth_role = 'coordenador'::public.user_role
     AND v_auth_setor_id IS NOT NULL
     AND p_target_setor_id IS NOT NULL
     AND v_auth_setor_id = p_target_setor_id THEN
    RETURN true;
  END IF;

  IF p_target_equipe_id IS NOT NULL AND EXISTS (
    SELECT 1
    FROM public.usuario_funcoes_equipe ufe
    WHERE ufe.user_id = v_auth_user_id
      AND ufe.equipe_id = p_target_equipe_id
      AND ufe.funcao = 'supervisor'
      AND coalesce(ufe.ativo, true)
  ) THEN
    RETURN true;
  END IF;

  RETURN false;
END;
$$;
GRANT EXECUTE ON FUNCTION public.can_read_operational_user(uuid, uuid) TO authenticated;
COMMENT ON FUNCTION public.can_read_operational_user(uuid, uuid) IS
  'Libera leitura de public.users no gerenciador para usuários da mesma equipe, coordenadores do mesmo setor e supervisorias adicionais.';
DROP POLICY IF EXISTS users_select_operational_scope ON public.users;
CREATE POLICY users_select_operational_scope
ON public.users
FOR SELECT
TO authenticated
USING (public.can_read_operational_user(equipe_id, setor_id));

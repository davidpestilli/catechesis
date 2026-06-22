-- ============================================================================
-- Hardening do perfil compartilhado de auth entre Gerenciador e Catechesis
-- Data: 2026-06-21
--
-- Objetivos:
-- 1. Impedir que metadata de auth sem contexto promova role global no gerenciador.
-- 2. Permitir promoção de role global apenas quando o fluxo declarar app_context=gerenciador.
-- 3. Manter o perfil base compartilhado (email/nome/ativo) sem misturar autorização por app.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.resolve_auth_profile_role(
  p_role text,
  p_app_context text DEFAULT NULL
)
RETURNS public.user_role
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_app_context text := lower(coalesce(trim(p_app_context), ''));
BEGIN
  IF v_app_context = 'gerenciador' THEN
    RETURN public.normalize_user_role(p_role);
  END IF;

  RETURN 'user'::public.user_role;
END;
$$;

COMMENT ON FUNCTION public.resolve_auth_profile_role(text, text) IS
  'Converte o role vindo do Auth em role base do gerenciador. Apenas eventos com app_context=gerenciador podem promover role global.';

CREATE OR REPLACE FUNCTION public.handle_auth_user_profile()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_nome text := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'nome'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
    ''
  );
  v_app_context text := lower(coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'app_context'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'app_code'), ''),
    ''
  ));
  v_requested_role public.user_role := public.normalize_user_role(new.raw_user_meta_data ->> 'role');
  v_role public.user_role := public.resolve_auth_profile_role(
    new.raw_user_meta_data ->> 'role',
    v_app_context
  );
BEGIN
  INSERT INTO public.users (id, email, nome, role, ativo)
  VALUES (
    new.id,
    lower(coalesce(new.email, '')),
    v_nome,
    v_role,
    true
  )
  ON CONFLICT (id) DO UPDATE
  SET email = excluded.email,
      nome = case
        when excluded.nome <> '' then excluded.nome
        else public.users.nome
      end,
      role = case
        when v_app_context = 'gerenciador' then
          case
            when public.users.role is null then excluded.role
            when public.users.role = 'catequista'::public.user_role then excluded.role
            when public.users.role = 'user'::public.user_role
              and v_requested_role in ('supervisor'::public.user_role, 'coordenador'::public.user_role, 'admin'::public.user_role)
              then excluded.role
            else public.users.role
          end
        else public.users.role
      end,
      ativo = coalesce(public.users.ativo, true),
      updated_at = timezone('utc', now());

  RETURN new;
END;
$$;

COMMENT ON FUNCTION public.handle_auth_user_profile() IS
  'Sincroniza perfil base de auth com public.users sem promover role global a partir de apps externos ao gerenciador.';

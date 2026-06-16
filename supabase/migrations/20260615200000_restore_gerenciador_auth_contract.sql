do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'user_role'
      and n.nspname = 'public'
  ) then
    create type public.user_role as enum (
      'user',
      'supervisor',
      'coordenador',
      'admin',
      'catequista'
    );
  else
    alter type public.user_role add value if not exists 'user';
    alter type public.user_role add value if not exists 'supervisor';
    alter type public.user_role add value if not exists 'coordenador';
    alter type public.user_role add value if not exists 'admin';
    alter type public.user_role add value if not exists 'catequista';
  end if;
end
$$;
create or replace function public.normalize_user_role(p_role text)
returns public.user_role
language plpgsql
immutable
as $$
declare
  v_role text := lower(coalesce(trim(p_role), ''));
begin
  if v_role = 'admin' then
    return 'admin'::public.user_role;
  end if;

  if v_role = 'supervisor' then
    return 'supervisor'::public.user_role;
  end if;

  if v_role = 'coordenador' then
    return 'coordenador'::public.user_role;
  end if;

  if v_role = 'catequista' then
    return 'user'::public.user_role;
  end if;

  return 'user'::public.user_role;
end;
$$;
create or replace function public.handle_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_nome text := coalesce(
    nullif(trim(new.raw_user_meta_data ->> 'nome'), ''),
    nullif(trim(new.raw_user_meta_data ->> 'name'), ''),
    ''
  );
  v_role public.user_role := public.normalize_user_role(new.raw_user_meta_data ->> 'role');
begin
  insert into public.users (id, email, nome, role, ativo)
  values (
    new.id,
    lower(coalesce(new.email, '')),
    v_nome,
    v_role,
    true
  )
  on conflict (id) do update
  set email = excluded.email,
      nome = case
        when excluded.nome <> '' then excluded.nome
        else public.users.nome
      end,
      role = case
        when public.users.role is null then excluded.role
        when public.users.role = 'catequista'::public.user_role then excluded.role
        else public.users.role
      end,
      ativo = coalesce(public.users.ativo, true),
      updated_at = timezone('utc', now());

  return new;
end;
$$;
drop trigger if exists on_auth_user_profile_created on auth.users;
create trigger on_auth_user_profile_created
after insert or update on auth.users
for each row
execute function public.handle_auth_user_profile();
update public.users
set role = 'user'::public.user_role,
    updated_at = timezone('utc', now())
where role = 'catequista'::public.user_role
  and (
    equipe_id is not null
    or setor_id is not null
    or lower(coalesce(email, '')) like '%@tjsp.jus.br'
    or exists (
      select 1
      from public.usuario_funcoes_equipe ufe
      where ufe.user_id = public.users.id
        and coalesce(ufe.ativo, true)
    )
  );

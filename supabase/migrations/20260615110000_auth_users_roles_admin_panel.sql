do $$
begin
  if not exists (
    select 1
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'user_role'
      and n.nspname = 'public'
  ) then
    create type public.user_role as enum ('admin', 'catequista');
  else
    alter type public.user_role add value if not exists 'admin';
    alter type public.user_role add value if not exists 'catequista';
  end if;
end
$$;

create table if not exists public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null,
  nome text not null default '',
  role public.user_role not null default 'catequista',
  ativo boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.users
  add column if not exists email text,
  add column if not exists nome text not null default '',
  add column if not exists role public.user_role not null default 'catequista',
  add column if not exists ativo boolean not null default true,
  add column if not exists created_at timestamptz not null default timezone('utc', now()),
  add column if not exists updated_at timestamptz not null default timezone('utc', now());

create unique index if not exists users_email_lower_idx
  on public.users (lower(email));

create or replace function public.set_row_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists trg_users_set_updated_at on public.users;
create trigger trg_users_set_updated_at
before update on public.users
for each row
execute function public.set_row_updated_at();

create or replace function public.normalize_user_role(p_role text)
returns public.user_role
language plpgsql
immutable
as $$
begin
  if lower(coalesce(trim(p_role), '')) = 'admin' then
    return 'admin'::public.user_role;
  end if;

  return 'catequista'::public.user_role;
end;
$$;

create or replace function public.bootstrap_catechesis_role()
returns public.user_role
language plpgsql
stable
as $$
begin
  if exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    join pg_namespace n on n.oid = t.typnamespace
    where t.typname = 'user_role'
      and n.nspname = 'public'
      and e.enumlabel = 'user'
  ) then
    return 'user'::public.user_role;
  end if;

  return 'catequista'::public.user_role;
end;
$$;

create or replace function public.handle_auth_user_profile()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_nome text := coalesce(trim(new.raw_user_meta_data ->> 'name'), '');
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
      role = coalesce(public.users.role, excluded.role),
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

create or replace function public.is_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.id = p_user_id
      and u.ativo = true
      and u.role = 'admin'
  );
$$;

create or replace function public.is_editor(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.users u
    where u.id = p_user_id
      and u.ativo = true
  );
$$;

alter table public.users enable row level security;

drop policy if exists "users_select_own_or_admin" on public.users;
create policy "users_select_own_or_admin"
on public.users
for select
to authenticated
using (id = auth.uid() or public.is_admin(auth.uid()));

drop policy if exists "encounters_write_authenticated" on public.encounters;
create policy "encounters_write_authenticated"
on public.encounters
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "assets_write_authenticated" on public.encounter_assets;
create policy "assets_write_authenticated"
on public.encounter_assets
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "quizzes_write_authenticated" on public.quizzes;
create policy "quizzes_write_authenticated"
on public.quizzes
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "questions_write_authenticated" on public.quiz_questions;
create policy "questions_write_authenticated"
on public.quiz_questions
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "options_write_authenticated" on public.quiz_options;
create policy "options_write_authenticated"
on public.quiz_options
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "articles_write_authenticated" on public.articles;
create policy "articles_write_authenticated"
on public.articles
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "settings_write_authenticated" on public.site_settings;
create policy "settings_write_authenticated"
on public.site_settings
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "class_groups_write_authenticated" on public.class_groups;
create policy "class_groups_write_authenticated"
on public.class_groups
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "useful_links_write_authenticated" on public.useful_links;
create policy "useful_links_write_authenticated"
on public.useful_links
for all
to authenticated
using (public.is_editor(auth.uid()))
with check (public.is_editor(auth.uid()));

drop policy if exists "catechesis_media_authenticated_write" on storage.objects;
create policy "catechesis_media_authenticated_write"
on storage.objects
for all
to authenticated
using (bucket_id = 'catechesis-media' and public.is_editor(auth.uid()))
with check (bucket_id = 'catechesis-media' and public.is_editor(auth.uid()));

alter table public.comments
  drop constraint if exists comments_author_kind_check,
  drop constraint if exists comments_subscription_email_check;

alter table public.comments
  add constraint comments_author_kind_check
  check (author_kind in ('guest', 'admin', 'catequista'));

alter table public.comments
  add constraint comments_subscription_email_check
  check (
    notify_replies = false
    or author_kind in ('admin', 'catequista')
    or author_email is not null
  );

insert into public.users (id, email, nome, role, ativo)
select
  au.id,
  lower(coalesce(au.email, '')),
  coalesce(trim(au.raw_user_meta_data ->> 'name'), ''),
  case
    when lower(coalesce(trim(au.raw_user_meta_data ->> 'role'), '')) = 'admin'
      then 'admin'::public.user_role
    else public.bootstrap_catechesis_role()
  end,
  true
from auth.users au
on conflict (id) do update
set email = excluded.email,
    nome = case
      when excluded.nome <> '' then excluded.nome
      else public.users.nome
    end,
    updated_at = timezone('utc', now());

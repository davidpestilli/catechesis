create table if not exists public.user_app_access (
  user_id uuid not null references public.users(id) on delete cascade,
  app_code text not null,
  role public.user_role not null default 'catequista',
  ativo boolean not null default true,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  primary key (user_id, app_code),
  constraint user_app_access_app_code_check check (char_length(trim(app_code)) > 0)
);
create index if not exists user_app_access_app_code_idx
  on public.user_app_access (app_code, created_at desc);
drop trigger if exists trg_user_app_access_set_updated_at on public.user_app_access;
create trigger trg_user_app_access_set_updated_at
before update on public.user_app_access
for each row
execute function public.set_row_updated_at();
create or replace function public.is_catequetico_admin(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_app_access access
    join public.users u on u.id = access.user_id
    where access.user_id = p_user_id
      and access.app_code = 'catequetico'
      and access.ativo = true
      and u.ativo = true
      and access.role = 'admin'
  );
$$;
create or replace function public.is_catequetico_editor(p_user_id uuid default auth.uid())
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.user_app_access access
    join public.users u on u.id = access.user_id
    where access.user_id = p_user_id
      and access.app_code = 'catequetico'
      and access.ativo = true
      and u.ativo = true
  );
$$;
grant execute on function public.is_catequetico_admin(uuid) to authenticated;
grant execute on function public.is_catequetico_editor(uuid) to authenticated;
alter table public.user_app_access enable row level security;
drop policy if exists "user_app_access_select_own_or_admin" on public.user_app_access;
create policy "user_app_access_select_own_or_admin"
on public.user_app_access
for select
to authenticated
using (user_id = auth.uid() or public.is_catequetico_admin(auth.uid()));
drop policy if exists "encounters_write_authenticated" on public.encounters;
drop policy if exists "encounters_write_catequetico_editor" on public.encounters;
create policy "encounters_write_catequetico_editor"
on public.encounters
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "assets_write_authenticated" on public.encounter_assets;
drop policy if exists "assets_write_catequetico_editor" on public.encounter_assets;
create policy "assets_write_catequetico_editor"
on public.encounter_assets
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "quizzes_write_authenticated" on public.quizzes;
drop policy if exists "quizzes_write_catequetico_editor" on public.quizzes;
create policy "quizzes_write_catequetico_editor"
on public.quizzes
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "questions_write_authenticated" on public.quiz_questions;
drop policy if exists "questions_write_catequetico_editor" on public.quiz_questions;
create policy "questions_write_catequetico_editor"
on public.quiz_questions
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "options_write_authenticated" on public.quiz_options;
drop policy if exists "options_write_catequetico_editor" on public.quiz_options;
create policy "options_write_catequetico_editor"
on public.quiz_options
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "articles_write_authenticated" on public.articles;
drop policy if exists "articles_write_catequetico_editor" on public.articles;
create policy "articles_write_catequetico_editor"
on public.articles
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "settings_write_authenticated" on public.site_settings;
drop policy if exists "settings_write_catequetico_editor" on public.site_settings;
create policy "settings_write_catequetico_editor"
on public.site_settings
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "class_groups_write_authenticated" on public.class_groups;
drop policy if exists "class_groups_write_catequetico_editor" on public.class_groups;
create policy "class_groups_write_catequetico_editor"
on public.class_groups
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "useful_links_write_authenticated" on public.useful_links;
drop policy if exists "useful_links_write_catequetico_editor" on public.useful_links;
create policy "useful_links_write_catequetico_editor"
on public.useful_links
for all
to authenticated
using (public.is_catequetico_editor(auth.uid()))
with check (public.is_catequetico_editor(auth.uid()));
drop policy if exists "catechesis_media_authenticated_write" on storage.objects;
drop policy if exists "catechesis_media_catequetico_write" on storage.objects;
create policy "catechesis_media_catequetico_write"
on storage.objects
for all
to authenticated
using (bucket_id = 'catechesis-media' and public.is_catequetico_editor(auth.uid()))
with check (bucket_id = 'catechesis-media' and public.is_catequetico_editor(auth.uid()));
insert into public.user_app_access (user_id, app_code, role, ativo)
select
  u.id,
  'catequetico',
  'admin'::public.user_role,
  true
from public.users u
where lower(u.email) = 'david.pestilli@outlook.com'
on conflict (user_id, app_code) do update
set role = excluded.role,
    ativo = true,
    updated_at = timezone('utc', now());

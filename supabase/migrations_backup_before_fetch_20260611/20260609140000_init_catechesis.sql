create extension if not exists "pgcrypto";

create table if not exists public.encounters (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  illuminated_title text default 'Encontros',
  summary text default '',
  theme text default '',
  audience text default '',
  order_index integer default 1,
  cover_image_url text,
  body_html text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.encounter_assets (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid not null references public.encounters(id) on delete cascade,
  title text not null,
  description text default '',
  kind text not null check (kind in ('summary', 'support')),
  view text not null check (view in ('image', 'pdf', 'html', 'video', 'link')),
  url text not null,
  downloadable boolean not null default true,
  order_index integer default 1,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.quizzes (
  id uuid primary key default gen_random_uuid(),
  encounter_id uuid not null unique references public.encounters(id) on delete cascade,
  title text not null,
  description text default '',
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.quiz_questions (
  id uuid primary key default gen_random_uuid(),
  quiz_id uuid not null references public.quizzes(id) on delete cascade,
  prompt text not null,
  explanation text default '',
  order_index integer default 1
);

create table if not exists public.quiz_options (
  id uuid primary key default gen_random_uuid(),
  question_id uuid not null references public.quiz_questions(id) on delete cascade,
  text text not null,
  is_correct boolean not null default false,
  order_index integer default 1
);

create table if not exists public.articles (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  title text not null,
  excerpt text default '',
  content_html text not null,
  tags text[] default '{}'::text[],
  cover_image_url text,
  featured boolean not null default false,
  published_at timestamptz not null default timezone('utc', now()),
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.site_settings (
  key text primary key,
  value jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.encounters enable row level security;
alter table public.encounter_assets enable row level security;
alter table public.quizzes enable row level security;
alter table public.quiz_questions enable row level security;
alter table public.quiz_options enable row level security;
alter table public.articles enable row level security;
alter table public.site_settings enable row level security;

drop policy if exists "encounters_public_read" on public.encounters;
create policy "encounters_public_read" on public.encounters for select using (true);
drop policy if exists "encounters_write_authenticated" on public.encounters;
create policy "encounters_write_authenticated" on public.encounters for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "assets_public_read" on public.encounter_assets;
create policy "assets_public_read" on public.encounter_assets for select using (true);
drop policy if exists "assets_write_authenticated" on public.encounter_assets;
create policy "assets_write_authenticated" on public.encounter_assets for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "quizzes_public_read" on public.quizzes;
create policy "quizzes_public_read" on public.quizzes for select using (true);
drop policy if exists "quizzes_write_authenticated" on public.quizzes;
create policy "quizzes_write_authenticated" on public.quizzes for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "questions_public_read" on public.quiz_questions;
create policy "questions_public_read" on public.quiz_questions for select using (true);
drop policy if exists "questions_write_authenticated" on public.quiz_questions;
create policy "questions_write_authenticated" on public.quiz_questions for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "options_public_read" on public.quiz_options;
create policy "options_public_read" on public.quiz_options for select using (true);
drop policy if exists "options_write_authenticated" on public.quiz_options;
create policy "options_write_authenticated" on public.quiz_options for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "articles_public_read" on public.articles;
create policy "articles_public_read" on public.articles for select using (true);
drop policy if exists "articles_write_authenticated" on public.articles;
create policy "articles_write_authenticated" on public.articles for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

drop policy if exists "settings_public_read" on public.site_settings;
create policy "settings_public_read" on public.site_settings for select using (true);
drop policy if exists "settings_write_authenticated" on public.site_settings;
create policy "settings_write_authenticated" on public.site_settings for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

insert into storage.buckets (id, name, public)
values ('catechesis-media', 'catechesis-media', true)
on conflict (id) do update set public = excluded.public;

drop policy if exists "catechesis_media_public_read" on storage.objects;
create policy "catechesis_media_public_read"
on storage.objects for select
using (bucket_id = 'catechesis-media');

drop policy if exists "catechesis_media_authenticated_write" on storage.objects;
create policy "catechesis_media_authenticated_write"
on storage.objects for all
using (bucket_id = 'catechesis-media' and auth.role() = 'authenticated')
with check (bucket_id = 'catechesis-media' and auth.role() = 'authenticated');

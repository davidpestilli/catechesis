alter table public.articles
add column if not exists category text not null default 'general';

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'articles_category_check'
      and conrelid = 'public.articles'::regclass
  ) then
    alter table public.articles
    add constraint articles_category_check
    check (category in ('general', 'saints-life'));
  end if;
end $$;

update public.articles
set category = 'general'
where category is null
   or category not in ('general', 'saints-life');

create table if not exists public.useful_links (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text default '',
  url text not null,
  tags text[] not null default '{}'::text[],
  cover_image_url text,
  order_index integer not null default 1,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.useful_links enable row level security;

drop policy if exists "useful_links_public_read" on public.useful_links;
create policy "useful_links_public_read" on public.useful_links for select using (true);

drop policy if exists "useful_links_write_authenticated" on public.useful_links;
create policy "useful_links_write_authenticated"
on public.useful_links
for all
using (auth.role() = 'authenticated')
with check (auth.role() = 'authenticated');

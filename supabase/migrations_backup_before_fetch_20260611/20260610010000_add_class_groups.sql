create table if not exists public.class_groups (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null unique,
  battle_cry text default '',
  order_index integer default 1,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.encounters
add column if not exists class_group_id uuid references public.class_groups(id);

with distinct_groups as (
  select
    coalesce(nullif(trim(audience), ''), 'Turma geral') as group_name,
    row_number() over (order by coalesce(nullif(trim(audience), ''), 'Turma geral')) as group_order
  from public.encounters
  group by coalesce(nullif(trim(audience), ''), 'Turma geral')
)
insert into public.class_groups (slug, name, battle_cry, order_index)
select
  coalesce(
    nullif(
      regexp_replace(
        lower(regexp_replace(group_name, '[^[:alnum:]]+', '-', 'g')),
        '(^-|-$)',
        '',
        'g'
      ),
      ''
    ),
    'turma-geral'
  ),
  group_name,
  '',
  group_order
from distinct_groups
on conflict (name) do nothing;

update public.encounters as encounter
set class_group_id = class_groups.id
from public.class_groups as class_groups
where encounter.class_group_id is null
  and class_groups.name = coalesce(nullif(trim(encounter.audience), ''), 'Turma geral');

update public.encounters
set class_group_id = (
  select id
  from public.class_groups
  order by order_index, created_at
  limit 1
)
where class_group_id is null;

alter table public.encounters
alter column class_group_id set not null;

alter table public.class_groups enable row level security;

drop policy if exists "class_groups_public_read" on public.class_groups;
create policy "class_groups_public_read" on public.class_groups for select using (true);
drop policy if exists "class_groups_write_authenticated" on public.class_groups;
create policy "class_groups_write_authenticated" on public.class_groups for all using (auth.role() = 'authenticated') with check (auth.role() = 'authenticated');

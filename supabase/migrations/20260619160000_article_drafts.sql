alter table public.articles
add column if not exists status text not null default 'published',
add column if not exists author_user_id uuid references public.users(id) on delete set null;

do $$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'articles_status_check'
      and conrelid = 'public.articles'::regclass
  ) then
    alter table public.articles
    add constraint articles_status_check
    check (status in ('draft', 'published'));
  end if;
end $$;

update public.articles
set status = 'published'
where status is null
   or status not in ('draft', 'published');

alter table public.articles
alter column published_at drop not null;

drop policy if exists "articles_public_read" on public.articles;
create policy "articles_public_read"
on public.articles
for select
using (status = 'published');

drop policy if exists "articles_editor_select" on public.articles;
create policy "articles_editor_select"
on public.articles
for select
to authenticated
using (
  public.is_catequetico_admin(auth.uid())
  or (
    public.is_catequetico_editor(auth.uid())
    and (status = 'published' or author_user_id = auth.uid())
  )
);

drop policy if exists "articles_write_authenticated" on public.articles;
drop policy if exists "articles_write_catequetico_editor" on public.articles;
drop policy if exists "articles_admin_manage" on public.articles;
create policy "articles_admin_manage"
on public.articles
for all
to authenticated
using (public.is_catequetico_admin(auth.uid()))
with check (public.is_catequetico_admin(auth.uid()));

drop policy if exists "articles_editor_insert_draft" on public.articles;
create policy "articles_editor_insert_draft"
on public.articles
for insert
to authenticated
with check (
  public.is_catequetico_editor(auth.uid())
  and author_user_id = auth.uid()
  and status = 'draft'
);

drop policy if exists "articles_editor_update_own_draft" on public.articles;
create policy "articles_editor_update_own_draft"
on public.articles
for update
to authenticated
using (
  public.is_catequetico_editor(auth.uid())
  and author_user_id = auth.uid()
  and status = 'draft'
)
with check (
  public.is_catequetico_editor(auth.uid())
  and author_user_id = auth.uid()
  and status = 'draft'
);

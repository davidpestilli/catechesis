create or replace view public.comments_public
with (security_invoker = true) as
select
  id,
  content_type,
  content_id,
  parent_comment_id,
  root_comment_id,
  author_kind,
  author_name,
  body,
  notify_replies,
  created_at,
  updated_at
from public.comments;

grant select on public.comments_public to anon, authenticated, service_role;

revoke select on public.comments from anon, authenticated;

create table if not exists public.comments (
  id uuid primary key,
  content_type text not null check (content_type in ('article', 'encounter')),
  content_id uuid not null,
  parent_comment_id uuid references public.comments(id) on delete cascade,
  root_comment_id uuid not null references public.comments(id) on delete cascade deferrable initially deferred,
  author_kind text not null check (author_kind in ('guest', 'admin')),
  admin_user_id uuid,
  author_name text not null check (char_length(trim(author_name)) between 1 and 80),
  author_email text,
  body text not null check (char_length(trim(body)) between 1 and 5000),
  notify_replies boolean not null default false,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now()),
  constraint comments_subscription_email_check check (
    notify_replies = false
    or author_kind = 'admin'
    or author_email is not null
  )
);

create table if not exists public.comment_subscriptions (
  id uuid primary key default gen_random_uuid(),
  root_comment_id uuid not null references public.comments(id) on delete cascade,
  email text not null,
  subscriber_name text not null default '',
  source text not null check (source in ('opt_in', 'admin_auto')),
  unsubscribe_token uuid not null default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  unsubscribed_at timestamptz
);

create table if not exists public.comment_events (
  id uuid primary key default gen_random_uuid(),
  comment_id uuid references public.comments(id) on delete cascade,
  root_comment_id uuid references public.comments(id) on delete cascade,
  event_type text not null check (
    event_type in (
      'comment_created',
      'subscription_created',
      'email_queued',
      'email_sent',
      'email_failed',
      'email_deferred',
      'unsubscribe'
    )
  ),
  recipient_email text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists comments_content_idx
  on public.comments (content_type, content_id, created_at desc);

create index if not exists comments_root_idx
  on public.comments (root_comment_id, created_at asc);

create index if not exists comments_parent_idx
  on public.comments (parent_comment_id);

create unique index if not exists comment_subscriptions_active_email_idx
  on public.comment_subscriptions (root_comment_id, lower(email))
  where unsubscribed_at is null;

create unique index if not exists comment_subscriptions_token_idx
  on public.comment_subscriptions (unsubscribe_token);

alter table public.comments enable row level security;
alter table public.comment_subscriptions enable row level security;
alter table public.comment_events enable row level security;

drop policy if exists "comments_public_read" on public.comments;
create policy "comments_public_read"
on public.comments for select
using (true);

drop policy if exists "comment_subscriptions_no_public_read" on public.comment_subscriptions;
create policy "comment_subscriptions_no_public_read"
on public.comment_subscriptions for select
using (false);

drop policy if exists "comment_events_no_public_read" on public.comment_events;
create policy "comment_events_no_public_read"
on public.comment_events for select
using (false);

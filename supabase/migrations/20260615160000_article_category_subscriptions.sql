create table if not exists public.article_category_subscriptions (
  id uuid primary key default gen_random_uuid(),
  category text not null check (category in ('general', 'saints-life')),
  email text not null,
  subscriber_name text not null default '',
  source text not null default 'manual_form' check (source in ('manual_form')),
  unsubscribe_token uuid not null default gen_random_uuid(),
  created_at timestamptz not null default timezone('utc', now()),
  unsubscribed_at timestamptz
);
create table if not exists public.article_notification_events (
  id uuid primary key default gen_random_uuid(),
  article_id uuid references public.articles(id) on delete cascade,
  subscription_id uuid references public.article_category_subscriptions(id) on delete cascade,
  category text not null check (category in ('general', 'saints-life')),
  event_type text not null check (
    event_type in (
      'subscription_created',
      'already_subscribed',
      'publication_created',
      'email_queued',
      'email_failed',
      'unsubscribe'
    )
  ),
  recipient_email text,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);
create unique index if not exists article_category_subscriptions_active_email_idx
  on public.article_category_subscriptions (category, lower(email))
  where unsubscribed_at is null;
create unique index if not exists article_category_subscriptions_token_idx
  on public.article_category_subscriptions (unsubscribe_token);
create index if not exists article_notification_events_article_idx
  on public.article_notification_events (article_id, created_at desc);
create index if not exists article_notification_events_category_idx
  on public.article_notification_events (category, created_at desc);
alter table public.article_category_subscriptions enable row level security;
alter table public.article_notification_events enable row level security;
drop policy if exists "article_category_subscriptions_no_public_read" on public.article_category_subscriptions;
create policy "article_category_subscriptions_no_public_read"
on public.article_category_subscriptions for select
using (false);
drop policy if exists "article_notification_events_no_public_read" on public.article_notification_events;
create policy "article_notification_events_no_public_read"
on public.article_notification_events for select
using (false);

alter table public.articles
drop constraint if exists articles_category_check;
alter table public.articles
add constraint articles_category_check
check (category in ('general', 'saints-life', 'biblical', 'catechism'));
alter table public.article_category_subscriptions
drop constraint if exists article_category_subscriptions_category_check;
alter table public.article_category_subscriptions
add constraint article_category_subscriptions_category_check
check (category in ('general', 'saints-life', 'biblical', 'catechism'));
alter table public.article_notification_events
drop constraint if exists article_notification_events_category_check;
alter table public.article_notification_events
add constraint article_notification_events_category_check
check (category in ('general', 'saints-life', 'biblical', 'catechism'));

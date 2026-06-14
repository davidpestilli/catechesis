alter table public.articles
add column if not exists card_image_url text,
add column if not exists sources text[] default '{}'::text[];

update public.articles
set
  card_image_url = coalesce(card_image_url, cover_image_url),
  sources = coalesce(sources, '{}'::text[])
where card_image_url is null
   or sources is null;

alter table public.articles
alter column sources set default '{}'::text[],
alter column sources set not null;

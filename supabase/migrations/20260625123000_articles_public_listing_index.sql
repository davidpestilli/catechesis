create index if not exists articles_published_listing_idx
  on public.articles (published_at desc)
  where status = 'published';

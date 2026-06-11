alter table public.encounter_assets
add column if not exists material_category text
check (material_category in ('video', 'image', 'text', 'website', 'book'));

update public.encounter_assets
set material_category = 'website'
where kind = 'support'
  and view = 'link'
  and material_category is null;

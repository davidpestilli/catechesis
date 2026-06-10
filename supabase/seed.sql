insert into public.site_settings (key, value)
values (
  'home',
  '{
    "heroVideoUrl": "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerMeltdowns.mp4",
    "heroPosterUrl": "https://images.unsplash.com/photo-1519494026892-80bbd2d6fd0d?auto=format&fit=crop&w=1200&q=80",
    "homeLead": ""
  }'::jsonb
)
on conflict (key) do update set value = excluded.value;

insert into public.class_groups (
  id,
  slug,
  name,
  battle_cry,
  order_index
)
values (
  '99999999-9999-9999-9999-999999999991',
  'turma-sao-pedro',
  'Turma Sao Pedro',
  'Firmes na fe, alegres na missao.',
  1
),
(
  '99999999-9999-9999-9999-999999999992',
  'turma-sao-paulo',
  'Turma Sao Paulo',
  'Anunciar, servir e caminhar juntos.',
  2
)
on conflict (id) do update
set
  slug = excluded.slug,
  name = excluded.name,
  battle_cry = excluded.battle_cry,
  order_index = excluded.order_index,
  updated_at = timezone('utc', now());

insert into public.encounters (
  id,
  class_group_id,
  slug,
  title,
  illuminated_title,
  summary,
  theme,
  audience,
  order_index,
  cover_image_url,
  body_html
)
values (
  '11111111-1111-1111-1111-111111111111',
  '99999999-9999-9999-9999-999999999991',
  'o-chamado-da-fe',
  'O Chamado da Fe',
  'Encontros',
  'Primeiro encontro sobre acolhida, sentido da catequese e caminhada em comunidade.',
  'Introducao a catequese',
  'Catequizandos iniciantes',
  1,
  'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
  '<h2>Boas-vindas</h2><p>Este encontro introduz a caminhada catequetica como resposta ao amor de Deus, vivida em comunidade.</p>'
),
(
  '22222222-2222-2222-2222-222222222222',
  '99999999-9999-9999-9999-999999999992',
  'a-palavra-que-ilumina',
  'A Palavra que Ilumina',
  'Encontros',
  'Encontro sobre a escuta da Palavra, meditacao e compromisso.',
  'Biblia e vida',
  'Turmas intermediarias',
  2,
  'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=1200&q=80',
  '<h2>Escuta e resposta</h2><p>A Palavra ilumina a vida e abre caminhos de conversao e partilha.</p>'
)
on conflict (id) do update
set
  class_group_id = excluded.class_group_id,
  slug = excluded.slug,
  title = excluded.title,
  illuminated_title = excluded.illuminated_title,
  summary = excluded.summary,
  theme = excluded.theme,
  audience = excluded.audience,
  order_index = excluded.order_index,
  cover_image_url = excluded.cover_image_url,
  body_html = excluded.body_html,
  updated_at = timezone('utc', now());

insert into public.encounter_assets (
  id,
  encounter_id,
  title,
  description,
  kind,
  view,
  url,
  downloadable,
  order_index
)
values (
  '33333333-3333-3333-3333-333333333333',
  '11111111-1111-1111-1111-111111111111',
  'Resumo do Encontro',
  'PDF com a estrutura principal do encontro.',
  'summary',
  'pdf',
  'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  true,
  1
),
(
  '44444444-4444-4444-4444-444444444444',
  '11111111-1111-1111-1111-111111111111',
  'Imagem de apoio',
  'Imagem contemplativa para o momento de partilha.',
  'support',
  'image',
  'https://images.unsplash.com/photo-1529078155058-5d716f45d604?auto=format&fit=crop&w=1200&q=80',
  true,
  2
)
on conflict (id) do update
set
  encounter_id = excluded.encounter_id,
  title = excluded.title,
  description = excluded.description,
  kind = excluded.kind,
  view = excluded.view,
  url = excluded.url,
  downloadable = excluded.downloadable,
  order_index = excluded.order_index;

insert into public.quizzes (id, encounter_id, title, description)
values (
  '55555555-5555-5555-5555-555555555555',
  '11111111-1111-1111-1111-111111111111',
  'Quiz do Encontro 1',
  'Revise as ideias centrais trabalhadas no encontro.'
)
on conflict (id) do update
set
  encounter_id = excluded.encounter_id,
  title = excluded.title,
  description = excluded.description;

insert into public.quiz_questions (id, quiz_id, prompt, explanation, order_index)
values (
  '66666666-6666-6666-6666-666666666666',
  '55555555-5555-5555-5555-555555555555',
  'Qual e a proposta principal deste primeiro encontro?',
  'O encontro apresenta a catequese como caminho de fe vivido em comunidade e resposta ao amor de Deus.',
  1
)
on conflict (id) do update
set
  quiz_id = excluded.quiz_id,
  prompt = excluded.prompt,
  explanation = excluded.explanation,
  order_index = excluded.order_index;

insert into public.quiz_options (id, question_id, text, is_correct, order_index)
values
  ('77777777-7777-7777-7777-777777777771', '66666666-6666-6666-6666-666666666666', 'Memorizar datas historicas isoladas.', false, 1),
  ('77777777-7777-7777-7777-777777777772', '66666666-6666-6666-6666-666666666666', 'Reconhecer a catequese como caminhada de fe em comunidade.', true, 2),
  ('77777777-7777-7777-7777-777777777773', '66666666-6666-6666-6666-666666666666', 'Substituir a vida comunitaria por estudo individual.', false, 3),
  ('77777777-7777-7777-7777-777777777774', '66666666-6666-6666-6666-666666666666', 'Tratar somente de regras disciplinares.', false, 4),
  ('77777777-7777-7777-7777-777777777775', '66666666-6666-6666-6666-666666666666', 'Encerrar a preparacao liturgica do grupo.', false, 5)
on conflict (id) do update
set
  question_id = excluded.question_id,
  text = excluded.text,
  is_correct = excluded.is_correct,
  order_index = excluded.order_index;

insert into public.articles (
  id,
  slug,
  title,
  excerpt,
  content_html,
  tags,
  cover_image_url,
  featured
)
values (
  '88888888-8888-8888-8888-888888888888',
  'como-organizar-um-encontro-catequetico',
  'Como organizar um encontro catequetico',
  'Guia breve para preparar acolhida, Palavra, dinamica e envio com intencionalidade pastoral.',
  '<h2>Antes do encontro</h2><p>Planeje o objetivo, a passagem biblica central e o gesto concreto do dia.</p><h2>Durante o encontro</h2><p>Varie os ritmos entre escuta, conversa, silencio e celebracao.</p><blockquote>A catequese floresce quando o conteudo encontra a vida.</blockquote>',
  array['metodologia', 'planejamento', 'catequese'],
  'https://images.unsplash.com/photo-1517486808906-6ca8b3f04846?auto=format&fit=crop&w=1200&q=80',
  true
)
on conflict (id) do update
set
  slug = excluded.slug,
  title = excluded.title,
  excerpt = excluded.excerpt,
  content_html = excluded.content_html,
  tags = excluded.tags,
  cover_image_url = excluded.cover_image_url,
  featured = excluded.featured,
  updated_at = timezone('utc', now());

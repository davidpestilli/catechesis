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
  cover_image_url,
  order_index
)
values (
  '99999999-9999-9999-9999-999999999991',
  'turma-sao-pedro',
  'Turma Sao Pedro',
  'Firmes na fe, alegres na missao.',
  'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
  1
),
(
  '99999999-9999-9999-9999-999999999992',
  'turma-sao-paulo',
  'Turma Sao Paulo',
  'Anunciar, servir e caminhar juntos.',
  'https://images.unsplash.com/photo-1507692049790-de58290a4334?auto=format&fit=crop&w=1200&q=80',
  2
)
on conflict (id) do update
set
  slug = excluded.slug,
  name = excluded.name,
  battle_cry = excluded.battle_cry,
  cover_image_url = excluded.cover_image_url,
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
),
(
  '22222222-2222-2222-2222-222222222223',
  '99999999-9999-9999-9999-999999999991',
  'jesus-nos-chama-pelo-nome',
  'Jesus nos Chama pelo Nome',
  'Encontros',
  'Encontro sobre vocacao pessoal, escuta do Evangelho e resposta concreta.',
  'Identidade e vocacao',
  'Catequizandos iniciantes',
  2,
  'https://images.unsplash.com/photo-1500530855697-b586d89ba3ee?auto=format&fit=crop&w=1200&q=80',
  '<h2>Chamado pessoal</h2><p>Jesus conhece cada pessoa pelo nome e chama para uma resposta livre, concreta e comunitaria.</p>'
),
(
  '22222222-2222-2222-2222-222222222224',
  '99999999-9999-9999-9999-999999999992',
  'celebrar-e-fazer-memoria',
  'Celebrar e Fazer Memoria',
  'Encontros',
  'Encontro sobre celebracao, memoria da fe e experiencia comunitaria.',
  'Liturgia e comunidade',
  'Turmas intermediarias',
  2,
  'https://images.unsplash.com/photo-1464638681273-0962e9b53566?auto=format&fit=crop&w=1200&q=80',
  '<h2>Memoria viva</h2><p>A celebracao ajuda a comunidade a recordar a acao de Deus e responder com louvor, escuta e compromisso.</p>'
),
(
  '22222222-2222-2222-2222-222222222225',
  '99999999-9999-9999-9999-999999999992',
  'servico-e-envio',
  'Servico e Envio',
  'Encontros',
  'Encontro sobre caridade, servico e compromisso vivido durante a semana.',
  'Missao crista',
  'Turmas intermediarias',
  3,
  'https://images.unsplash.com/photo-1469571486292-b53601020f35?auto=format&fit=crop&w=1200&q=80',
  '<h2>Fe que se torna gesto</h2><p>O encontro termina com um compromisso simples para a semana e com a recordacao de que a catequese continua fora da sala.</p>'
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
  material_category,
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
  null,
  true,
  1
),
(
  '44444444-4444-4444-4444-444444444444',
  '11111111-1111-1111-1111-111111111111',
  'Video de acolhida',
  'Breve introducao em video para abrir a conversa do encontro.',
  'support',
  'link',
  'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
  'video',
  false,
  2
),
(
  '44444444-4444-4444-4444-444444444448',
  '11111111-1111-1111-1111-111111111111',
  'Texto sobre catequese e comunidade',
  'Leitura curta para aprofundar a ideia de caminhada comunitaria.',
  'support',
  'link',
  'https://www.vatican.va',
  'text',
  false,
  3
),
(
  '44444444-4444-4444-4444-444444444449',
  '11111111-1111-1111-1111-111111111111',
  'Imagem simbolica da Palavra',
  'Referencia visual para projetar ou compartilhar com a turma.',
  'support',
  'link',
  'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
  'image',
  false,
  4
),
(
  '44444444-4444-4444-4444-444444444445',
  '22222222-2222-2222-2222-222222222223',
  'Roteiro do catequista',
  'Sequencia sugerida para acolhida, Palavra e dinamica.',
  'summary',
  'pdf',
  'https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf',
  null,
  true,
  1
),
(
  '44444444-4444-4444-4444-444444444446',
  '22222222-2222-2222-2222-222222222224',
  'Esquema celebrativo',
  'Sugestao simples para conduzir um momento orante com a turma.',
  'summary',
  'html',
  '<h2>Momento celebrativo</h2><p>Inicie com um refrao, proclame a Palavra, abra uma breve partilha e conclua com uma prece comum.</p>',
  null,
  false,
  1
),
(
  '44444444-4444-4444-4444-444444444447',
  '22222222-2222-2222-2222-222222222225',
  'Proposta de gesto concreto',
  'Sugestoes de servico para viver durante a semana.',
  'support',
  'link',
  'https://www.vatican.va',
  'website',
  false,
  1
),
(
  '44444444-4444-4444-4444-444444444450',
  '22222222-2222-2222-2222-222222222225',
  'Livro para aprofundamento',
  'Referencia bibliografica para continuar o estudo sobre missao e servico.',
  'support',
  'link',
  'https://books.google.com',
  'book',
  false,
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
  material_category = excluded.material_category,
  downloadable = excluded.downloadable,
  order_index = excluded.order_index;

insert into public.quizzes (id, encounter_id, title, description)
values (
  '55555555-5555-5555-5555-555555555555',
  '11111111-1111-1111-1111-111111111111',
  'Quiz do Encontro 1',
  'Revise as ideias centrais trabalhadas no encontro.'
),
(
  '55555555-5555-5555-5555-555555555556',
  '22222222-2222-2222-2222-222222222223',
  'Quiz do chamado',
  'Revise os pontos principais sobre vocacao e resposta.'
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
),
(
  '66666666-6666-6666-6666-666666666667',
  '55555555-5555-5555-5555-555555555556',
  'O que significa dizer que Jesus chama cada pessoa pelo nome?',
  'Significa que a fe toca a historia pessoal de cada catequizando e pede uma resposta concreta.',
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
  ('77777777-7777-7777-7777-777777777775', '66666666-6666-6666-6666-666666666666', 'Encerrar a preparacao liturgica do grupo.', false, 5),
  ('77777777-7777-7777-7777-777777777776', '66666666-6666-6666-6666-666666666667', 'Que a fe dispensa a comunidade.', false, 1),
  ('77777777-7777-7777-7777-777777777777', '66666666-6666-6666-6666-666666666667', 'Que o chamado de Deus alcanca a historia pessoal de cada um.', true, 2),
  ('77777777-7777-7777-7777-777777777778', '66666666-6666-6666-6666-666666666667', 'Que somente os catequistas sao chamados.', false, 3),
  ('77777777-7777-7777-7777-777777777779', '66666666-6666-6666-6666-666666666667', 'Que basta decorar conteudos.', false, 4),
  ('77777777-7777-7777-7777-777777777780', '66666666-6666-6666-6666-666666666667', 'Que nao ha necessidade de resposta.', false, 5)
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
  category,
  tags,
  cover_image_url,
  card_image_url,
  sources,
  featured
)
values (
  '88888888-8888-8888-8888-888888888888',
  'como-organizar-um-encontro-catequetico',
  'Como organizar um encontro catequetico',
  'Guia breve para preparar acolhida, Palavra, dinamica e envio com intencionalidade pastoral.',
  '<h2>Antes do encontro</h2><p>Planeje o objetivo, a passagem biblica central e o gesto concreto do dia.</p><h2>Durante o encontro</h2><p>Varie os ritmos entre escuta, conversa, silencio e celebracao.</p><blockquote>A catequese floresce quando o conteudo encontra a vida.</blockquote>',
  'general',
  array['metodologia', 'planejamento', 'catequese'],
  'https://images.unsplash.com/photo-1517486808906-6ca8b3f04846?auto=format&fit=crop&w=1200&q=80',
  'https://images.unsplash.com/photo-1517486808906-6ca8b3f04846?auto=format&fit=crop&w=1200&q=80',
  array['Diretorio Nacional de Catequese', 'https://www.vatican.va'],
  true
),
(
  '88888888-8888-8888-8888-888888888889',
  'sao-francisco-de-assis-e-a-alegria-do-evangelho',
  'Sao Francisco de Assis e a alegria do Evangelho',
  'Uma leitura breve sobre simplicidade, louvor e testemunho a partir da vida de Sao Francisco.',
  '<h2>Um coracao livre</h2><p>Sao Francisco descobriu no Evangelho um caminho de liberdade, pobreza e fraternidade.</p><h2>Para a catequese</h2><p>Sua vida ajuda a aproximar os catequizandos da alegria simples de seguir Jesus com inteireza.</p>',
  'saints-life',
  array['santos', 'testemunho', 'espiritualidade'],
  'https://images.unsplash.com/photo-1520637836862-4d197d17c11a?auto=format&fit=crop&w=1200&q=80',
  'https://images.unsplash.com/photo-1520637836862-4d197d17c11a?auto=format&fit=crop&w=1200&q=80',
  array['https://www.vatican.va'],
  false
)
on conflict (id) do update
set
  slug = excluded.slug,
  title = excluded.title,
  excerpt = excluded.excerpt,
  content_html = excluded.content_html,
  category = excluded.category,
  tags = excluded.tags,
  cover_image_url = excluded.cover_image_url,
  card_image_url = excluded.card_image_url,
  sources = excluded.sources,
  featured = excluded.featured,
  updated_at = timezone('utc', now());

insert into public.useful_links (
  id,
  title,
  description,
  url,
  tags,
  cover_image_url,
  order_index
)
values (
  '99999999-8888-7777-6666-555555555551',
  'Portal do Vaticano',
  'Documentos, noticias e textos oficiais para consulta e aprofundamento.',
  'https://www.vatican.va',
  array['igreja', 'documentos', 'vaticano'],
  'https://images.unsplash.com/photo-1531572753322-ad063cecc140?auto=format&fit=crop&w=1200&q=80',
  1
),
(
  '99999999-8888-7777-6666-555555555552',
  'Biblia Online - CNBB',
  'Leitura e pesquisa das Sagradas Escrituras em ambiente digital.',
  'https://www.bibliacatolica.com.br',
  array['biblia', 'leitura', 'estudo'],
  'https://images.unsplash.com/photo-1504052434569-70ad5836ab65?auto=format&fit=crop&w=1200&q=80',
  2
)
on conflict (id) do update
set
  title = excluded.title,
  description = excluded.description,
  url = excluded.url,
  tags = excluded.tags,
  cover_image_url = excluded.cover_image_url,
  order_index = excluded.order_index,
  updated_at = timezone('utc', now());

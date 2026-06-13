# Catequético

Projeto base para um site de apoio ao ensino de catequese com:

- `Vite + React + TypeScript`
- `Tailwind CSS 3.3.5`
- `React Router` com `HashRouter` para GitHub Pages
- `TanStack Query`
- componentes no estilo `shadcn/ui`
- `Supabase` para auth, banco e storage
- `Cloudflare Worker` para proxy de media/configuracoes

## Estrutura

- `src/`: frontend React
- `supabase/`: configuracao local, migrations e seed
- `worker/`: proxy em Cloudflare Workers
- `.github/workflows/deploy.yml`: deploy automatico no GitHub Pages

## Scripts

- `npm run dev`: sobe o frontend em `http://localhost:5173`
- `npm run build`: typecheck + build
- `npm run cf:dev`: sobe o worker local em `http://127.0.0.1:8787`
- `npm run cf:deploy`: publica o worker no Cloudflare

## Ambiente

- Frontend:
  `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_CLOUDFLARE_WORKER_URL`, `VITE_SITE_NAME`
- Worker:
  `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, `VITE_SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_NOTIFICATION_EMAIL`, `APP_BASE_URL`, `SITE_NAME`, `ZEPTO_MAIL_FROM_EMAIL`, `ZEPTO_MAIL_FROM_NAME`

## Login administrativo de teste

Enquanto o fluxo definitivo de usuarios nao e refinado, o projeto esta preparado para autenticar via Supabase Auth com o usuario administrativo criado no ambiente remoto.

## Observacoes de arquitetura

- O `service_role` deve ficar apenas no Worker e/ou em ambiente servidor.
- A `anon key` do Supabase e, por padrao, uma credencial publica de cliente. O projeto ja deixa o Worker preparado para proxiar media e downloads sem expor a `service_role`.
- O GitHub Pages faz apenas o deploy estatico do frontend. O Worker deve ser publicado separadamente no Cloudflare e a URL dele precisa entrar em `VITE_CLOUDFLARE_WORKER_URL`.
- Os comentarios publicos usam leitura direta do Supabase e escrita via Worker para concentrar regras de assinatura, eventos e notificacoes futuras.
- O envio de email de comentarios usa RPCs do Supabase no estilo do `gerenciador-chamados` (`enviar_email_zeptomail` / `enviar_emails_zeptomail_lote`). A migration correspondente precisa receber a API key real do ZeptoMail antes de ser aplicada em producao.

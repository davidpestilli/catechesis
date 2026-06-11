-- =====================================================
-- Usuario sistema em public.users
-- Evita 406 em consultas .single() quando referencias usam o
-- usuario sistema 00000000-0000-0000-0000-000000000001.
-- =====================================================

BEGIN;
INSERT INTO public.users (id, email, nome, role, ativo)
VALUES (
  '00000000-0000-0000-0000-000000000001'::uuid,
  'sistema@gerenciador.local',
  'Sistema',
  'admin'::user_role,
  true
)
ON CONFLICT (id) DO UPDATE
SET email = EXCLUDED.email,
    nome = EXCLUDED.nome,
    ativo = true;
COMMIT;

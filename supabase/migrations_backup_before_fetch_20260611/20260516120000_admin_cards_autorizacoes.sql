-- =====================================================
-- Autorizações: cards administrativos da Home
-- =====================================================
-- Adiciona ao BossOnly > Autorizações > Administração os
-- controles de visualização e acesso para cards existentes.
-- Grants iniciais preservam o comportamento atual para perfis
-- não-admin; admins continuam sempre liberados por tem_permissao().
-- =====================================================

INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem) VALUES
  (
    'admin.melhorias_eproc',
    'Acessar Melhorias Eproc',
    'Visualização e acesso ao card/modal Melhorias Eproc.',
    'admin',
    'src/pages/Home.tsx'
  ),
  (
    'admin.rejeites',
    'Acessar Rejeites',
    'Visualização e acesso ao card/modal Rejeites na Home e em Chamados & Outros Serviços.',
    'admin',
    'src/pages/Home.tsx; src/components/PastelariaModal.tsx'
  ),
  (
    'admin.chamados_manual',
    'Acessar Manual em Chamados',
    'Visualização e acesso ao subcard Manual dentro de Chamados & Outros Serviços.',
    'admin',
    'src/components/PastelariaModal.tsx; src/pages/Home.tsx'
  ),
  (
    'admin.chamados_dropdowns',
    'Acessar Dropdowns em Chamados',
    'Visualização e acesso ao subcard Dropdowns dentro de Chamados & Outros Serviços.',
    'admin',
    'src/components/PastelariaModal.tsx; src/pages/Home.tsx'
  )
ON CONFLICT (codigo) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  categoria = EXCLUDED.categoria,
  origem = EXCLUDED.origem,
  updated_at = NOW();
INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id) VALUES
  ('admin.melhorias_eproc',    'role', 'user'),
  ('admin.melhorias_eproc',    'role', 'supervisor'),
  ('admin.melhorias_eproc',    'role', 'coordenador'),
  ('admin.rejeites',           'role', 'user'),
  ('admin.rejeites',           'role', 'supervisor'),
  ('admin.rejeites',           'role', 'coordenador'),
  ('admin.chamados_manual',    'role', 'user'),
  ('admin.chamados_manual',    'role', 'supervisor'),
  ('admin.chamados_manual',    'role', 'coordenador'),
  ('admin.chamados_dropdowns', 'role', 'user'),
  ('admin.chamados_dropdowns', 'role', 'supervisor'),
  ('admin.chamados_dropdowns', 'role', 'coordenador')
ON CONFLICT DO NOTHING;

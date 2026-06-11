-- =====================================================
-- Autorizações: Arena de Pontos no dashboard principal
-- =====================================================
-- Cadastra o objeto de permissão da estatística gamificada
-- para controle via BossOnly > Autorizações.
--
-- Grants iniciais preservam o comportamento atual do card:
-- user, supervisor e coordenador continuam vendo a Arena de
-- Pontos; admins seguem sempre liberados por tem_permissao().
-- =====================================================

INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem) VALUES
  (
    'admin.gamificacao_dashboard',
    'Acessar Arena de Pontos',
    'Visualização e acesso ao card/modal Arena de Pontos no dashboard principal.',
    'admin',
    'src/pages/Home.tsx; src/components/GamificacaoModal.tsx'
  )
ON CONFLICT (codigo) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  categoria = EXCLUDED.categoria,
  origem = EXCLUDED.origem,
  updated_at = NOW();
INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id) VALUES
  ('admin.gamificacao_dashboard', 'role', 'user'),
  ('admin.gamificacao_dashboard', 'role', 'supervisor'),
  ('admin.gamificacao_dashboard', 'role', 'coordenador')
ON CONFLICT DO NOTHING;

-- =====================================================
-- Permissões: RPCs auxiliares para o frontend e seed
-- de grants iniciais (preserva comportamento hardcoded
-- atualmente em produção).
-- =====================================================

-- 1) RPC para o frontend carregar de uma vez todos os
--    códigos que o usuário corrente pode acessar.
--    Admin recebe '*' (sentinela = tudo liberado).
CREATE OR REPLACE FUNCTION public.permissoes_minhas_codigos()
RETURNS TABLE (codigo TEXT)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_role    TEXT;
  v_equipe  UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN;
  END IF;

  SELECT role::TEXT, equipe_id INTO v_role, v_equipe
  FROM public.users WHERE id = v_user_id;

  IF v_role = 'admin' THEN
    RETURN QUERY SELECT '*'::TEXT;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT DISTINCT g.objeto_codigo
  FROM public.permissoes_grants g
  WHERE
    (g.target_type = 'usuario' AND g.target_id = v_user_id::TEXT)
    OR (v_role IS NOT NULL AND g.target_type = 'role' AND g.target_id = v_role)
    OR (v_equipe IS NOT NULL AND g.target_type = 'equipe' AND g.target_id = v_equipe::TEXT);
END;
$$;
GRANT EXECUTE ON FUNCTION public.permissoes_minhas_codigos() TO authenticated;
-- 2) Seed dos grants iniciais para preservar o comportamento
--    hardcoded existente no código frontend.
--    OBS: 'admin' não precisa de grant — sempre passa via tem_permissao().

-- 2a) Equipe 2.1 (Qualidade) → controles N1 nos Scripts
INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id)
SELECT 'scripts.n1_controles', 'equipe', '5e589ebe-d178-4242-8482-fc92f34f034f'
WHERE EXISTS (SELECT 1 FROM public.equipes WHERE id = '5e589ebe-d178-4242-8482-fc92f34f034f')
ON CONFLICT DO NOTHING;
-- 2b) Equipes da Coordenadoria 3.2 (3.2.1, 3.2.2, 3.2.3) → "Scripts em Números"
INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id)
SELECT 'scripts.em_numeros_modal', 'equipe', e.id::TEXT
FROM public.equipes e
WHERE e.id IN (
  'd1c9e80b-2fd2-4f8d-973b-e7748e9bc9f2',
  'bb0f8880-a592-4deb-91b0-aa90aca157cf',
  'c954ef41-f837-49c7-8223-106bef99dfe1'
)
ON CONFLICT DO NOTHING;
-- 2c) Role 'supervisor' → privilégios de gestão no Radar
--     (preserva comportamento: hoje admin+supervisor podem editar/excluir
--      qualquer ticket e qualquer comentário no Radar de Tickets)
INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id) VALUES
  ('radar.dashboard_admin',             'role', 'supervisor'),
  ('radar.ticket_editar_qualquer',      'role', 'supervisor'),
  ('radar.ticket_excluir_qualquer',     'role', 'supervisor'),
  ('radar.comentario_excluir_qualquer', 'role', 'supervisor')
ON CONFLICT DO NOTHING;
-- Observações sobre objetos NÃO seedados (somente admin atualmente):
--   admin.boss_only_modal, admin.smith_consulta, admin.sinatra, admin.embeddings_dev
--   distribuidor.upload_excel, distribuidor.sos_keywords,
--   distribuidor.suspender_mantidos, distribuidor.liberar_ticket_outro
--   radar.ticket_editar_qualquer, radar.ticket_excluir_qualquer,
--   radar.comentario_excluir_qualquer, scripts.aprovar_exclusao
-- Admin continua com acesso automático; outros perfis começam SEM acesso
-- (mesmo comportamento atual, basta criar grants pela UI quando necessário).;

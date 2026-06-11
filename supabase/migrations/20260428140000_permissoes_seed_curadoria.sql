-- =============================================================================
-- Seed de grants para `scripts.curadoria_acesso`
-- Preserva o comportamento hardcoded anterior: somente admin (autom\u00e1tico via
-- tem_permissao()) e equipes da Coordenadoria 3.2 (3.2.1, 3.2.2, 3.2.3) podem
-- acessar os controles de Curadoria de Scripts.
-- =============================================================================

INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id)
SELECT 'scripts.curadoria_acesso', 'equipe', e.id::TEXT
FROM public.equipes e
WHERE e.id IN (
  'd1c9e80b-2fd2-4f8d-973b-e7748e9bc9f2', -- 3.2.1
  'bb0f8880-a592-4deb-91b0-aa90aca157cf', -- 3.2.2
  'c954ef41-f837-49c7-8223-106bef99dfe1'  -- 3.2.3
)
ON CONFLICT DO NOTHING;

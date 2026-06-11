-- =====================================================
-- Permissão: alterar threshold no Sistema Solar (Distribuidor)
-- =====================================================
INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem) VALUES
  ('distribuidor.cluster_threshold_slider',
   'Ajustar threshold do Sistema Solar',
   'Permite alterar o slider de threshold (rigor da similaridade) e disparar "Computar agrupamentos" no modal Sistema Solar do Distribuidor. Sem esta permissão o slider fica somente-leitura. Como o agrupamento é compartilhado por toda a equipe, recomenda-se conceder a poucos curadores para evitar que recomputações simultâneas conflitem entre usuários.',
   'distribuidor',
   'src/components/distribuidor/ClusterPlanetasModal.tsx')
ON CONFLICT (codigo) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  categoria = EXCLUDED.categoria,
  origem = EXCLUDED.origem;

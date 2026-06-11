-- Adiciona objeto de permissão para o botão "Agrupar Similares" do Distribuidor
INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem) VALUES
  ('distribuidor.cluster_planetas', 'Agrupar tickets por similaridade (Sistema Solar)',
   'Botão "Agrupar Similares" no header do Distribuidor — abre o modal de agrupamento semântico de tickets por embeddings (planetas e satélites).',
   'distribuidor', 'src/components/DistribuidorHeader.tsx')
ON CONFLICT (codigo) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  categoria = EXCLUDED.categoria,
  origem = EXCLUDED.origem,
  updated_at = NOW();

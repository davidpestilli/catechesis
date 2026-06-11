-- Ajusta o threshold padrao do mapa semantico de tickets livres para 88%.

CREATE OR REPLACE FUNCTION public.dist_obter_mapa_similaridade_livres(
  p_equipe_id uuid,
  p_origem text DEFAULT NULL,
  p_min_similarity real DEFAULT 0.88,
  p_top_k integer DEFAULT 8,
  p_max_tickets integer DEFAULT 800
)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, extensions
SET statement_timeout = '45s'
AS $$
  WITH parametros AS (
    SELECT
      LEAST(0.98::real, GREATEST(0.50::real, COALESCE(p_min_similarity, 0.88)::real)) AS min_similarity,
      LEAST(20, GREATEST(1, COALESCE(p_top_k, 8)))::integer AS top_k,
      LEAST(1200, GREATEST(20, COALESCE(p_max_tickets, 800)))::integer AS max_tickets
  ),
  base AS (
    SELECT
      t.id AS ticket_id,
      te.embedding,
      t.numero_chamado,
      t.gse,
      LEFT(COALESCE(t.descricao, ''), 900) AS descricao,
      t.email,
      COALESCE(t.vip, false) AS vip,
      COALESCE(t.sos, false) AS sos,
      t.origem::text AS origem,
      t.tempo_espera_origem,
      GREATEST(0::numeric, EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600.0) AS espera_horas,
      ta.categoria_equipe_id AS categoria_id,
      ce.nome AS categoria_nome,
      ce.cor_hex AS categoria_cor,
      ta.subcategoria_gse_id AS subcategoria_id,
      sg.nome AS subcategoria_nome
    FROM public.tickets t
    JOIN public.gse_equipes ge ON ge.gse = t.gse AND ge.equipe_id = p_equipe_id
    JOIN public.ticket_embeddings te ON te.ticket_id = t.id
    LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
    LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
    LEFT JOIN public.subcategorias_gse sg ON sg.id = ta.subcategoria_gse_id
    WHERE t.status = 'aguardando'
      AND COALESCE(t.suspenso, false) = false
      AND t.usuario_atual IS NULL
      AND t.mantido_por IS NULL
      AND t.tempo_espera_origem IS NOT NULL
      AND (p_origem IS NULL OR trim(p_origem) = '' OR t.origem::text = p_origem)
      AND NULLIF(BTRIM(t.descricao), '') IS NOT NULL
      AND lower(regexp_replace(BTRIM(t.descricao), '[[:space:]]+', ' ', 'g')) NOT IN (
        'descricao nao encontrada',
        'descrição não encontrada',
        'sem descricao',
        'sem descrição',
        'nao informado',
        'não informado',
        'description not found'
      )
  ),
  totais_base AS (
    SELECT
      count(*)::integer AS total_candidatos,
      count(*) FILTER (WHERE vip)::integer AS total_vip_base,
      count(*) FILTER (WHERE sos)::integer AS total_sos_base,
      COALESCE(ROUND(AVG(espera_horas)::numeric, 2), 0::numeric) AS tempo_medio_base_horas,
      MIN(tempo_espera_origem) AS ticket_mais_antigo_em
    FROM base
  ),
  candidatos AS (
    SELECT b.*
    FROM base b, parametros p
    ORDER BY b.vip DESC, b.sos DESC, b.tempo_espera_origem ASC, b.numero_chamado ASC
    LIMIT (SELECT max_tickets FROM parametros)
  ),
  raw_edges AS (
    SELECT
      LEAST(c1.ticket_id, vizinho.ticket_id) AS source_id,
      GREATEST(c1.ticket_id, vizinho.ticket_id) AS target_id,
      vizinho.similaridade
    FROM candidatos c1
    CROSS JOIN LATERAL (
      SELECT
        c2.ticket_id,
        (1.0 - (c1.embedding <=> c2.embedding))::real AS similaridade
      FROM candidatos c2, parametros p
      WHERE c2.ticket_id <> c1.ticket_id
        AND (1.0 - (c1.embedding <=> c2.embedding)) >= p.min_similarity
      ORDER BY c1.embedding <=> c2.embedding ASC, c2.ticket_id ASC
      LIMIT (SELECT top_k FROM parametros)
    ) vizinho
  ),
  edges AS (
    SELECT
      source_id,
      target_id,
      MAX(similaridade)::real AS similaridade
    FROM raw_edges
    WHERE source_id <> target_id
    GROUP BY source_id, target_id
  ),
  stats_edges AS (
    SELECT
      ticket_id,
      count(*)::integer AS grau,
      ROUND(AVG(similaridade)::numeric, 4)::real AS similaridade_media
    FROM (
      SELECT source_id AS ticket_id, similaridade FROM edges
      UNION ALL
      SELECT target_id AS ticket_id, similaridade FROM edges
    ) edge_refs
    GROUP BY ticket_id
  ),
  totais_exibidos AS (
    SELECT
      count(*)::integer AS total_exibidos,
      count(*) FILTER (WHERE vip)::integer AS total_vip,
      count(*) FILTER (WHERE sos)::integer AS total_sos,
      COALESCE(ROUND(AVG(espera_horas)::numeric, 2), 0::numeric) AS tempo_medio_horas,
      MIN(tempo_espera_origem) AS ticket_mais_antigo_exibido_em
    FROM candidatos
  ),
  nodes_json AS (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'ticket_id', c.ticket_id,
        'numero_chamado', c.numero_chamado,
        'gse', c.gse,
        'descricao', c.descricao,
        'email', c.email,
        'vip', c.vip,
        'sos', c.sos,
        'origem', c.origem,
        'tempo_espera_origem', c.tempo_espera_origem,
        'espera_horas', ROUND(c.espera_horas::numeric, 2),
        'categoria_id', c.categoria_id,
        'categoria_nome', c.categoria_nome,
        'categoria_cor', c.categoria_cor,
        'subcategoria_id', c.subcategoria_id,
        'subcategoria_nome', c.subcategoria_nome,
        'grau', COALESCE(se.grau, 0),
        'similaridade_media', COALESCE(se.similaridade_media, 0)
      ) ORDER BY COALESCE(se.grau, 0) DESC, c.vip DESC, c.sos DESC, c.tempo_espera_origem ASC
    ), '[]'::jsonb) AS nodes
    FROM candidatos c
    LEFT JOIN stats_edges se ON se.ticket_id = c.ticket_id
  ),
  edges_json AS (
    SELECT COALESCE(jsonb_agg(
      jsonb_build_object(
        'source', e.source_id,
        'target', e.target_id,
        'similaridade', ROUND(e.similaridade::numeric, 4)
      ) ORDER BY e.similaridade DESC, e.source_id, e.target_id
    ), '[]'::jsonb) AS edges
    FROM edges e
  )
  SELECT jsonb_build_object(
    'nodes', nodes_json.nodes,
    'edges', edges_json.edges,
    'metricas', jsonb_build_object(
      'total_candidatos', totais_base.total_candidatos,
      'total_exibidos', totais_exibidos.total_exibidos,
      'total_com_conexao', (SELECT count(*)::integer FROM stats_edges),
      'total_isolados', GREATEST(0, totais_exibidos.total_exibidos - (SELECT count(*)::integer FROM stats_edges)),
      'total_arestas', (SELECT count(*)::integer FROM edges),
      'total_vip', totais_exibidos.total_vip,
      'total_sos', totais_exibidos.total_sos,
      'total_vip_base', totais_base.total_vip_base,
      'total_sos_base', totais_base.total_sos_base,
      'tempo_medio_horas', totais_exibidos.tempo_medio_horas,
      'tempo_medio_base_horas', totais_base.tempo_medio_base_horas,
      'ticket_mais_antigo_em', totais_base.ticket_mais_antigo_em,
      'ticket_mais_antigo_exibido_em', totais_exibidos.ticket_mais_antigo_exibido_em,
      'limite_aplicado', totais_base.total_candidatos > totais_exibidos.total_exibidos
    ),
    'params', jsonb_build_object(
      'equipe_id', p_equipe_id,
      'origem', p_origem,
      'min_similarity', parametros.min_similarity,
      'top_k', parametros.top_k,
      'max_tickets', parametros.max_tickets
    ),
    'atualizado_em', now()
  )
  FROM parametros
  CROSS JOIN totais_base
  CROSS JOIN totais_exibidos
  CROSS JOIN nodes_json
  CROSS JOIN edges_json;
$$;

-- =========================================================================
-- 20260421183000_oraculo_relacionados_embedding.sql
-- =========================================================================
-- Reescreve oraculo_relacionados_ticket para usar EMBEDDINGS (busca semantica)
-- ao inves de FTS filtrado por categoria.
--
-- Motivacao: usuario reportou que ticket de "carta precatoria" categorizado
-- como "Peticionamento Eletronico > Erros e Falhas" nao trazia tickets/scripts
-- relacionados a carta precatoria, mesmo existindo varios na base. O filtro
-- rigido por categoria_equipe_id excluia matches semanticos relevantes.
--
-- Nova estrategia:
--   1. Tickets: ordena por similaridade vetorial (cosine) sem filtrar por
--      categoria. Mesma categoria/subcategoria recebe boost no ORDER BY.
--   2. Scripts: usa embeddings (script_embeddings) com mesma logica.
--   3. Fallback: se ticket nao tem embedding, mantem comportamento antigo
--      (FTS dentro da categoria) para nao quebrar.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.oraculo_relacionados_ticket(
  p_ticket_id UUID,
  p_limit INT DEFAULT 10
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_descricao TEXT;
  v_categoria_equipe_id UUID;
  v_subcategoria_gse_id UUID;
  v_categoria_slug TEXT;
  v_subcategoria_slug TEXT;
  v_equipe_id UUID;
  v_categoria_nome TEXT;
  v_subcategoria_nome TEXT;
  v_ticket_embedding vector(2000);
  v_ticket_equipe_id UUID;
  v_tickets JSONB;
  v_scripts JSONB;
  v_origem TEXT := 'embedding';
BEGIN
  -- 0. Descricao do ticket alvo
  SELECT t.descricao
    INTO v_descricao
    FROM public.tickets t
   WHERE t.id = p_ticket_id;

  IF v_descricao IS NULL OR trim(v_descricao) = '' THEN
    RETURN jsonb_build_object(
      'tickets', '[]'::jsonb,
      'scripts', '[]'::jsonb,
      'aviso', 'Ticket sem descricao. Nao e possivel buscar relacionados.',
      'categoria', NULL,
      'subcategoria', NULL,
      'origem', 'sem_descricao'
    );
  END IF;

  -- 1. Categoria/subcategoria (usadas como BOOST, nao como filtro)
  SELECT ta.categoria_equipe_id, ta.subcategoria_gse_id
    INTO v_categoria_equipe_id, v_subcategoria_gse_id
    FROM public.ticket_analises ta
   WHERE ta.ticket_id = p_ticket_id
   LIMIT 1;

  IF v_categoria_equipe_id IS NOT NULL THEN
    SELECT ce.slug, ce.equipe_id, ce.nome
      INTO v_categoria_slug, v_equipe_id, v_categoria_nome
      FROM public.categorias_equipe ce
     WHERE ce.id = v_categoria_equipe_id;
  END IF;

  IF v_subcategoria_gse_id IS NOT NULL THEN
    SELECT sg.slug, sg.nome
      INTO v_subcategoria_slug, v_subcategoria_nome
      FROM public.subcategorias_gse sg
     WHERE sg.id = v_subcategoria_gse_id;
  END IF;

  -- 2. Embedding do ticket alvo
  SELECT te.embedding, te.equipe_id
    INTO v_ticket_embedding, v_ticket_equipe_id
    FROM public.ticket_embeddings te
   WHERE te.ticket_id = p_ticket_id;

  -- 3a. Se TEM embedding => busca semantica
  IF v_ticket_embedding IS NOT NULL THEN
    -- Tickets relacionados via similaridade vetorial
    -- (sem filtro de categoria; boost para mesma cat/subcat e resposta substancial)
    SELECT COALESCE(jsonb_agg(row_to_json(ranked) ORDER BY ranked.ord), '[]'::jsonb)
      INTO v_tickets
      FROM (
        SELECT t.id,
               t.numero_chamado,
               t.descricao,
               t.resposta_ia,
               t.gse,
               t.email,
               t.updated_at,
               t.finished_at,
               ta_rel.subcategoria_gse_id,
               sg_rel.nome AS subcategoria_nome,
               ce_rel.nome AS categoria_nome,
               (1 - (te.embedding <=> v_ticket_embedding))::real AS similaridade,
               row_number() OVER (
                 ORDER BY
                   te.embedding <=> v_ticket_embedding ASC,
                   CASE WHEN ta_rel.categoria_equipe_id = v_categoria_equipe_id THEN 0 ELSE 1 END,
                   CASE WHEN v_subcategoria_gse_id IS NOT NULL
                             AND ta_rel.subcategoria_gse_id = v_subcategoria_gse_id THEN 0 ELSE 1 END,
                   CASE WHEN length(COALESCE(t.resposta_ia,'')) > 100 THEN 0 ELSE 1 END,
                   COALESCE(t.finished_at, t.updated_at) DESC NULLS LAST
               ) AS ord
          FROM public.ticket_embeddings te
          JOIN public.tickets t ON t.id = te.ticket_id
          LEFT JOIN public.ticket_analises ta_rel ON ta_rel.ticket_id = t.id
          LEFT JOIN public.categorias_equipe ce_rel ON ce_rel.id = ta_rel.categoria_equipe_id
          LEFT JOIN public.subcategorias_gse sg_rel ON sg_rel.id = ta_rel.subcategoria_gse_id
         WHERE te.ticket_id <> p_ticket_id
           AND t.status = 'finalizado'
           AND COALESCE(t.resposta_ia, '') <> ''
           AND (v_ticket_equipe_id IS NULL OR te.equipe_id = v_ticket_equipe_id)
         ORDER BY te.embedding <=> v_ticket_embedding ASC
         LIMIT GREATEST(p_limit * 5, 30)
      ) ranked
     WHERE ord <= p_limit;

    -- Scripts relacionados via similaridade vetorial
    SELECT COALESCE(jsonb_agg(row_to_json(s_ranked) ORDER BY s_ranked.ord), '[]'::jsonb)
      INTO v_scripts
      FROM (
        SELECT s.id,
               s.nome,
               s.conteudo_bruto,
               s.conteudo_atendente,
               s.tem_conteudo_atendente,
               s.categoria_equipe_slug,
               s.subcategoria_gse_slug,
               s.criado_em,
               s.dominio,
               (1 - (se.embedding <=> v_ticket_embedding))::real AS similaridade,
               row_number() OVER (
                 ORDER BY
                   se.embedding <=> v_ticket_embedding ASC,
                   CASE WHEN s.categoria_equipe_slug = v_categoria_slug THEN 0 ELSE 1 END,
                   CASE WHEN v_subcategoria_slug IS NOT NULL
                             AND s.subcategoria_gse_slug = v_subcategoria_slug THEN 0 ELSE 1 END,
                   s.criado_em DESC NULLS LAST
               ) AS ord
          FROM public.script_embeddings se
          JOIN public.scripts_customizados s ON s.id = se.script_id
         WHERE COALESCE(s.deletado, false) = false
           AND COALESCE(s.exclusao_pendente, false) = false
           AND (
             v_ticket_equipe_id IS NULL
             OR s.equipe_id = v_ticket_equipe_id
             OR (
               -- 2.3.2: incluir scripts da equipe 2.3.2 com dominio externo
               v_ticket_equipe_id = '11111111-1111-1111-1111-111111111111'::uuid
               AND s.equipe_id = '11111111-1111-1111-1111-111111111111'::uuid
               AND se.dominio = 'externo'
             )
           )
         ORDER BY se.embedding <=> v_ticket_embedding ASC
         LIMIT GREATEST(p_limit * 5, 30)
      ) s_ranked
     WHERE ord <= p_limit;

  ELSE
    -- 3b. Fallback FTS dentro da categoria (caso nao tenha embedding)
    v_origem := 'fts_categoria';

    IF v_categoria_equipe_id IS NULL THEN
      RETURN jsonb_build_object(
        'tickets', '[]'::jsonb,
        'scripts', '[]'::jsonb,
        'aviso', 'Ticket sem embedding e sem categorizacao. Use "Categorizar agora" ou aguarde geracao do embedding.',
        'categoria', NULL,
        'subcategoria', NULL,
        'origem', 'sem_embedding_sem_categoria'
      );
    END IF;

    SELECT COALESCE(jsonb_agg(row_to_json(r)), '[]'::jsonb)
      INTO v_tickets
      FROM (
        SELECT t.id, t.numero_chamado, t.descricao, t.resposta_ia, t.gse, t.email,
               t.updated_at, t.finished_at,
               ta_rel.subcategoria_gse_id,
               sg_rel.nome AS subcategoria_nome,
               ts_rank(
                 to_tsvector('portuguese', COALESCE(t.descricao, '')),
                 plainto_tsquery('portuguese', v_descricao)
               ) AS fts_rank
          FROM public.tickets t
          INNER JOIN public.ticket_analises ta_rel ON ta_rel.ticket_id = t.id
          LEFT JOIN public.subcategorias_gse sg_rel ON sg_rel.id = ta_rel.subcategoria_gse_id
         WHERE t.id <> p_ticket_id
           AND t.status = 'finalizado'
           AND ta_rel.categoria_equipe_id = v_categoria_equipe_id
           AND COALESCE(t.resposta_ia, '') <> ''
         ORDER BY fts_rank DESC,
                  CASE WHEN v_subcategoria_gse_id IS NOT NULL
                            AND ta_rel.subcategoria_gse_id = v_subcategoria_gse_id THEN 0 ELSE 1 END,
                  COALESCE(t.finished_at, t.updated_at) DESC NULLS LAST
         LIMIT p_limit
      ) r;

    SELECT COALESCE(jsonb_agg(row_to_json(s)), '[]'::jsonb)
      INTO v_scripts
      FROM (
        SELECT s.id, s.nome, s.conteudo_bruto, s.conteudo_atendente,
               s.tem_conteudo_atendente, s.categoria_equipe_slug,
               s.subcategoria_gse_slug, s.criado_em, s.dominio
          FROM public.scripts_customizados s
         WHERE s.equipe_id = v_equipe_id
           AND s.categoria_equipe_slug = v_categoria_slug
           AND COALESCE(s.deletado, false) = false
           AND COALESCE(s.exclusao_pendente, false) = false
         ORDER BY CASE WHEN v_subcategoria_slug IS NOT NULL
                            AND s.subcategoria_gse_slug = v_subcategoria_slug THEN 0 ELSE 1 END,
                  s.criado_em DESC NULLS LAST
         LIMIT p_limit
      ) s;
  END IF;

  RETURN jsonb_build_object(
    'tickets', COALESCE(v_tickets, '[]'::jsonb),
    'scripts', COALESCE(v_scripts, '[]'::jsonb),
    'categoria', CASE
      WHEN v_categoria_equipe_id IS NOT NULL THEN
        jsonb_build_object('id', v_categoria_equipe_id, 'slug', v_categoria_slug, 'nome', v_categoria_nome)
      ELSE NULL
    END,
    'subcategoria', CASE
      WHEN v_subcategoria_gse_id IS NOT NULL THEN
        jsonb_build_object('id', v_subcategoria_gse_id, 'slug', v_subcategoria_slug, 'nome', v_subcategoria_nome)
      ELSE NULL
    END,
    'origem', v_origem
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.oraculo_relacionados_ticket(UUID, INT) TO authenticated, service_role;
COMMENT ON FUNCTION public.oraculo_relacionados_ticket(UUID, INT) IS
'Modal Analise Oraculo V2: retorna tickets e scripts relacionados via similaridade vetorial (embeddings). Mesma categoria/subcategoria recebe boost no ranking, mas nao filtra. Fallback FTS+categoria quando ticket nao possui embedding.';

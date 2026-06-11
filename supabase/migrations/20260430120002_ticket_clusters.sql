-- =====================================================
-- MIGRATION: Sistema Solar — Agrupamento Semântico de Tickets
-- Data: 2026-04-30
-- Objetivo: agrupar tickets aguardando da fila Livres por similaridade
-- semântica (embeddings) para permitir resposta em massa por planeta.
-- Documento: docs/PLANO_AGRUPAMENTO_TICKETS_DISTRIBUIDOR.md
-- =====================================================

-- ============================================================
-- 1. TABELAS
-- ============================================================

CREATE TABLE IF NOT EXISTS public.ticket_clusters (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  equipe_id           uuid NOT NULL REFERENCES public.equipes(id) ON DELETE CASCADE,
  problema_comum      text NOT NULL DEFAULT '',
  resumo_curto        text,
  confianca           smallint NOT NULL DEFAULT 0,
  total_satelites     integer NOT NULL DEFAULT 0,
  total_livres        integer NOT NULL DEFAULT 0,
  categorias          jsonb NOT NULL DEFAULT '[]'::jsonb,
  subcategorias       jsonb NOT NULL DEFAULT '[]'::jsonb,
  gses                jsonb NOT NULL DEFAULT '[]'::jsonb,
  centroid_ticket_id  uuid REFERENCES public.tickets(id) ON DELETE SET NULL,
  algoritmo_versao    text NOT NULL DEFAULT 'v1-cosine088-min3',
  threshold           real NOT NULL DEFAULT 0.88,
  resumo_status       text NOT NULL DEFAULT 'pendente'
                       CHECK (resumo_status IN ('pendente','processando','ok','erro')),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_ticket_clusters_equipe
  ON public.ticket_clusters(equipe_id, updated_at DESC);
CREATE TABLE IF NOT EXISTS public.ticket_cluster_membros (
  cluster_id   uuid NOT NULL REFERENCES public.ticket_clusters(id) ON DELETE CASCADE,
  ticket_id    uuid NOT NULL REFERENCES public.tickets(id) ON DELETE CASCADE,
  similaridade real NOT NULL DEFAULT 0,
  PRIMARY KEY (cluster_id, ticket_id)
);
CREATE INDEX IF NOT EXISTS idx_ticket_cluster_membros_ticket
  ON public.ticket_cluster_membros(ticket_id);
-- Trigger updated_at
DROP TRIGGER IF EXISTS trg_ticket_clusters_updated_at ON public.ticket_clusters;
CREATE TRIGGER trg_ticket_clusters_updated_at
BEFORE UPDATE ON public.ticket_clusters
FOR EACH ROW EXECUTE FUNCTION public.set_updated_at_timestamp();
-- ============================================================
-- 2. RLS (somente leitura para autenticados; mutações via RPC)
-- ============================================================

ALTER TABLE public.ticket_clusters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ticket_cluster_membros ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS ticket_clusters_select ON public.ticket_clusters;
CREATE POLICY ticket_clusters_select ON public.ticket_clusters
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS ticket_cluster_membros_select ON public.ticket_cluster_membros;
CREATE POLICY ticket_cluster_membros_select ON public.ticket_cluster_membros
  FOR SELECT TO authenticated USING (true);
-- ============================================================
-- 3. RPC: cluster_tickets_equipe — pipeline de agrupamento
-- ============================================================
-- Faz: 1) varre tickets aguardando da equipe com embedding;
--      2) para cada ticket, busca top-K vizinhos com sim >= threshold;
--      3) union-find; descarta clusters menores que p_min_satelites;
--      4) calcula agregados (categorias/subcategorias/GSEs);
--      5) escreve ticket_clusters + ticket_cluster_membros (substitui anteriores da equipe).
--
-- Retorna jsonb { n_clusters, n_tickets_agrupados, n_tickets_avaliados, segundos }.

CREATE OR REPLACE FUNCTION public.cluster_tickets_equipe(
  p_equipe_id     uuid,
  p_threshold     real    DEFAULT 0.88,
  p_min_satelites integer DEFAULT 3,
  p_top_k         integer DEFAULT 20
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_inicio       timestamptz := clock_timestamp();
  v_n_avaliados  integer;
  v_n_clusters   integer;
  v_n_agrupados  integer;
  v_lock_key     bigint;
BEGIN
  -- Lock advisory por equipe para evitar dois recomputos simultâneos
  v_lock_key := ('x' || substr(md5('cluster:' || p_equipe_id::text), 1, 16))::bit(64)::bigint;
  PERFORM pg_advisory_xact_lock(v_lock_key);

  -- Limpa clusters antigos da equipe (cascade limpa membros)
  DELETE FROM public.ticket_clusters WHERE equipe_id = p_equipe_id;

  -- Tickets candidatos: aguardando, da equipe, com embedding
  CREATE TEMP TABLE _candidatos ON COMMIT DROP AS
    SELECT te.ticket_id, te.embedding
    FROM public.ticket_embeddings te
    JOIN public.tickets t ON t.id = te.ticket_id
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    WHERE ge.equipe_id = p_equipe_id
      AND t.status = 'aguardando';

  SELECT count(*) INTO v_n_avaliados FROM _candidatos;

  IF v_n_avaliados = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0, 'n_tickets_agrupados', 0, 'n_tickets_avaliados', 0,
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  -- Arestas semânticas: para cada candidato, top-K vizinhos no mesmo conjunto, sim >= threshold
  CREATE TEMP TABLE _arestas ON COMMIT DROP AS
    SELECT a.ticket_id AS a_id, b.ticket_id AS b_id, (1 - (a.embedding <=> b.embedding))::real AS sim
    FROM _candidatos a
    CROSS JOIN LATERAL (
      SELECT c.ticket_id, c.embedding
      FROM _candidatos c
      WHERE c.ticket_id <> a.ticket_id
      ORDER BY a.embedding <=> c.embedding
      LIMIT p_top_k
    ) b
    WHERE (1 - (a.embedding <=> b.embedding)) >= p_threshold;

  -- Union-find iterativo via MERGE de pares (algoritmo simples para o porte: <2k nós)
  CREATE TEMP TABLE _uf (ticket_id uuid PRIMARY KEY, root uuid NOT NULL) ON COMMIT DROP;
  INSERT INTO _uf(ticket_id, root) SELECT ticket_id, ticket_id FROM _candidatos;

  -- Loop de merges até convergir
  DECLARE
    v_changed integer := 1;
    v_iter integer := 0;
  BEGIN
    WHILE v_changed > 0 AND v_iter < 50 LOOP
      WITH pares AS (
        SELECT DISTINCT ua.root AS ra, ub.root AS rb
        FROM _arestas e
        JOIN _uf ua ON ua.ticket_id = e.a_id
        JOIN _uf ub ON ub.ticket_id = e.b_id
        WHERE ua.root <> ub.root
      ),
      novos AS (
        SELECT ra AS perdedor, LEAST(ra, rb) AS vencedor FROM pares WHERE ra > rb
        UNION
        SELECT rb, LEAST(ra, rb) FROM pares WHERE rb > ra
      ),
      atualizacoes AS (
        UPDATE _uf SET root = n.vencedor
        FROM novos n
        WHERE _uf.root = n.perdedor
        RETURNING 1
      )
      SELECT count(*) INTO v_changed FROM atualizacoes;
      v_iter := v_iter + 1;
    END LOOP;
  END;

  -- Agrupa: contagem por root
  CREATE TEMP TABLE _grupos ON COMMIT DROP AS
    SELECT root, count(*)::integer AS tamanho, array_agg(ticket_id) AS membros
    FROM _uf
    GROUP BY root
    HAVING count(*) >= p_min_satelites;

  SELECT count(*), COALESCE(sum(tamanho), 0) INTO v_n_clusters, v_n_agrupados FROM _grupos;

  IF v_n_clusters = 0 THEN
    RETURN jsonb_build_object(
      'n_clusters', 0, 'n_tickets_agrupados', 0, 'n_tickets_avaliados', v_n_avaliados,
      'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
    );
  END IF;

  -- Persiste planetas com agregados
  WITH grupos AS (
    SELECT g.root, g.tamanho, g.membros,
           gen_random_uuid() AS cluster_id
    FROM _grupos g
  ),
  inserts AS (
    INSERT INTO public.ticket_clusters (
      id, equipe_id, total_satelites, total_livres,
      categorias, subcategorias, gses, centroid_ticket_id,
      algoritmo_versao, threshold, resumo_status
    )
    SELECT
      g.cluster_id,
      p_equipe_id,
      g.tamanho,
      (SELECT count(*) FROM public.tickets t
        WHERE t.id = ANY(g.membros) AND t.mantido_por IS NULL),
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', x.cat_id, 'nome', x.cat_nome, 'count', x.c) ORDER BY x.c DESC), '[]'::jsonb)
        FROM (
          SELECT ce.id AS cat_id, ce.nome AS cat_nome, count(*)::int AS c
          FROM public.tickets t
          LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
          LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
          WHERE t.id = ANY(g.membros)
          GROUP BY ce.id, ce.nome
        ) x),
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('id', x.sub_id, 'nome', x.sub_nome, 'count', x.c) ORDER BY x.c DESC), '[]'::jsonb)
        FROM (
          SELECT sg.id AS sub_id, sg.nome AS sub_nome, count(*)::int AS c
          FROM public.tickets t
          LEFT JOIN public.ticket_analises ta ON ta.ticket_id = t.id
          LEFT JOIN public.subcategorias_gse sg ON sg.id = ta.subcategoria_gse_id
          WHERE t.id = ANY(g.membros)
          GROUP BY sg.id, sg.nome
        ) x),
      (SELECT COALESCE(jsonb_agg(jsonb_build_object('gse', x.gse, 'count', x.c) ORDER BY x.c DESC), '[]'::jsonb)
        FROM (
          SELECT t.gse, count(*)::int AS c
          FROM public.tickets t
          WHERE t.id = ANY(g.membros)
          GROUP BY t.gse
        ) x),
      g.root,
      'v1-cosine088-min3',
      p_threshold,
      'pendente'
    FROM grupos g
    RETURNING id
  )
  -- Insere membros com similaridade ao centroide
  INSERT INTO public.ticket_cluster_membros (cluster_id, ticket_id, similaridade)
  SELECT
    g.cluster_id,
    t_id,
    COALESCE((1 - (
      (SELECT embedding FROM public.ticket_embeddings WHERE ticket_id = t_id)
      <=>
      (SELECT embedding FROM public.ticket_embeddings WHERE ticket_id = g.root)
    ))::real, 0)
  FROM grupos g
  CROSS JOIN LATERAL unnest(g.membros) AS t_id;

  RETURN jsonb_build_object(
    'n_clusters', v_n_clusters,
    'n_tickets_agrupados', v_n_agrupados,
    'n_tickets_avaliados', v_n_avaliados,
    'segundos', EXTRACT(EPOCH FROM clock_timestamp() - v_inicio)
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_equipe(uuid, real, integer, integer) TO authenticated;
-- ============================================================
-- 4. RPC: cluster_tickets_listar — lista planetas + status atual
-- ============================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_listar(p_equipe_id uuid)
RETURNS TABLE(
  id uuid,
  problema_comum text,
  resumo_curto text,
  confianca smallint,
  total_satelites integer,
  total_livres_agora integer,
  categorias jsonb,
  subcategorias jsonb,
  gses jsonb,
  centroid_ticket_id uuid,
  resumo_status text,
  threshold real,
  updated_at timestamptz
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    c.problema_comum,
    c.resumo_curto,
    c.confianca,
    c.total_satelites,
    (SELECT count(*)::int
       FROM public.ticket_cluster_membros m
       JOIN public.tickets t ON t.id = m.ticket_id
       WHERE m.cluster_id = c.id AND t.mantido_por IS NULL),
    c.categorias,
    c.subcategorias,
    c.gses,
    c.centroid_ticket_id,
    c.resumo_status,
    c.threshold,
    c.updated_at
  FROM public.ticket_clusters c
  WHERE c.equipe_id = p_equipe_id
  ORDER BY c.total_satelites DESC, c.updated_at DESC;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_listar(uuid) TO authenticated;
-- ============================================================
-- 5. RPC: cluster_tickets_obter — detalhes + satélites
-- ============================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_obter(p_cluster_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'cluster', to_jsonb(c.*),
    'satelites', COALESCE((
      SELECT jsonb_agg(jsonb_build_object(
        'ticket_id', m.ticket_id,
        'similaridade', m.similaridade,
        'numero_chamado', t.numero_chamado,
        'gse', t.gse,
        'descricao', t.descricao,
        'email', t.email,
        'vip', t.vip,
        'sos', t.sos,
        'mantido_por', t.mantido_por,
        'mantido_por_nome', u.nome,
        'mantido_por_email', u.email,
        'tempo_espera_origem', t.tempo_espera_origem
      ) ORDER BY m.similaridade DESC)
      FROM public.ticket_cluster_membros m
      JOIN public.tickets t ON t.id = m.ticket_id
      LEFT JOIN public.users u ON u.id = t.mantido_por
      WHERE m.cluster_id = c.id
    ), '[]'::jsonb)
  )
  FROM public.ticket_clusters c
  WHERE c.id = p_cluster_id;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_obter(uuid) TO authenticated;
-- ============================================================
-- 6. RPC: cluster_tickets_atualizar_resumo — chamado pelo frontend após DeepSeek
-- ============================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_atualizar_resumo(
  p_cluster_id uuid,
  p_problema   text,
  p_resumo     text,
  p_confianca  integer,
  p_status     text DEFAULT 'ok'
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  UPDATE public.ticket_clusters
  SET problema_comum = COALESCE(p_problema, problema_comum),
      resumo_curto   = COALESCE(p_resumo, resumo_curto),
      confianca      = LEAST(100, GREATEST(0, COALESCE(p_confianca, 0))),
      resumo_status  = COALESCE(p_status, 'ok'),
      updated_at     = now()
  WHERE id = p_cluster_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_atualizar_resumo(uuid, text, text, integer, text) TO authenticated;
-- ============================================================
-- 7. RPC: cluster_tickets_manter_sistema — manter satélites livres
-- ============================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_manter_sistema(
  p_cluster_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_reservados integer := 0;
  v_ja_mantidos integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado';
  END IF;

  WITH alvo AS (
    SELECT m.ticket_id
    FROM public.ticket_cluster_membros m
    WHERE m.cluster_id = p_cluster_id
  ),
  upd AS (
    UPDATE public.tickets t
    SET mantido_por = v_user_id,
        mantido_at  = now(),
        updated_at  = now()
    FROM alvo
    WHERE t.id = alvo.ticket_id
      AND t.mantido_por IS NULL
    RETURNING t.id
  )
  SELECT count(*)::int INTO v_reservados FROM upd;

  SELECT count(*)::int INTO v_ja_mantidos
  FROM public.ticket_cluster_membros m
  JOIN public.tickets t ON t.id = m.ticket_id
  WHERE m.cluster_id = p_cluster_id
    AND t.mantido_por IS NOT NULL
    AND t.mantido_por <> v_user_id;

  -- Atualiza contador no cluster
  UPDATE public.ticket_clusters c
  SET total_livres = (
        SELECT count(*)::int FROM public.ticket_cluster_membros m
        JOIN public.tickets t ON t.id = m.ticket_id
        WHERE m.cluster_id = c.id AND t.mantido_por IS NULL
      ),
      updated_at = now()
  WHERE c.id = p_cluster_id;

  RETURN jsonb_build_object(
    'reservados', v_reservados,
    'ja_mantidos_por_outros', v_ja_mantidos
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_manter_sistema(uuid) TO authenticated;
-- ============================================================
-- 8. RPC utilitária: lista clusters pendentes de resumo (para o frontend chamar DeepSeek)
-- ============================================================

CREATE OR REPLACE FUNCTION public.cluster_tickets_pendentes_resumo(p_equipe_id uuid)
RETURNS TABLE(
  cluster_id uuid,
  amostras jsonb
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    c.id,
    (
      SELECT jsonb_agg(jsonb_build_object(
        'numero_chamado', s.numero_chamado,
        'descricao', LEFT(s.descricao, 800)
      ) ORDER BY s.similaridade DESC)
      FROM (
        SELECT t.numero_chamado, t.descricao, m.similaridade
        FROM public.ticket_cluster_membros m
        JOIN public.tickets t ON t.id = m.ticket_id
        WHERE m.cluster_id = c.id
        ORDER BY m.similaridade DESC
        LIMIT 5
      ) s
    )
  FROM public.ticket_clusters c
  WHERE c.equipe_id = p_equipe_id
    AND c.resumo_status IN ('pendente','erro');
$$;
GRANT EXECUTE ON FUNCTION public.cluster_tickets_pendentes_resumo(uuid) TO authenticated;

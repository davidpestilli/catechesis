-- =====================================================
-- MIGRATION: Sistema SOS no Distribuidor
-- Data: 2026-04-23
-- Descrição: Classificação de tickets por palavras-chave
--            de urgência/perigo (SOS), análoga aos VIPs.
--            - Coluna sos/sos_palavras/sos_override em tickets
--            - Tabela sos_palavras_chave (admin-managed)
--            - Trigger de avaliação automática
--            - RPCs de gestão e filtros
--            - Atualização de dist_buscar_tickets_paginado
-- =====================================================

BEGIN;
-- =====================================================
-- 1. Colunas em tickets
-- =====================================================
ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS sos boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS sos_palavras text[] NOT NULL DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS sos_override boolean NOT NULL DEFAULT false;
CREATE INDEX IF NOT EXISTS idx_tickets_sos ON public.tickets (sos) WHERE sos = true;
CREATE INDEX IF NOT EXISTS idx_tickets_sos_palavras_gin ON public.tickets USING gin (sos_palavras);
-- =====================================================
-- 2. Tabela de palavras-chave SOS
-- =====================================================
CREATE TABLE IF NOT EXISTS public.sos_palavras_chave (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  palavra text NOT NULL,
  palavra_normalizada text GENERATED ALWAYS AS (lower(public.f_unaccent(palavra))) STORED,
  ativo boolean NOT NULL DEFAULT true,
  criado_por uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS uq_sos_palavras_normalizada
  ON public.sos_palavras_chave (palavra_normalizada);
ALTER TABLE public.sos_palavras_chave ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS sos_palavras_select_all ON public.sos_palavras_chave;
CREATE POLICY sos_palavras_select_all ON public.sos_palavras_chave
  FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS sos_palavras_admin_all ON public.sos_palavras_chave;
CREATE POLICY sos_palavras_admin_all ON public.sos_palavras_chave
  FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin'));
-- Realtime para o modal/filtro (idempotente)
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.sos_palavras_chave;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
-- =====================================================
-- 3. Função de avaliação (auxiliar pura)
-- Recalcula array de palavras matched para um texto
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_match_palavras(p_descricao text)
RETURNS text[]
LANGUAGE sql
STABLE
AS $$
  SELECT COALESCE(
    array_agg(p.palavra_normalizada ORDER BY p.palavra_normalizada),
    '{}'::text[]
  )
  FROM public.sos_palavras_chave p
  WHERE p.ativo = true
    AND p_descricao IS NOT NULL
    AND lower(public.f_unaccent(p_descricao)) LIKE '%' || p.palavra_normalizada || '%';
$$;
-- =====================================================
-- 4. Trigger de avaliação automática em tickets
-- =====================================================
CREATE OR REPLACE FUNCTION public.tickets_sos_evaluate_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Recalcula palavras matched
  NEW.sos_palavras := public.sos_match_palavras(NEW.descricao);

  -- Se não houver override manual, aplica decisão automática
  IF NEW.sos_override IS NOT TRUE THEN
    NEW.sos := COALESCE(array_length(NEW.sos_palavras, 1), 0) > 0;
  END IF;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_tickets_sos_evaluate ON public.tickets;
CREATE TRIGGER trg_tickets_sos_evaluate
BEFORE INSERT OR UPDATE OF descricao, sos_override
ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION public.tickets_sos_evaluate_trigger();
-- =====================================================
-- 5. RPC: reavaliar tickets em fila
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_reavaliar_tickets_fila(
  p_equipe_id uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gses text[];
  v_count integer := 0;
BEGIN
  IF p_equipe_id IS NOT NULL THEN
    SELECT array_agg(gse) INTO v_gses
    FROM public.gse_equipes WHERE equipe_id = p_equipe_id;
    IF v_gses IS NULL THEN RETURN 0; END IF;
  END IF;

  -- UPDATE no-op força o trigger BEFORE UPDATE OF descricao a NÃO disparar
  -- (porque descricao não muda). Solução: fazer UPDATE explícito que
  -- inclua descricao = descricao? Não — basta usar UPDATE de sos_palavras
  -- diretamente recalculado, pois sos_override também dispara o trigger.
  WITH alvo AS (
    SELECT id FROM public.tickets t
    WHERE t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND (v_gses IS NULL OR t.gse = ANY(v_gses))
  )
  UPDATE public.tickets t
     SET sos_palavras = public.sos_match_palavras(t.descricao),
         sos = CASE
                 WHEN t.sos_override IS TRUE THEN t.sos
                 ELSE COALESCE(array_length(public.sos_match_palavras(t.descricao), 1), 0) > 0
               END
   FROM alvo
   WHERE t.id = alvo.id;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
COMMENT ON FUNCTION public.sos_reavaliar_tickets_fila IS
  'Reavalia classificação SOS de todos os tickets em fila (status=aguardando, sem usuário_atual). Escopo opcional por equipe.';
-- =====================================================
-- 6. RPC: listar palavras com contagem global (admin)
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_listar_palavras_admin()
RETURNS TABLE(
  id uuid,
  palavra text,
  palavra_normalizada text,
  ativo boolean,
  total_tickets bigint,
  tickets_em_fila bigint,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin') THEN
    RAISE EXCEPTION 'Apenas administradores podem listar palavras SOS';
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.palavra,
    p.palavra_normalizada,
    p.ativo,
    (SELECT COUNT(*) FROM public.tickets t WHERE p.palavra_normalizada = ANY(t.sos_palavras))::bigint AS total_tickets,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando' AND t.usuario_atual IS NULL)::bigint AS tickets_em_fila,
    p.created_at
  FROM public.sos_palavras_chave p
  ORDER BY p.created_at DESC;
END;
$$;
-- =====================================================
-- 7. RPC: listar palavras + contagem por equipe (filtro)
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_listar_palavras_equipe(
  p_equipe_id uuid,
  p_origem text DEFAULT NULL
)
RETURNS TABLE(
  palavra_normalizada text,
  palavra text,
  quantidade bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gses text[];
BEGIN
  SELECT array_agg(gse) INTO v_gses
  FROM public.gse_equipes WHERE equipe_id = p_equipe_id;

  IF v_gses IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT
    p.palavra_normalizada,
    p.palavra,
    COUNT(*)::bigint AS quantidade
  FROM public.sos_palavras_chave p
  JOIN public.tickets t
    ON p.palavra_normalizada = ANY(t.sos_palavras)
  WHERE p.ativo = true
    AND t.status = 'aguardando'
    AND t.usuario_atual IS NULL
    AND t.gse = ANY(v_gses)
    AND (p_origem IS NULL OR t.origem = p_origem)
  GROUP BY p.palavra_normalizada, p.palavra
  ORDER BY quantidade DESC, p.palavra;
END;
$$;
-- =====================================================
-- 8. RPC: adicionar palavra
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_adicionar_palavra(
  p_palavra text,
  p_aplicar_retroativo boolean DEFAULT true
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id uuid;
  v_norm text;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin') THEN
    RAISE EXCEPTION 'Apenas administradores podem adicionar palavras SOS';
  END IF;

  IF p_palavra IS NULL OR length(trim(p_palavra)) < 2 THEN
    RAISE EXCEPTION 'Palavra deve ter pelo menos 2 caracteres';
  END IF;

  v_norm := lower(public.f_unaccent(trim(p_palavra)));

  -- Se já existir mas inativa, reativa; se ativa, retorna o id existente
  SELECT id INTO v_id FROM public.sos_palavras_chave
   WHERE palavra_normalizada = v_norm;

  IF v_id IS NOT NULL THEN
    UPDATE public.sos_palavras_chave SET ativo = true WHERE id = v_id;
  ELSE
    INSERT INTO public.sos_palavras_chave (palavra, criado_por)
    VALUES (trim(p_palavra), auth.uid())
    RETURNING id INTO v_id;
  END IF;

  IF p_aplicar_retroativo THEN
    PERFORM public.sos_reavaliar_tickets_fila(NULL);
  END IF;

  RETURN v_id;
END;
$$;
-- =====================================================
-- 9. RPC: remover palavra
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_remover_palavra(
  p_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin') THEN
    RAISE EXCEPTION 'Apenas administradores podem remover palavras SOS';
  END IF;

  DELETE FROM public.sos_palavras_chave WHERE id = p_id;

  -- Reavalia tickets em fila (descontar a palavra removida)
  PERFORM public.sos_reavaliar_tickets_fila(NULL);
END;
$$;
-- =====================================================
-- 10. RPC: toggle SOS de um ticket (manual override)
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_toggle_ticket(
  p_ticket_id uuid
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_novo boolean;
BEGIN
  UPDATE public.tickets
     SET sos = NOT sos,
         sos_override = true,
         updated_at = now()
   WHERE id = p_ticket_id
   RETURNING sos INTO v_novo;

  IF v_novo IS NULL THEN
    RAISE EXCEPTION 'Ticket não encontrado: %', p_ticket_id;
  END IF;

  RETURN v_novo;
END;
$$;
-- =====================================================
-- 11. Atualizar dist_buscar_tickets_paginado
--     Adiciona p_filtro_sos + colunas SOS no retorno
--     Ordenação: VIP > SOS > tempo_espera
-- =====================================================
DROP FUNCTION IF EXISTS public.dist_buscar_tickets_paginado(uuid, text, boolean, integer, integer, text, text, text, numeric, text, text);
CREATE OR REPLACE FUNCTION public.dist_buscar_tickets_paginado(
  p_equipe_id uuid,
  p_origem text DEFAULT NULL,
  p_suspenso boolean DEFAULT false,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0,
  p_filtro_categoria text DEFAULT NULL,
  p_filtro_mantido text DEFAULT NULL,
  p_filtro_numero text DEFAULT NULL,
  p_filtro_tempo_horas numeric DEFAULT NULL,
  p_filtro_tempo_operador text DEFAULT 'maior',
  p_filtro_subcategoria text DEFAULT NULL,
  p_filtro_sos text DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  numero_chamado text,
  gse text,
  email text,
  descricao text,
  status text,
  origem text,
  vip boolean,
  sos boolean,
  sos_palavras text[],
  sos_override boolean,
  tempo_espera_origem timestamptz,
  suspenso boolean,
  causa_suspensao text,
  mantido_por uuid,
  mantido_at timestamptz,
  mantido_por_nome text,
  mantido_por_email text,
  chamado_global_id uuid,
  created_at timestamptz,
  updated_at timestamptz,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_gses text[];
  v_total bigint;
  v_sos_norm text;
BEGIN
  SELECT array_agg(ge.gse) INTO v_gses
  FROM gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  IF v_gses IS NULL OR array_length(v_gses, 1) IS NULL THEN
    RETURN;
  END IF;

  v_sos_norm := CASE
                  WHEN p_filtro_sos IS NULL OR p_filtro_sos = 'todas' THEN NULL
                  ELSE lower(public.f_unaccent(p_filtro_sos))
                END;

  SELECT COUNT(*) INTO v_total
  FROM tickets t
  LEFT JOIN ticket_analises ta ON ta.ticket_id = t.id
  WHERE t.gse = ANY(v_gses)
    AND t.status = 'aguardando'
    AND t.usuario_atual IS NULL
    AND t.suspenso = p_suspenso
    AND (p_origem IS NULL OR t.origem = p_origem)
    AND (p_filtro_categoria IS NULL OR ta.categoria_slug = p_filtro_categoria)
    AND (p_filtro_subcategoria IS NULL OR ta.subcategoria_slug = p_filtro_subcategoria)
    AND (
      p_filtro_mantido IS NULL
      OR p_filtro_mantido = 'todos'
      OR (p_filtro_mantido = 'livres' AND t.mantido_por IS NULL)
      OR (p_filtro_mantido = 'mantidos' AND t.mantido_por IS NOT NULL)
      OR t.mantido_por::text = p_filtro_mantido
    )
    AND (p_filtro_numero IS NULL OR t.numero_chamado ILIKE '%' || p_filtro_numero || '%')
    AND (
      p_filtro_tempo_horas IS NULL
      OR (p_filtro_tempo_operador = 'maior'
          AND EXTRACT(EPOCH FROM (NOW() - t.tempo_espera_origem)) / 3600 > p_filtro_tempo_horas)
      OR (p_filtro_tempo_operador = 'menor'
          AND EXTRACT(EPOCH FROM (NOW() - t.tempo_espera_origem)) / 3600 < p_filtro_tempo_horas)
    )
    AND (
      p_filtro_sos IS NULL
      OR (p_filtro_sos = 'todas' AND t.sos = true)
      OR (v_sos_norm IS NOT NULL AND v_sos_norm = ANY(t.sos_palavras))
    );

  RETURN QUERY
  SELECT
    t.id,
    t.numero_chamado,
    t.gse,
    t.email,
    t.descricao,
    t.status,
    t.origem,
    t.vip,
    t.sos,
    t.sos_palavras,
    t.sos_override,
    t.tempo_espera_origem,
    t.suspenso,
    t.causa_suspensao,
    t.mantido_por,
    t.mantido_at,
    u.nome AS mantido_por_nome,
    u.email AS mantido_por_email,
    t.chamado_global_id,
    t.created_at,
    t.updated_at,
    v_total AS total_count
  FROM tickets t
  LEFT JOIN users u ON u.id = t.mantido_por
  LEFT JOIN ticket_analises ta ON ta.ticket_id = t.id
  WHERE t.gse = ANY(v_gses)
    AND t.status = 'aguardando'
    AND t.usuario_atual IS NULL
    AND t.suspenso = p_suspenso
    AND (p_origem IS NULL OR t.origem = p_origem)
    AND (p_filtro_categoria IS NULL OR ta.categoria_slug = p_filtro_categoria)
    AND (p_filtro_subcategoria IS NULL OR ta.subcategoria_slug = p_filtro_subcategoria)
    AND (
      p_filtro_mantido IS NULL
      OR p_filtro_mantido = 'todos'
      OR (p_filtro_mantido = 'livres' AND t.mantido_por IS NULL)
      OR (p_filtro_mantido = 'mantidos' AND t.mantido_por IS NOT NULL)
      OR t.mantido_por::text = p_filtro_mantido
    )
    AND (p_filtro_numero IS NULL OR t.numero_chamado ILIKE '%' || p_filtro_numero || '%')
    AND (
      p_filtro_tempo_horas IS NULL
      OR (p_filtro_tempo_operador = 'maior'
          AND EXTRACT(EPOCH FROM (NOW() - t.tempo_espera_origem)) / 3600 > p_filtro_tempo_horas)
      OR (p_filtro_tempo_operador = 'menor'
          AND EXTRACT(EPOCH FROM (NOW() - t.tempo_espera_origem)) / 3600 < p_filtro_tempo_horas)
    )
    AND (
      p_filtro_sos IS NULL
      OR (p_filtro_sos = 'todas' AND t.sos = true)
      OR (v_sos_norm IS NOT NULL AND v_sos_norm = ANY(t.sos_palavras))
    )
  ORDER BY t.vip DESC, t.sos DESC, t.tempo_espera_origem ASC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;
COMMENT ON FUNCTION public.dist_buscar_tickets_paginado IS
  'Busca tickets paginados com filtros de categoria, subcategoria, mantido, tempo de espera e SOS. Ordena por VIP > SOS > tempo de espera.';
-- =====================================================
-- 12. GRANTS
-- =====================================================
GRANT EXECUTE ON FUNCTION public.sos_match_palavras(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_listar_palavras_admin() TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_listar_palavras_equipe(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_adicionar_palavra(text, boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_remover_palavra(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_toggle_ticket(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.sos_reavaliar_tickets_fila(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.dist_buscar_tickets_paginado(uuid, text, boolean, integer, integer, text, text, text, numeric, text, text, text) TO authenticated;
GRANT SELECT ON public.sos_palavras_chave TO authenticated;
-- =====================================================
-- 13. SEED inicial
-- =====================================================
INSERT INTO public.sos_palavras_chave (palavra) VALUES
  ('Urgência'),
  ('Audiência'),
  ('Fatal'),
  ('Liminar'),
  ('Tutela'),
  ('Onco')
ON CONFLICT (palavra_normalizada) DO NOTHING;
-- =====================================================
-- 14. Backfill: avalia todos os tickets em fila com as palavras seed
-- =====================================================
UPDATE public.tickets t
   SET sos_palavras = public.sos_match_palavras(t.descricao),
       sos = CASE
               WHEN t.sos_override IS TRUE THEN t.sos
               ELSE COALESCE(array_length(public.sos_match_palavras(t.descricao), 1), 0) > 0
             END
 WHERE t.status = 'aguardando' AND t.usuario_atual IS NULL;
-- Recarregar cache PostgREST
NOTIFY pgrst, 'reload schema';
COMMIT;

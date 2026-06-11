-- =====================================================
-- MIGRATION: SOS — Compartimentalização por Equipe
-- Data: 2026-04-24 (18h)
--
-- Mudança estrutural: palavras-chave SOS agora pertencem a uma
-- equipe específica. Trigger resolve a equipe do ticket via GSE
-- e aplica APENAS as palavras dessa equipe.
--
-- Resolve:
--  - Palavra adicionada por equipe X afetando tickets de outras equipes
--  - "Reavaliar fila" reavaliando 1309 tickets do sistema todo
--  - Modal admin listando palavras de outras equipes
-- =====================================================

BEGIN;
-- =====================================================
-- 1. Adicionar equipe_id à tabela sos_palavras_chave
-- =====================================================
ALTER TABLE public.sos_palavras_chave
  ADD COLUMN IF NOT EXISTS equipe_id uuid REFERENCES public.equipes(id) ON DELETE CASCADE;
-- Backfill: atribui cada palavra existente à equipe que tem mais tickets
-- com aquela palavra (decisão pragmática para preservar dados existentes)
UPDATE public.sos_palavras_chave p
   SET equipe_id = sub.equipe_id
  FROM (
    SELECT pp.id, ge.equipe_id
    FROM public.sos_palavras_chave pp
    JOIN public.tickets t ON pp.palavra_normalizada = ANY(t.sos_palavras)
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    WHERE pp.equipe_id IS NULL
    GROUP BY pp.id, ge.equipe_id
    ORDER BY pp.id, COUNT(*) DESC
  ) sub
 WHERE p.id = sub.id AND p.equipe_id IS NULL;
-- Palavras sem nenhum match → atribuir à primeira equipe (admin pode mover/excluir depois)
UPDATE public.sos_palavras_chave
   SET equipe_id = (SELECT id FROM public.equipes ORDER BY created_at LIMIT 1)
 WHERE equipe_id IS NULL;
-- Tornar NOT NULL (se ainda houver nulos, falha segura)
ALTER TABLE public.sos_palavras_chave ALTER COLUMN equipe_id SET NOT NULL;
-- Trocar índice único: agora por (equipe_id, palavra_normalizada)
DROP INDEX IF EXISTS public.uq_sos_palavras_normalizada;
CREATE UNIQUE INDEX IF NOT EXISTS uq_sos_palavras_equipe_normalizada
  ON public.sos_palavras_chave (equipe_id, palavra_normalizada);
CREATE INDEX IF NOT EXISTS idx_sos_palavras_equipe ON public.sos_palavras_chave (equipe_id);
-- =====================================================
-- 2. sos_match_palavras agora exige equipe_id
-- =====================================================
DROP FUNCTION IF EXISTS public.sos_match_palavras(text);
DROP FUNCTION IF EXISTS public.sos_match_palavras(text, uuid);
CREATE OR REPLACE FUNCTION public.sos_match_palavras(
  p_descricao text,
  p_equipe_id uuid
)
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
    AND p.equipe_id = p_equipe_id
    AND p_descricao IS NOT NULL
    AND lower(public.f_unaccent(p_descricao)) LIKE '%' || p.palavra_normalizada || '%';
$$;
-- =====================================================
-- 3. Trigger: resolve equipe do ticket via gse_equipes
-- =====================================================
CREATE OR REPLACE FUNCTION public.tickets_sos_evaluate_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_equipe_id uuid;
BEGIN
  -- Resolve a equipe do ticket pelo GSE
  SELECT ge.equipe_id INTO v_equipe_id
  FROM public.gse_equipes ge
  WHERE ge.gse = NEW.gse
  LIMIT 1;

  IF v_equipe_id IS NULL THEN
    -- Ticket sem equipe associada → sem match SOS
    NEW.sos_palavras := '{}'::text[];
  ELSE
    NEW.sos_palavras := public.sos_match_palavras(NEW.descricao, v_equipe_id);
  END IF;

  IF NEW.sos_override IS NOT TRUE THEN
    NEW.sos := COALESCE(array_length(NEW.sos_palavras, 1), 0) > 0;
  END IF;

  RETURN NEW;
END;
$$;
-- =====================================================
-- 4. sos_reavaliar_tickets_fila — exige equipe_id
-- =====================================================
DROP FUNCTION IF EXISTS public.sos_reavaliar_tickets_fila(uuid);
CREATE OR REPLACE FUNCTION public.sos_reavaliar_tickets_fila(
  p_equipe_id uuid
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
  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatório para reavaliação SOS (compartimentalização por equipe)';
  END IF;

  SELECT array_agg(gse) INTO v_gses
  FROM public.gse_equipes WHERE equipe_id = p_equipe_id;

  IF v_gses IS NULL OR array_length(v_gses, 1) IS NULL THEN
    RETURN 0;
  END IF;

  WITH alvo AS (
    SELECT id FROM public.tickets t
    WHERE t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND t.gse = ANY(v_gses)
  )
  UPDATE public.tickets t
     SET sos_palavras = public.sos_match_palavras(t.descricao, p_equipe_id),
         sos = CASE
                 WHEN t.sos_override IS TRUE THEN t.sos
                 ELSE COALESCE(array_length(public.sos_match_palavras(t.descricao, p_equipe_id), 1), 0) > 0
               END
   FROM alvo
   WHERE t.id = alvo.id;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_reavaliar_tickets_fila(uuid) TO authenticated;
COMMENT ON FUNCTION public.sos_reavaliar_tickets_fila IS
  'Reavalia classificação SOS de tickets ATIVOS da equipe especificada (status=aguardando, sem usuário_atual).';
-- =====================================================
-- 5. sos_listar_palavras_admin — escopo OBRIGATÓRIO por equipe
-- =====================================================
DROP FUNCTION IF EXISTS public.sos_listar_palavras_admin();
DROP FUNCTION IF EXISTS public.sos_listar_palavras_admin(uuid);
CREATE OR REPLACE FUNCTION public.sos_listar_palavras_admin(
  p_equipe_id uuid
)
RETURNS TABLE(
  id uuid,
  palavra text,
  palavra_normalizada text,
  ativo boolean,
  total_tickets bigint,
  tickets_em_fila bigint,
  tickets_livres bigint,
  tickets_suspensos bigint,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gses text[];
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin') THEN
    RAISE EXCEPTION 'Apenas administradores podem listar palavras SOS';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatório (compartimentalização por equipe)';
  END IF;

  SELECT array_agg(gse) INTO v_gses
  FROM public.gse_equipes WHERE equipe_id = p_equipe_id;

  RETURN QUERY
  SELECT
    p.id,
    p.palavra,
    p.palavra_normalizada,
    p.ativo,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS total_tickets,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_em_fila,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_livres,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = true
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_suspensos,
    p.created_at
  FROM public.sos_palavras_chave p
  WHERE p.equipe_id = p_equipe_id
  ORDER BY tickets_livres DESC, tickets_suspensos DESC, p.palavra ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_listar_palavras_admin(uuid) TO authenticated;
-- =====================================================
-- 6. sos_listar_palavras_equipe — palavras já filtradas por equipe
-- =====================================================
DROP FUNCTION IF EXISTS public.sos_listar_palavras_equipe(uuid, text);
DROP FUNCTION IF EXISTS public.sos_listar_palavras_equipe(uuid, text, boolean);
CREATE OR REPLACE FUNCTION public.sos_listar_palavras_equipe(
  p_equipe_id uuid,
  p_origem text DEFAULT NULL,
  p_suspenso boolean DEFAULT false
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
    AND p.equipe_id = p_equipe_id
    AND t.status = 'aguardando'
    AND t.usuario_atual IS NULL
    AND COALESCE(t.suspenso, false) = COALESCE(p_suspenso, false)
    AND t.gse = ANY(v_gses)
    AND (p_origem IS NULL OR t.origem = p_origem)
  GROUP BY p.palavra_normalizada, p.palavra
  ORDER BY quantidade DESC, p.palavra;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_listar_palavras_equipe(uuid, text, boolean) TO authenticated;
-- =====================================================
-- 7. sos_adicionar_palavra — exige equipe_id, reavalia só essa equipe
-- =====================================================
DROP FUNCTION IF EXISTS public.sos_adicionar_palavra(text, boolean);
DROP FUNCTION IF EXISTS public.sos_adicionar_palavra(text, uuid, boolean);
CREATE OR REPLACE FUNCTION public.sos_adicionar_palavra(
  p_palavra text,
  p_equipe_id uuid,
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

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'equipe_id obrigatório (compartimentalização por equipe)';
  END IF;

  IF p_palavra IS NULL OR length(trim(p_palavra)) < 2 THEN
    RAISE EXCEPTION 'Palavra deve ter pelo menos 2 caracteres';
  END IF;

  v_norm := lower(public.f_unaccent(trim(p_palavra)));

  SELECT id INTO v_id FROM public.sos_palavras_chave
   WHERE palavra_normalizada = v_norm AND equipe_id = p_equipe_id;

  IF v_id IS NOT NULL THEN
    UPDATE public.sos_palavras_chave SET ativo = true WHERE id = v_id;
  ELSE
    INSERT INTO public.sos_palavras_chave (palavra, equipe_id, criado_por)
    VALUES (trim(p_palavra), p_equipe_id, auth.uid())
    RETURNING id INTO v_id;
  END IF;

  IF p_aplicar_retroativo THEN
    PERFORM public.sos_reavaliar_tickets_fila(p_equipe_id);
  END IF;

  RETURN v_id;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_adicionar_palavra(text, uuid, boolean) TO authenticated;
-- =====================================================
-- 8. sos_remover_palavra — reavalia apenas a equipe da palavra
-- =====================================================
CREATE OR REPLACE FUNCTION public.sos_remover_palavra(
  p_id uuid
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_equipe_id uuid;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin') THEN
    RAISE EXCEPTION 'Apenas administradores podem remover palavras SOS';
  END IF;

  SELECT equipe_id INTO v_equipe_id FROM public.sos_palavras_chave WHERE id = p_id;

  DELETE FROM public.sos_palavras_chave WHERE id = p_id;

  IF v_equipe_id IS NOT NULL THEN
    PERFORM public.sos_reavaliar_tickets_fila(v_equipe_id);
  END IF;
END;
$$;
-- =====================================================
-- 9. sos_contar_tickets_unicos — já recebe equipe_id (mantém)
-- =====================================================
-- (sem mudanças; já filtra por GSEs da equipe)

COMMIT;
NOTIFY pgrst, 'reload schema';

-- =====================================================
-- MIGRATION: SOS — escopo por equipe em admin + só tickets ativos
-- Data: 2026-04-24 (17h)
-- Bug fix:
--   1. sos_listar_palavras_admin: era global (todas as equipes), agora
--      aceita p_equipe_id opcional e escopa ao time.
--   2. total_tickets: era ALL statuses (incluía finalizados), agora
--      conta apenas tickets ativos na fila (status='aguardando').
--   3. sos_contar_tickets_unicos: total_sistema agora conta apenas ativos.
-- =====================================================

-- 1. Listagem admin com escopo opcional por equipe
DROP FUNCTION IF EXISTS public.sos_listar_palavras_admin();
DROP FUNCTION IF EXISTS public.sos_listar_palavras_admin(uuid);
CREATE OR REPLACE FUNCTION public.sos_listar_palavras_admin(
  p_equipe_id uuid DEFAULT NULL
)
RETURNS TABLE(
  id uuid,
  palavra text,
  palavra_normalizada text,
  ativo boolean,
  total_tickets bigint,         -- livres + suspensos na fila (ativo, escopo equipe)
  tickets_em_fila bigint,        -- = livres (compat.)
  tickets_livres bigint,
  tickets_suspensos bigint,
  created_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gses text[] := NULL;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin') THEN
    RAISE EXCEPTION 'Apenas administradores podem listar palavras SOS';
  END IF;

  -- Quando equipeId fornecido, restringe GSEs à equipe
  IF p_equipe_id IS NOT NULL THEN
    SELECT array_agg(gse) INTO v_gses
    FROM public.gse_equipes WHERE equipe_id = p_equipe_id;
    -- equipe sem GSEs → retorna zeros
    IF v_gses IS NULL THEN v_gses := ARRAY[]::text[]; END IF;
  END IF;

  RETURN QUERY
  SELECT
    p.id,
    p.palavra,
    p.palavra_normalizada,
    p.ativo,
    -- total ativo = livres + suspensos na fila (não conta finalizados)
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND (v_gses IS NULL OR t.gse = ANY(v_gses)))::bigint AS total_tickets,
    -- tickets_em_fila = livres (compat. cliente antigo)
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NULL OR t.gse = ANY(v_gses)))::bigint AS tickets_em_fila,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NULL OR t.gse = ANY(v_gses)))::bigint AS tickets_livres,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = true
         AND (v_gses IS NULL OR t.gse = ANY(v_gses)))::bigint AS tickets_suspensos,
    p.created_at
  FROM public.sos_palavras_chave p
  ORDER BY tickets_livres DESC, tickets_suspensos DESC, total_tickets DESC, p.palavra ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_listar_palavras_admin(uuid) TO authenticated;
-- 2. Contagem de tickets únicos — total_sistema agora conta apenas ativos
DROP FUNCTION IF EXISTS public.sos_contar_tickets_unicos(uuid);
CREATE OR REPLACE FUNCTION public.sos_contar_tickets_unicos(
  p_equipe_id uuid DEFAULT NULL
)
RETURNS TABLE(
  total_sistema bigint,    -- tickets com SOS ativos (fila, escopo equipe)
  total_livres bigint,
  total_suspensos bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_gses text[] := NULL;
BEGIN
  IF p_equipe_id IS NOT NULL THEN
    SELECT array_agg(gse) INTO v_gses
    FROM public.gse_equipes WHERE equipe_id = p_equipe_id;
    IF v_gses IS NULL THEN
      total_sistema := 0; total_livres := 0; total_suspensos := 0;
      RETURN NEXT;
      RETURN;
    END IF;
  END IF;

  RETURN QUERY
  SELECT
    -- total_sistema = livres + suspensos (apenas ativos na fila, não conta finalizados)
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND (v_gses IS NULL OR t.gse = ANY(v_gses)))::bigint AS total_sistema,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND t.status = 'aguardando' AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NULL OR t.gse = ANY(v_gses)))::bigint AS total_livres,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND t.status = 'aguardando' AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = true
         AND (v_gses IS NULL OR t.gse = ANY(v_gses)))::bigint AS total_suspensos;
END;
$$;
GRANT EXECUTE ON FUNCTION public.sos_contar_tickets_unicos(uuid) TO authenticated;
NOTIFY pgrst, 'reload schema';

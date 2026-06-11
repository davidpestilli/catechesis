-- =====================================================
-- MIGRATION: SOS — separar contagens Livres x Suspensos
-- Data: 2026-04-24 (16h)
-- Bug fix: contagens do modal incluíam tickets suspensos,
-- gerando discrepância com a fila visível.
-- =====================================================

-- 1. Listagem admin com contagem detalhada (livres + suspensos)
DROP FUNCTION IF EXISTS public.sos_listar_palavras_admin();
CREATE OR REPLACE FUNCTION public.sos_listar_palavras_admin()
RETURNS TABLE(
  id uuid,
  palavra text,
  palavra_normalizada text,
  ativo boolean,
  total_tickets bigint,
  tickets_em_fila bigint,        -- mantido = LIVRES (compat. cliente antigo)
  tickets_livres bigint,
  tickets_suspensos bigint,
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
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras))::bigint AS total_tickets,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false)::bigint AS tickets_em_fila,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false)::bigint AS tickets_livres,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = true)::bigint AS tickets_suspensos,
    p.created_at
  FROM public.sos_palavras_chave p
  ORDER BY tickets_livres DESC, tickets_suspensos DESC, total_tickets DESC, p.palavra ASC;
END;
$$;
-- 2. Listagem por equipe — agora com flag p_suspenso
DROP FUNCTION IF EXISTS public.sos_listar_palavras_equipe(uuid, text);
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
-- 3. Contagem tickets únicos com SOS — separa livres e suspensos + escopo opcional por equipe
DROP FUNCTION IF EXISTS public.sos_contar_tickets_unicos();
CREATE OR REPLACE FUNCTION public.sos_contar_tickets_unicos(
  p_equipe_id uuid DEFAULT NULL
)
RETURNS TABLE(
  total_sistema bigint,
  total_livres bigint,
  total_suspensos bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  v_gses text[];
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
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
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

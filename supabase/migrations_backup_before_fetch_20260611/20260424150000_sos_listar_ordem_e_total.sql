-- =====================================================
-- MIGRATION: SOS — ordenar palavras por matches + total único de tickets
-- Data: 2026-04-24
-- =====================================================

-- 1. Atualiza listagem admin: ORDER BY tickets em fila DESC, total DESC
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
  ORDER BY tickets_em_fila DESC, total_tickets DESC, p.palavra ASC;
END;
$$;
-- 2. Nova RPC: contagem única de tickets com SOS
-- Conta tickets distintos onde sos = true (matches em comum NÃO contam duplicado,
-- pois o flag sos é por ticket, não por palavra).
CREATE OR REPLACE FUNCTION public.sos_contar_tickets_unicos()
RETURNS TABLE(
  total_sistema bigint,
  total_fila bigint
)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT
    (SELECT COUNT(*) FROM public.tickets WHERE sos = true)::bigint AS total_sistema,
    (SELECT COUNT(*) FROM public.tickets
       WHERE sos = true AND status = 'aguardando' AND usuario_atual IS NULL)::bigint AS total_fila;
$$;
GRANT EXECUTE ON FUNCTION public.sos_contar_tickets_unicos() TO authenticated;
NOTIFY pgrst, 'reload schema';

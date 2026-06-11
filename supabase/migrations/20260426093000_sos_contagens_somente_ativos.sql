-- Ajusta contagens SOS para considerar apenas tickets atualmente classificados como SOS.
-- Tickets desclassificados manualmente podem manter sos_palavras para auditoria/exibição,
-- mas não devem aparecer nas contagens do filtro nem do modal admin.

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
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS total_tickets,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_em_fila,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
         AND t.status = 'aguardando'
         AND t.usuario_atual IS NULL
         AND COALESCE(t.suspenso, false) = false
         AND (v_gses IS NOT NULL AND t.gse = ANY(v_gses)))::bigint AS tickets_livres,
    (SELECT COUNT(*) FROM public.tickets t
       WHERE t.sos = true
         AND p.palavra_normalizada = ANY(t.sos_palavras)
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
    AND t.sos = true
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

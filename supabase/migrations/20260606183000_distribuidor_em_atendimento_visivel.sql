-- =====================================================
-- DISTRIBUIDOR: estado "Em Atendimento por ..." visivel na fila
-- - Inclui tickets em atendimento na busca da fila livres
-- - Retorna dados do usuario_atual para UI
-- - Cria RPC para "Liberar do atendimento"
-- - Ajusta contadores livres/suspensos
-- =====================================================

DROP FUNCTION IF EXISTS public.dist_buscar_tickets_paginado(uuid, text, boolean, integer, integer, text, text, text, numeric, text, text, text);
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
  tempo_espera_origem timestamp,
  suspenso boolean,
  causa_suspensao text,
  mantido_por uuid,
  mantido_at timestamptz,
  mantido_por_nome text,
  mantido_por_email text,
  usuario_atual uuid,
  usuario_atual_nome text,
  usuario_atual_email text,
  chamado_global_id uuid,
  created_at timestamp,
  updated_at timestamp,
  total_count bigint
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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
    AND (
      (p_suspenso = true
        AND t.status = 'aguardando'
        AND t.suspenso = true
        AND t.usuario_atual IS NULL)
      OR
      (p_suspenso = false
        AND (
          (t.status = 'aguardando' AND t.suspenso = false)
          OR (t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL)
        ))
    )
    AND (p_origem IS NULL OR t.origem = p_origem)
    AND (p_filtro_categoria IS NULL OR ta.categoria_slug = p_filtro_categoria)
    AND (p_filtro_subcategoria IS NULL OR ta.subcategoria_slug = p_filtro_subcategoria)
    AND (
      p_filtro_mantido IS NULL
      OR p_filtro_mantido = 'todos'
      OR (t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL)
      OR (p_filtro_mantido = 'livres' AND t.mantido_por IS NULL)
      OR (p_filtro_mantido = 'mantidos' AND t.mantido_por IS NOT NULL)
      OR t.mantido_por::text = p_filtro_mantido
    )
    AND (p_filtro_numero IS NULL OR t.numero_chamado ILIKE '%' || p_filtro_numero || '%')
    AND (
      p_filtro_tempo_horas IS NULL
      OR (p_filtro_tempo_operador = 'maior'
          AND EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600 > p_filtro_tempo_horas)
      OR (p_filtro_tempo_operador = 'menor'
          AND EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600 < p_filtro_tempo_horas)
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
    u_hold.nome AS mantido_por_nome,
    u_hold.email AS mantido_por_email,
    t.usuario_atual,
    u_atual.nome AS usuario_atual_nome,
    u_atual.email AS usuario_atual_email,
    t.chamado_global_id,
    t.created_at,
    t.updated_at,
    v_total AS total_count
  FROM tickets t
  LEFT JOIN users u_hold ON u_hold.id = t.mantido_por
  LEFT JOIN users u_atual ON u_atual.id = t.usuario_atual
  LEFT JOIN ticket_analises ta ON ta.ticket_id = t.id
  WHERE t.gse = ANY(v_gses)
    AND (
      (p_suspenso = true
        AND t.status = 'aguardando'
        AND t.suspenso = true
        AND t.usuario_atual IS NULL)
      OR
      (p_suspenso = false
        AND (
          (t.status = 'aguardando' AND t.suspenso = false)
          OR (t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL)
        ))
    )
    AND (p_origem IS NULL OR t.origem = p_origem)
    AND (p_filtro_categoria IS NULL OR ta.categoria_slug = p_filtro_categoria)
    AND (p_filtro_subcategoria IS NULL OR ta.subcategoria_slug = p_filtro_subcategoria)
    AND (
      p_filtro_mantido IS NULL
      OR p_filtro_mantido = 'todos'
      OR (t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL)
      OR (p_filtro_mantido = 'livres' AND t.mantido_por IS NULL)
      OR (p_filtro_mantido = 'mantidos' AND t.mantido_por IS NOT NULL)
      OR t.mantido_por::text = p_filtro_mantido
    )
    AND (p_filtro_numero IS NULL OR t.numero_chamado ILIKE '%' || p_filtro_numero || '%')
    AND (
      p_filtro_tempo_horas IS NULL
      OR (p_filtro_tempo_operador = 'maior'
          AND EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600 > p_filtro_tempo_horas)
      OR (p_filtro_tempo_operador = 'menor'
          AND EXTRACT(EPOCH FROM (now() - t.tempo_espera_origem)) / 3600 < p_filtro_tempo_horas)
    )
    AND (
      p_filtro_sos IS NULL
      OR (p_filtro_sos = 'todas' AND t.sos = true)
      OR (v_sos_norm IS NOT NULL AND v_sos_norm = ANY(t.sos_palavras))
    )
  ORDER BY
    CASE
      WHEN t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL THEN 0
      ELSE 1
    END,
    CASE WHEN public.is_gse_homologacao(t.gse) THEN 0 ELSE 1 END,
    t.vip DESC,
    t.sos DESC,
    t.tempo_espera_origem ASC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;
GRANT EXECUTE ON FUNCTION public.dist_buscar_tickets_paginado(uuid, text, boolean, integer, integer, text, text, text, numeric, text, text, text) TO authenticated;
CREATE OR REPLACE FUNCTION public.dist_contar_tickets_fila(
  p_equipe_id uuid,
  p_origem text DEFAULT NULL::text
)
RETURNS TABLE(total_livres bigint, total_suspensos bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gses text[];
BEGIN
  SELECT array_agg(gse) INTO v_gses
  FROM gse_equipes
  WHERE equipe_id = p_equipe_id;

  IF v_gses IS NULL OR array_length(v_gses, 1) IS NULL THEN
    RETURN QUERY SELECT 0::bigint, 0::bigint;
    RETURN;
  END IF;

  RETURN QUERY
  SELECT
    COUNT(*) FILTER (
      WHERE (
        (t.status = 'aguardando' AND t.suspenso = false)
        OR (t.status IN ('atribuido', 'em_atendimento') AND t.usuario_atual IS NOT NULL)
      )
    )::bigint AS total_livres,
    COUNT(*) FILTER (
      WHERE t.status = 'aguardando'
        AND t.suspenso = true
        AND t.usuario_atual IS NULL
    )::bigint AS total_suspensos
  FROM tickets t
  WHERE t.gse = ANY(v_gses)
    AND (p_origem IS NULL OR t.origem = p_origem);
END;
$$;
GRANT EXECUTE ON FUNCTION public.dist_contar_tickets_fila(uuid, text) TO authenticated;
CREATE OR REPLACE FUNCTION public.dist_liberar_ticket_atendimento(
  p_ticket_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket tickets%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado';
  END IF;

  SELECT *
    INTO v_ticket
  FROM tickets
  WHERE id = p_ticket_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'reason', 'ticket_nao_encontrado');
  END IF;

  IF v_ticket.usuario_atual IS NULL OR v_ticket.status NOT IN ('atribuido', 'em_atendimento') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'ticket_nao_em_atendimento');
  END IF;

  IF v_ticket.usuario_atual IS DISTINCT FROM auth.uid()
     AND NOT public.tem_permissao('distribuidor.liberar_ticket_outro') THEN
    RETURN jsonb_build_object('success', false, 'reason', 'sem_permissao');
  END IF;

  UPDATE tickets
  SET
    usuario_atual = NULL,
    status = 'aguardando',
    mantido_por = NULL,
    mantido_at = NULL,
    assigned_at = NULL,
    started_at = NULL,
    finished_at = NULL,
    suspenso = false,
    updated_at = now()
  WHERE id = p_ticket_id;

  RETURN jsonb_build_object('success', true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.dist_liberar_ticket_atendimento(uuid) TO authenticated;

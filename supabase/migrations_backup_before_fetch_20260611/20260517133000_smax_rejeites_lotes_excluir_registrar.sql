-- =====================================================================
-- SMAX Rejeites - Acoes em lote para excluir e registrar/excluir
-- Bloqueia tickets mantidos por outros usuarios e agrega registro de
-- Resolucao de rejeites em um unico servico quando usado em lote.
-- =====================================================================

BEGIN;
CREATE OR REPLACE FUNCTION public.smax_rejeites_excluir(p_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_rejeite record;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_id IS NULL THEN
    RAISE EXCEPTION 'Rejeite obrigatorio';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  IF v_user_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao encontrado ou sem equipe';
  END IF;

  SELECT s.id,
         s.equipe_id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome AS mantido_por_nome,
         mantenedor.email AS mantido_por_email
    INTO v_rejeite
  FROM public.smax_rejeites_snapshot s
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.id = p_id
  FOR UPDATE OF s;

  IF v_rejeite.id IS NULL THEN
    RAISE EXCEPTION 'Rejeite nao encontrado';
  END IF;

  IF v_rejeite.equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para excluir este rejeite';
  END IF;

  IF v_rejeite.mantido_por IS NOT NULL AND v_rejeite.mantido_por IS DISTINCT FROM v_user_id THEN
    RETURN jsonb_build_object(
      'success', false,
      'reason', 'mantido_por_outro',
      'id', v_rejeite.id,
      'ticket_numero', v_rejeite.ticket_numero,
      'mantido_por', v_rejeite.mantido_por,
      'mantido_at', v_rejeite.mantido_at,
      'mantido_por_nome', v_rejeite.mantido_por_nome,
      'mantido_por_email', v_rejeite.mantido_por_email
    );
  END IF;

  DELETE FROM public.smax_rejeites_snapshot s
  WHERE s.id = v_rejeite.id;

  RETURN jsonb_build_object(
    'success', true,
    'id', v_rejeite.id,
    'ticket_numero', v_rejeite.ticket_numero
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_rejeites_excluir_lote(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_total_solicitado integer := 0;
  v_total_excluido integer := 0;
  v_total_bloqueado integer := 0;
  v_ids_excluidos jsonb := '[]'::jsonb;
  v_tickets_excluidos jsonb := '[]'::jsonb;
  v_tickets_bloqueados jsonb := '[]'::jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'total_solicitado', 0,
      'total_excluido', 0,
      'total_bloqueado', 0,
      'ids_excluidos', '[]'::jsonb,
      'tickets_excluidos', '[]'::jsonb,
      'tickets_bloqueados', '[]'::jsonb
    );
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  IF v_user_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao encontrado ou sem equipe';
  END IF;

  DROP TABLE IF EXISTS pg_temp.smax_rejeites_lote_solicitados;
  CREATE TEMP TABLE smax_rejeites_lote_solicitados (
    id uuid PRIMARY KEY,
    ticket_numero text NOT NULL,
    mantido_por uuid,
    mantido_at timestamptz,
    mantido_por_nome text,
    mantido_por_email text
  ) ON COMMIT DROP;

  INSERT INTO pg_temp.smax_rejeites_lote_solicitados (
    id,
    ticket_numero,
    mantido_por,
    mantido_at,
    mantido_por_nome,
    mantido_por_email
  )
  SELECT s.id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome,
         mantenedor.email
  FROM public.smax_rejeites_snapshot s
  JOIN (
    SELECT DISTINCT input.id
    FROM unnest(p_ids) AS input(id)
    WHERE input.id IS NOT NULL
  ) ids ON ids.id = s.id
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.equipe_id = v_user_equipe_id
  FOR UPDATE OF s;

  SELECT count(*)::integer
    INTO v_total_solicitado
  FROM pg_temp.smax_rejeites_lote_solicitados;

  SELECT count(*)::integer,
         COALESCE(jsonb_agg(
           jsonb_build_object(
             'id', id,
             'ticket_numero', ticket_numero,
             'mantido_por', mantido_por,
             'mantido_at', mantido_at,
             'mantido_por_nome', mantido_por_nome,
             'mantido_por_email', mantido_por_email
           ) ORDER BY ticket_numero
         ), '[]'::jsonb)
    INTO v_total_bloqueado,
         v_tickets_bloqueados
  FROM pg_temp.smax_rejeites_lote_solicitados
  WHERE mantido_por IS NOT NULL
    AND mantido_por IS DISTINCT FROM v_user_id;

  WITH excluidos AS (
    DELETE FROM public.smax_rejeites_snapshot s
    USING pg_temp.smax_rejeites_lote_solicitados solicitados
    WHERE s.id = solicitados.id
      AND (
        solicitados.mantido_por IS NULL
        OR solicitados.mantido_por = v_user_id
      )
    RETURNING s.id, s.ticket_numero
  )
  SELECT count(*)::integer,
         COALESCE(jsonb_agg(id ORDER BY ticket_numero), '[]'::jsonb),
         COALESCE(jsonb_agg(ticket_numero ORDER BY ticket_numero), '[]'::jsonb)
    INTO v_total_excluido,
         v_ids_excluidos,
         v_tickets_excluidos
  FROM excluidos;

  RETURN jsonb_build_object(
    'success', true,
    'total_solicitado', COALESCE(v_total_solicitado, 0),
    'total_excluido', COALESCE(v_total_excluido, 0),
    'total_bloqueado', COALESCE(v_total_bloqueado, 0),
    'ids_excluidos', COALESCE(v_ids_excluidos, '[]'::jsonb),
    'tickets_excluidos', COALESCE(v_tickets_excluidos, '[]'::jsonb),
    'tickets_bloqueados', COALESCE(v_tickets_bloqueados, '[]'::jsonb)
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_rejeites_registrar_e_excluir_lote(p_ids uuid[])
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_usuario_nome text;
  v_now timestamptz := now();
  v_total_solicitado integer := 0;
  v_total_processado integer := 0;
  v_total_bloqueado integer := 0;
  v_total_deletado integer := 0;
  v_ids_processados jsonb := '[]'::jsonb;
  v_tickets_processados jsonb := '[]'::jsonb;
  v_tickets_bloqueados jsonb := '[]'::jsonb;
  v_tickets_texto text;
  v_descricao text;
  v_servico_id uuid;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF p_ids IS NULL OR cardinality(p_ids) = 0 THEN
    RETURN jsonb_build_object(
      'success', true,
      'total_solicitado', 0,
      'total_processado', 0,
      'total_bloqueado', 0,
      'servico_id', NULL,
      'ids_processados', '[]'::jsonb,
      'tickets_processados', '[]'::jsonb,
      'descricao', NULL,
      'data_execucao', NULL,
      'tickets_bloqueados', '[]'::jsonb
    );
  END IF;

  SELECT u.equipe_id,
         COALESCE(u.nome, u.email, 'Usuario')
    INTO v_user_equipe_id,
         v_usuario_nome
  FROM public.users u
  WHERE u.id = v_user_id;

  IF v_user_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao encontrado ou sem equipe';
  END IF;

  DROP TABLE IF EXISTS pg_temp.smax_rejeites_registrar_lote_solicitados;
  CREATE TEMP TABLE smax_rejeites_registrar_lote_solicitados (
    id uuid PRIMARY KEY,
    ticket_numero text NOT NULL,
    mantido_por uuid,
    mantido_at timestamptz,
    mantido_por_nome text,
    mantido_por_email text
  ) ON COMMIT DROP;

  INSERT INTO pg_temp.smax_rejeites_registrar_lote_solicitados (
    id,
    ticket_numero,
    mantido_por,
    mantido_at,
    mantido_por_nome,
    mantido_por_email
  )
  SELECT s.id,
         s.ticket_numero,
         s.mantido_por,
         s.mantido_at,
         mantenedor.nome,
         mantenedor.email
  FROM public.smax_rejeites_snapshot s
  JOIN (
    SELECT DISTINCT input.id
    FROM unnest(p_ids) AS input(id)
    WHERE input.id IS NOT NULL
  ) ids ON ids.id = s.id
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  WHERE s.equipe_id = v_user_equipe_id
  FOR UPDATE OF s;

  SELECT count(*)::integer
    INTO v_total_solicitado
  FROM pg_temp.smax_rejeites_registrar_lote_solicitados;

  SELECT count(*)::integer,
         COALESCE(jsonb_agg(
           jsonb_build_object(
             'id', id,
             'ticket_numero', ticket_numero,
             'mantido_por', mantido_por,
             'mantido_at', mantido_at,
             'mantido_por_nome', mantido_por_nome,
             'mantido_por_email', mantido_por_email
           ) ORDER BY ticket_numero
         ), '[]'::jsonb)
    INTO v_total_bloqueado,
         v_tickets_bloqueados
  FROM pg_temp.smax_rejeites_registrar_lote_solicitados
  WHERE mantido_por IS NOT NULL
    AND mantido_por IS DISTINCT FROM v_user_id;

  SELECT count(*)::integer,
         COALESCE(jsonb_agg(id ORDER BY ticket_numero), '[]'::jsonb),
         COALESCE(jsonb_agg(ticket_numero ORDER BY ticket_numero), '[]'::jsonb),
         string_agg(ticket_numero, ', ' ORDER BY ticket_numero)
    INTO v_total_processado,
         v_ids_processados,
         v_tickets_processados,
         v_tickets_texto
  FROM pg_temp.smax_rejeites_registrar_lote_solicitados
  WHERE mantido_por IS NULL
     OR mantido_por = v_user_id;

  IF COALESCE(v_total_processado, 0) > 0 THEN
    v_descricao := CASE
      WHEN v_total_processado = 1 THEN 'Respondi ao ticket ' || v_tickets_texto
      ELSE 'Respondi aos tickets ' || v_tickets_texto
    END;

    INSERT INTO public.servicos (
      tipo,
      quantidade,
      usuario_id,
      usuario_nome,
      equipe_id,
      observacao,
      data_execucao,
      descricao
    )
    VALUES (
      'analise_rejeites',
      v_total_processado,
      v_user_id,
      v_usuario_nome,
      v_user_equipe_id,
      NULL,
      v_now,
      v_descricao
    )
    RETURNING id INTO v_servico_id;

    DELETE FROM public.smax_rejeites_snapshot s
    USING pg_temp.smax_rejeites_registrar_lote_solicitados solicitados
    WHERE s.id = solicitados.id
      AND (
        solicitados.mantido_por IS NULL
        OR solicitados.mantido_por = v_user_id
      );

    GET DIAGNOSTICS v_total_deletado = ROW_COUNT;

    IF v_total_deletado IS DISTINCT FROM v_total_processado THEN
      RAISE EXCEPTION 'Falha ao excluir todos os rejeites registrados';
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'total_solicitado', COALESCE(v_total_solicitado, 0),
    'total_processado', COALESCE(v_total_processado, 0),
    'total_bloqueado', COALESCE(v_total_bloqueado, 0),
    'servico_id', v_servico_id,
    'ids_processados', COALESCE(v_ids_processados, '[]'::jsonb),
    'tickets_processados', COALESCE(v_tickets_processados, '[]'::jsonb),
    'descricao', v_descricao,
    'data_execucao', CASE WHEN v_servico_id IS NULL THEN NULL ELSE v_now END,
    'tickets_bloqueados', COALESCE(v_tickets_bloqueados, '[]'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_rejeites_excluir(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_rejeites_excluir_lote(uuid[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_rejeites_registrar_e_excluir_lote(uuid[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_excluir(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_excluir_lote(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_rejeites_registrar_e_excluir_lote(uuid[]) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

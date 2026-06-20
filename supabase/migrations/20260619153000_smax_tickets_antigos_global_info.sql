CREATE OR REPLACE FUNCTION public.smax_tickets_antigos_listar(p_equipe_id uuid DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_user_equipe_id uuid;
  v_equipe_id uuid;
  v_meta jsonb := NULL;
  v_registros jsonb := '[]'::jsonb;
  v_por_usuario jsonb := '[]'::jsonb;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  SELECT u.equipe_id
    INTO v_user_equipe_id
  FROM public.users u
  WHERE u.id = v_user_id;

  v_equipe_id := COALESCE(p_equipe_id, v_user_equipe_id);

  IF v_equipe_id IS NULL THEN
    RETURN jsonb_build_object('meta', NULL, 'registros', '[]'::jsonb, 'por_usuario', '[]'::jsonb);
  END IF;

  IF v_equipe_id IS DISTINCT FROM v_user_equipe_id THEN
    RAISE EXCEPTION 'Usuario sem permissao para consultar esta equipe';
  END IF;

  SELECT to_jsonb(m)
    INTO v_meta
  FROM public.smax_tickets_antigos_snapshot_meta m
  WHERE m.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', s.id,
      'equipe_id', s.equipe_id,
      'user_id', s.user_id,
      'usuario_nome', CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE COALESCE(u.nome, s.smax_nome)
      END,
      'usuario_email', u.email,
      'smax_nome', s.smax_nome,
      'smax_nome_original', s.smax_nome_original,
      'ticket_numero', s.ticket_numero,
      'hora_criacao', s.hora_criacao,
      'ultima_atualizacao', s.ultima_atualizacao,
      'solicitante_email', s.solicitante_email,
      'total_mesmo_solicitante', s.total_mesmo_solicitante,
      'smax_url', s.smax_url,
      'capturado_em', s.capturado_em,
      'mapeado', s.mapeado,
      'grupo_rejeite', s.grupo_rejeite,
      'mantido_por', s.mantido_por,
      'mantido_at', s.mantido_at,
      'mantido_por_nome', mantenedor.nome,
      'mantido_por_email', mantenedor.email,
      'respondendo_por', s.respondendo_por,
      'respondendo_at', s.respondendo_at,
      'respondendo_por_nome', respondente.nome,
      'respondendo_por_email', respondente.email,
      'chamado_global_id', global_info.chamado_global_id,
      'global_numero', global_info.global_numero,
      'global_nome', global_info.global_nome,
      'global_ativo', global_info.global_ativo
    )
    ORDER BY s.hora_criacao DESC, s.ticket_numero
  ), '[]'::jsonb)
    INTO v_registros
  FROM public.smax_tickets_antigos_snapshot s
  LEFT JOIN public.users u ON u.id = s.user_id
  LEFT JOIN public.users mantenedor ON mantenedor.id = s.mantido_por
  LEFT JOIN public.users respondente ON respondente.id = s.respondendo_por
  LEFT JOIN LATERAL (
    SELECT
      tg.chamado_global_id,
      cg.numero AS global_numero,
      cg.nome AS global_nome,
      cg.ativo AS global_ativo
    FROM public.tickets t
    JOIN public.tickets_globais tg ON tg.ticket_id = t.id
    JOIN public.chamados_globais cg ON cg.id = tg.chamado_global_id
    WHERE t.numero_chamado = s.ticket_numero
    ORDER BY tg.anexado_at DESC, tg.id DESC
    LIMIT 1
  ) global_info ON TRUE
  WHERE s.equipe_id = v_equipe_id;

  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'user_id', grouped.user_id,
      'usuario_nome', grouped.usuario_nome,
      'smax_nome', grouped.smax_nome,
      'total', grouped.total,
      'hora_criacao', grouped.hora_criacao,
      'ultima_atualizacao', grouped.hora_criacao,
      'mapeado', grouped.mapeado,
      'grupo_rejeite', grouped.grupo_rejeite
    )
    ORDER BY grouped.usuario_nome, grouped.hora_criacao DESC
  ), '[]'::jsonb)
    INTO v_por_usuario
  FROM (
    SELECT
      CASE WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN NULL ELSE s.user_id END AS user_id,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE COALESCE(u.nome, s.smax_nome)
      END AS usuario_nome,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE s.smax_nome
      END AS smax_nome,
      count(*)::integer AS total,
      max(s.hora_criacao) AS hora_criacao,
      bool_and(s.mapeado) AS mapeado,
      s.grupo_rejeite
    FROM public.smax_tickets_antigos_snapshot s
    LEFT JOIN public.users u ON u.id = s.user_id
    WHERE s.equipe_id = v_equipe_id
    GROUP BY
      CASE WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN NULL ELSE s.user_id END,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE COALESCE(u.nome, s.smax_nome)
      END,
      CASE
        WHEN s.grupo_rejeite = 'externo_ou_sem_usuario' THEN 'Usuarios externos e ticket sem usuario'
        ELSE s.smax_nome
      END,
      s.grupo_rejeite
  ) grouped;

  RETURN jsonb_build_object(
    'meta', v_meta,
    'registros', v_registros,
    'por_usuario', v_por_usuario
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_tickets_antigos_listar(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_tickets_antigos_listar(uuid) TO authenticated;

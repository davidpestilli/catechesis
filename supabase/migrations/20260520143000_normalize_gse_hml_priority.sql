BEGIN;
CREATE OR REPLACE FUNCTION public.normalizar_gse(p_gse text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v text;
BEGIN
  IF p_gse IS NULL THEN
    RETURN NULL;
  END IF;

  v := p_gse;
  v := replace(v, chr(160), ' ');
  v := replace(v, chr(5760), ' ');
  v := replace(v, chr(6158), ' ');
  v := replace(v, chr(8192), ' ');
  v := replace(v, chr(8193), ' ');
  v := replace(v, chr(8194), ' ');
  v := replace(v, chr(8195), ' ');
  v := replace(v, chr(8196), ' ');
  v := replace(v, chr(8197), ' ');
  v := replace(v, chr(8198), ' ');
  v := replace(v, chr(8199), ' ');
  v := replace(v, chr(8200), ' ');
  v := replace(v, chr(8201), ' ');
  v := replace(v, chr(8202), ' ');
  v := replace(v, chr(8239), ' ');
  v := replace(v, chr(8287), ' ');
  v := replace(v, chr(12288), ' ');
  v := replace(v, chr(8203), '');
  v := replace(v, chr(8204), '');
  v := replace(v, chr(8205), '');
  v := replace(v, chr(65279), '');
  v := replace(v, chr(8208), '-');
  v := replace(v, chr(8209), '-');
  v := replace(v, chr(8210), '-');
  v := replace(v, chr(8211), '-');
  v := replace(v, chr(8212), '-');
  v := replace(v, chr(8213), '-');
  v := replace(v, chr(8722), '-');
  v := regexp_replace(v, '[[:space:]]*-[[:space:]]*', ' - ', 'g');
  v := regexp_replace(v, '[[:space:]]+', ' ', 'g');
  v := upper(btrim(v));
  v := replace(v, 'HOMOLOGA' || chr(199) || chr(195) || 'O', 'HOMOLOGACAO');

  RETURN NULLIF(v, '');
END;
$$;
CREATE OR REPLACE FUNCTION public.is_gse_homologacao(p_gse text)
RETURNS boolean
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT public.normalizar_gse(p_gse) = 'GSE - SGS - EPROC - HOMOLOGACAO';
$$;
GRANT EXECUTE ON FUNCTION public.normalizar_gse(text) TO anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_gse_homologacao(text) TO anon, authenticated, service_role;
DO $$
DECLARE
  v_conflicts jsonb;
BEGIN
  SELECT jsonb_agg(
           jsonb_build_object(
             'gse_normalizado', gse_normalizado,
             'valores', valores,
             'equipes', equipes
           )
         )
  INTO v_conflicts
  FROM (
    SELECT
      public.normalizar_gse(gse) AS gse_normalizado,
      array_agg(gse ORDER BY gse) AS valores,
      array_agg(DISTINCT equipe_id ORDER BY equipe_id) AS equipes
    FROM public.gse_equipes
    GROUP BY public.normalizar_gse(gse)
    HAVING count(DISTINCT equipe_id) > 1
  ) conflitos;

  IF v_conflicts IS NOT NULL THEN
    RAISE EXCEPTION 'Conflito de GSE normalizado entre equipes: %', v_conflicts;
  END IF;
END;
$$;
WITH ranked AS (
  SELECT
    id,
    row_number() OVER (
      PARTITION BY public.normalizar_gse(gse), equipe_id
      ORDER BY created_at NULLS LAST, id
    ) AS rn
  FROM public.gse_equipes
)
DELETE FROM public.gse_equipes ge
USING ranked r
WHERE ge.id = r.id
  AND r.rn > 1;
UPDATE public.gse_equipes ge
SET gse = public.normalizar_gse(ge.gse)
WHERE ge.gse IS DISTINCT FROM public.normalizar_gse(ge.gse);
INSERT INTO public.gse_equipes (gse, equipe_id)
SELECT 'GSE - SGS - EPROC - HOMOLOGACAO', e.id
FROM public.equipes e
WHERE e.sgs_codigo = '2.3.2'
ORDER BY e.created_at NULLS LAST, e.id
LIMIT 1
ON CONFLICT (gse) DO UPDATE
SET equipe_id = EXCLUDED.equipe_id;
UPDATE public.tickets t
SET gse = public.normalizar_gse(t.gse)
WHERE t.gse IS DISTINCT FROM public.normalizar_gse(t.gse);
CREATE OR REPLACE FUNCTION public.tg_normalizar_gse_tickets()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.gse := public.normalizar_gse(NEW.gse);
  IF NEW.gse IS NULL THEN
    RAISE EXCEPTION 'GSE do ticket nao pode ser vazio';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_normalizar_gse_tickets ON public.tickets;
CREATE TRIGGER trg_normalizar_gse_tickets
BEFORE INSERT OR UPDATE OF gse
ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION public.tg_normalizar_gse_tickets();
CREATE OR REPLACE FUNCTION public.tg_normalizar_gse_equipes()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.gse := public.normalizar_gse(NEW.gse);
  IF NEW.gse IS NULL THEN
    RAISE EXCEPTION 'GSE da equipe nao pode ser vazio';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_normalizar_gse_equipes ON public.gse_equipes;
CREATE TRIGGER trg_normalizar_gse_equipes
BEFORE INSERT OR UPDATE OF gse
ON public.gse_equipes
FOR EACH ROW
EXECUTE FUNCTION public.tg_normalizar_gse_equipes();
CREATE OR REPLACE FUNCTION public.admin_criar_gse(p_gse text, p_equipe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gse_id uuid;
  v_gse text;
BEGIN
  IF NOT is_boss() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado');
  END IF;

  v_gse := public.normalizar_gse(p_gse);

  IF v_gse IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'GSE e obrigatorio');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM equipes WHERE id = p_equipe_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Equipe nao encontrada');
  END IF;

  IF EXISTS (SELECT 1 FROM gse_equipes WHERE public.normalizar_gse(gse) = v_gse) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Este GSE ja esta vinculado a uma equipe');
  END IF;

  INSERT INTO gse_equipes (gse, equipe_id)
  VALUES (v_gse, p_equipe_id)
  RETURNING id INTO v_gse_id;

  RETURN jsonb_build_object('success', true, 'id', v_gse_id, 'message', 'GSE criado');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
CREATE OR REPLACE FUNCTION public.admin_atualizar_gse(p_id uuid, p_gse text, p_equipe_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_gse text;
BEGIN
  IF NOT is_boss() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado');
  END IF;

  v_gse := public.normalizar_gse(p_gse);

  IF v_gse IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'GSE e obrigatorio');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM gse_equipes WHERE id = p_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'GSE nao encontrado');
  END IF;

  IF NOT EXISTS (SELECT 1 FROM equipes WHERE id = p_equipe_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Equipe nao encontrada');
  END IF;

  IF EXISTS (SELECT 1 FROM gse_equipes WHERE public.normalizar_gse(gse) = v_gse AND id != p_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Este GSE ja esta vinculado a uma equipe');
  END IF;

  UPDATE gse_equipes
  SET gse = v_gse,
      equipe_id = p_equipe_id
  WHERE id = p_id;

  RETURN jsonb_build_object('success', true, 'message', 'GSE atualizado');
EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$;
CREATE OR REPLACE FUNCTION public.get_ticket_equipe_id(p_gse text)
RETURNS uuid
LANGUAGE sql
STABLE
AS $$
  SELECT ge.equipe_id
  FROM public.gse_equipes ge
  WHERE public.normalizar_gse(ge.gse) = public.normalizar_gse(p_gse)
  LIMIT 1;
$$;
CREATE OR REPLACE FUNCTION public.set_mention_equipe_nome()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT ge.equipe_id, e.nome
  INTO NEW.ticket_equipe_id, NEW.ticket_equipe_nome
  FROM public.tickets t
  JOIN public.gse_equipes ge ON public.normalizar_gse(ge.gse) = public.normalizar_gse(t.gse)
  JOIN public.equipes e ON e.id = ge.equipe_id
  WHERE t.id = NEW.ticket_id
  LIMIT 1;

  RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION public.set_team_mention_equipe_nome()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  SELECT ge.equipe_id, e.nome
  INTO NEW.ticket_equipe_id, NEW.ticket_equipe_nome
  FROM public.tickets t
  JOIN public.gse_equipes ge ON public.normalizar_gse(ge.gse) = public.normalizar_gse(t.gse)
  JOIN public.equipes e ON e.id = ge.equipe_id
  WHERE t.id = NEW.ticket_id
  LIMIT 1;

  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trigger_set_team_mention_equipe_nome ON public.user_team_mentions;
CREATE TRIGGER trigger_set_team_mention_equipe_nome
BEFORE INSERT ON public.user_team_mentions
FOR EACH ROW
EXECUTE FUNCTION public.set_team_mention_equipe_nome();
UPDATE public.user_mentions um
SET ticket_equipe_id = resolved.equipe_id,
    ticket_equipe_nome = resolved.equipe_nome
FROM (
  SELECT t.id AS ticket_id, ge.equipe_id, e.nome AS equipe_nome
  FROM public.tickets t
  JOIN public.gse_equipes ge ON public.normalizar_gse(ge.gse) = public.normalizar_gse(t.gse)
  JOIN public.equipes e ON e.id = ge.equipe_id
) resolved
WHERE um.ticket_id = resolved.ticket_id
  AND (
    um.ticket_equipe_id IS DISTINCT FROM resolved.equipe_id
    OR um.ticket_equipe_nome IS DISTINCT FROM resolved.equipe_nome
  );
UPDATE public.user_team_mentions utm
SET ticket_equipe_id = resolved.equipe_id,
    ticket_equipe_nome = resolved.equipe_nome
FROM (
  SELECT t.id AS ticket_id, ge.equipe_id, e.nome AS equipe_nome
  FROM public.tickets t
  JOIN public.gse_equipes ge ON public.normalizar_gse(ge.gse) = public.normalizar_gse(t.gse)
  JOIN public.equipes e ON e.id = ge.equipe_id
) resolved
WHERE utm.ticket_id = resolved.ticket_id
  AND (
    utm.ticket_equipe_id IS DISTINCT FROM resolved.equipe_id
    OR utm.ticket_equipe_nome IS DISTINCT FROM resolved.equipe_nome
  );
CREATE OR REPLACE FUNCTION public.notificar_movimentacao_ticket(
  p_numero_chamado text,
  p_novo_gse text,
  p_descricao text DEFAULT ''::text,
  p_email text DEFAULT ''::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket_id uuid;
  v_gse_atual text;
  v_gse_atual_norm text;
  v_gse_email text;
  v_status_atual text;
  v_causa_suspensao_atual text;
  v_suspenso_atual boolean;
  v_ticket_origem text;
  v_mensagem text;
  v_mensagem_id uuid;
  v_system_user_id uuid := '00000000-0000-0000-0000-000000000001';
  v_data_movimentacao text;
  v_equipe_id uuid;
  v_equipe_nome text;
  v_member_ids uuid[];
  v_dpestilli_id uuid;
BEGIN
  v_data_movimentacao := to_char(now() AT TIME ZONE 'America/Sao_Paulo', 'DD/MM/YYYY "as" HH24:MI');
  v_gse_email := public.normalizar_gse(p_novo_gse);

  SELECT id, gse, public.normalizar_gse(gse), status, causa_suspensao, suspenso, COALESCE(origem, 'email')
  INTO v_ticket_id, v_gse_atual, v_gse_atual_norm, v_status_atual, v_causa_suspensao_atual, v_suspenso_atual, v_ticket_origem
  FROM tickets
  WHERE numero_chamado = p_numero_chamado;

  IF v_ticket_id IS NULL THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', format('Ticket com numero_chamado=%s nao encontrado', p_numero_chamado)
    );
  END IF;

  IF v_gse_email IS NOT NULL
     AND v_gse_atual_norm = v_gse_email
     AND v_gse_atual IS DISTINCT FROM v_gse_email
  THEN
    UPDATE tickets
    SET gse = v_gse_email
    WHERE id = v_ticket_id;

    v_gse_atual := v_gse_email;
    v_gse_atual_norm := v_gse_email;
  END IF;

  SELECT ge.equipe_id, e.nome
  INTO v_equipe_id, v_equipe_nome
  FROM gse_equipes ge
  JOIN equipes e ON e.id = ge.equipe_id
  WHERE public.normalizar_gse(ge.gse) = v_gse_atual_norm
  LIMIT 1;

  SELECT id INTO v_dpestilli_id
  FROM users
  WHERE email ILIKE '%dpestilli%' OR nome ILIKE '%dpestilli%'
  LIMIT 1;

  IF v_dpestilli_id IS NOT NULL THEN
    IF EXISTS (
      SELECT 1 FROM user_mentions
      WHERE ticket_id = v_ticket_id
        AND mentioned_user_id = v_dpestilli_id
        AND created_at > now() - interval '5 minutes'
    ) THEN
      RETURN jsonb_build_object(
        'sucesso', true,
        'ticket_id', v_ticket_id,
        'acao', 'dedup_ignorado',
        'motivo', 'Notificacao ja enviada nos ultimos 5 minutos'
      );
    END IF;
  END IF;

  v_mensagem := format(
    E'**Tentativa de insercao de ticket duplicado** (%s)\n\n@dpestilli',
    v_data_movimentacao
  );

  IF v_dpestilli_id IS NOT NULL THEN
    v_member_ids := ARRAY[v_dpestilli_id];
  ELSE
    v_member_ids := '{}';
  END IF;

  INSERT INTO ticket_messages (ticket_id, user_id, user_name, user_email, message, mentioned_user_ids)
  VALUES (
    v_ticket_id,
    v_system_user_id,
    'Sistema',
    'sistema@gerenciador.local',
    v_mensagem,
    v_member_ids
  )
  RETURNING id INTO v_mensagem_id;

  IF v_dpestilli_id IS NOT NULL AND v_mensagem_id IS NOT NULL THEN
    INSERT INTO user_mentions (
      message_id,
      ticket_id,
      mentioned_user_id,
      mentioner_user_id,
      ticket_numero,
      ticket_origem,
      ticket_fila,
      ticket_equipe_id,
      ticket_equipe_nome
    )
    VALUES (
      v_mensagem_id,
      v_ticket_id,
      v_dpestilli_id,
      v_system_user_id,
      p_numero_chamado,
      v_ticket_origem,
      CASE WHEN v_suspenso_atual THEN 'suspensos' ELSE 'livres' END,
      v_equipe_id,
      v_equipe_nome
    )
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN jsonb_build_object(
    'sucesso', true,
    'ticket_id', v_ticket_id,
    'gse_atual', v_gse_atual,
    'gse_email', v_gse_email,
    'status_atual', v_status_atual,
    'suspenso_atual', v_suspenso_atual,
    'equipe_nome', v_equipe_nome,
    'mensagem_id', v_mensagem_id,
    'dpestilli_id', v_dpestilli_id
  );
END;
$$;
CREATE OR REPLACE FUNCTION public.notify_subscribers_on_message()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_subscriber record;
  v_ticket_numero varchar;
  v_ticket_origem varchar;
  v_ticket_fila varchar;
  v_ticket_equipe_id uuid;
  v_ticket_equipe_nome varchar;
BEGIN
  SELECT
    t.numero_chamado,
    t.origem,
    CASE WHEN t.suspenso THEN 'suspensos' ELSE 'livres' END,
    ge.equipe_id,
    e.nome
  INTO v_ticket_numero, v_ticket_origem, v_ticket_fila, v_ticket_equipe_id, v_ticket_equipe_nome
  FROM tickets t
  LEFT JOIN gse_equipes ge ON public.normalizar_gse(ge.gse) = public.normalizar_gse(t.gse)
  LEFT JOIN equipes e ON e.id = ge.equipe_id
  WHERE t.id = NEW.ticket_id;

  IF v_ticket_numero IS NULL THEN
    RETURN NEW;
  END IF;

  FOR v_subscriber IN
    SELECT tcs.user_id
    FROM ticket_chat_subscribers tcs
    WHERE tcs.ticket_id = NEW.ticket_id
      AND tcs.is_active = true
      AND tcs.user_id != NEW.user_id
      AND tcs.user_id != ALL(COALESCE(NEW.mentioned_user_ids, '{}'))
  LOOP
    INSERT INTO user_mentions (
      message_id,
      ticket_id,
      mentioned_user_id,
      mentioner_user_id,
      ticket_numero,
      ticket_origem,
      ticket_fila,
      ticket_equipe_id,
      ticket_equipe_nome,
      is_read,
      is_auto_notification
    )
    VALUES (
      NEW.id,
      NEW.ticket_id,
      v_subscriber.user_id,
      NEW.user_id,
      v_ticket_numero,
      COALESCE(v_ticket_origem, 'email'),
      v_ticket_fila,
      v_ticket_equipe_id,
      v_ticket_equipe_nome,
      false,
      true
    )
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN NEW;
END;
$$;
CREATE OR REPLACE FUNCTION public.tickets_sos_evaluate_trigger()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_equipe_id uuid;
BEGIN
  SELECT ge.equipe_id INTO v_equipe_id
  FROM public.gse_equipes ge
  WHERE public.normalizar_gse(ge.gse) = public.normalizar_gse(NEW.gse)
  LIMIT 1;

  IF v_equipe_id IS NULL THEN
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
DROP TRIGGER IF EXISTS trg_tickets_sos_evaluate ON public.tickets;
CREATE TRIGGER trg_tickets_sos_evaluate
BEFORE INSERT OR UPDATE OF descricao, sos_override, gse
ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION public.tickets_sos_evaluate_trigger();
DROP FUNCTION IF EXISTS public.dist_buscar_tickets_paginado(uuid, text, boolean, integer, integer, text, text, text, numeric, text, text);
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
    CASE WHEN public.is_gse_homologacao(t.gse) THEN 0 ELSE 1 END,
    t.vip DESC,
    t.sos DESC,
    t.tempo_espera_origem ASC
  LIMIT p_limit
  OFFSET p_offset;
END;
$$;
GRANT EXECUTE ON FUNCTION public.dist_buscar_tickets_paginado(uuid, text, boolean, integer, integer, text, text, text, numeric, text, text, text) TO authenticated;
CREATE OR REPLACE FUNCTION public.buscar_tickets_fts(
  p_query text,
  p_equipe_id uuid,
  p_origem text DEFAULT NULL::text,
  p_limit integer DEFAULT 100
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_tsquery tsquery;
  v_clean_query text;
  v_gse_list text[];
  v_result jsonb;
BEGIN
  IF p_query IS NULL OR trim(p_query) = '' THEN
    RETURN '[]'::jsonb;
  END IF;

  IF p_equipe_id IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  v_clean_query := trim(p_query);

  SELECT array_agg(ge.gse)
  INTO v_gse_list
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  IF v_gse_list IS NULL OR array_length(v_gse_list, 1) IS NULL THEN
    RETURN '[]'::jsonb;
  END IF;

  BEGIN
    v_tsquery := websearch_to_tsquery('portuguese', public.f_unaccent(v_clean_query));
  EXCEPTION WHEN OTHERS THEN
    BEGIN
      v_tsquery := plainto_tsquery('portuguese', public.f_unaccent(v_clean_query));
    EXCEPTION WHEN OTHERS THEN
      RETURN '[]'::jsonb;
    END;
  END;

  SELECT COALESCE(jsonb_agg(row_to_json(subq)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      t.id,
      t.numero_chamado,
      t.gse,
      t.tempo_espera_origem,
      t.descricao,
      t.email,
      t.vip,
      t.sos,
      t.sos_palavras,
      t.sos_override,
      t.is_reopened,
      t.suspenso,
      t.causa_suspensao,
      t.comentario,
      t.resposta_ia,
      t.origem,
      t.status,
      t.created_at,
      t.updated_at,
      t.assigned_at,
      t.started_at,
      t.finished_at,
      t.version,
      t.mantido_por,
      t.mantido_at,
      t.usuario_atual,
      ts_rank_cd(t.search_vector_descricao, v_tsquery) AS fts_rank,
      'fts' AS match_type
    FROM public.tickets t
    WHERE t.gse = ANY(v_gse_list)
      AND t.status = 'aguardando'
      AND t.suspenso = false
      AND t.usuario_atual IS NULL
      AND (p_origem IS NULL OR t.origem::text = p_origem)
      AND t.search_vector_descricao @@ v_tsquery
    ORDER BY
      CASE WHEN public.is_gse_homologacao(t.gse) THEN 0 ELSE 1 END,
      t.vip DESC,
      ts_rank_cd(t.search_vector_descricao, v_tsquery) DESC
    LIMIT p_limit
  ) subq;

  IF jsonb_array_length(v_result) > 0 THEN
    RETURN v_result;
  END IF;

  SELECT COALESCE(jsonb_agg(row_to_json(subq)), '[]'::jsonb)
  INTO v_result
  FROM (
    SELECT
      t.id,
      t.numero_chamado,
      t.gse,
      t.tempo_espera_origem,
      t.descricao,
      t.email,
      t.vip,
      t.sos,
      t.sos_palavras,
      t.sos_override,
      t.is_reopened,
      t.suspenso,
      t.causa_suspensao,
      t.comentario,
      t.resposta_ia,
      t.origem,
      t.status,
      t.created_at,
      t.updated_at,
      t.assigned_at,
      t.started_at,
      t.finished_at,
      t.version,
      t.mantido_por,
      t.mantido_at,
      t.usuario_atual,
      similarity(public.f_unaccent(coalesce(t.descricao, '')), public.f_unaccent(v_clean_query)) AS fts_rank,
      'ilike' AS match_type
    FROM public.tickets t
    WHERE t.gse = ANY(v_gse_list)
      AND t.status = 'aguardando'
      AND t.suspenso = false
      AND t.usuario_atual IS NULL
      AND (p_origem IS NULL OR t.origem::text = p_origem)
      AND public.f_unaccent(coalesce(t.descricao, '')) ILIKE '%' || public.f_unaccent(v_clean_query) || '%'
    ORDER BY
      CASE WHEN public.is_gse_homologacao(t.gse) THEN 0 ELSE 1 END,
      t.vip DESC,
      similarity(public.f_unaccent(coalesce(t.descricao, '')), public.f_unaccent(v_clean_query)) DESC
    LIMIT p_limit
  ) subq;

  RETURN v_result;
END;
$$;
UPDATE public.tickets
SET gse = gse
WHERE public.is_gse_homologacao(gse);
NOTIFY pgrst, 'reload schema';
COMMIT;

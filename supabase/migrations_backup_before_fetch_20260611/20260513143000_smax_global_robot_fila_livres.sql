-- =====================================================
-- SMAX Global Robot - fila Livres com mantidos
-- Corrige a conferência/anexação para comparar apenas com a
-- fila Livres da equipe, incluindo tickets já mantidos por usuário.
-- =====================================================

BEGIN;
CREATE OR REPLACE FUNCTION public.smax_global_classificar_numeros(
  p_equipe_id uuid,
  p_global_id uuid,
  p_numeros text[]
)
RETURNS TABLE(
  numero_pesquisado text,
  ticket_id uuid,
  numero_chamado text,
  gse text,
  descricao text,
  status text,
  suspenso boolean,
  mantido_por uuid,
  mantido_por_email text,
  chamado_global_id uuid,
  motivo text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_global record;
  v_gses text[] := ARRAY[]::text[];
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Usuario nao autenticado';
  END IF;

  IF NOT public.tem_permissao('distribuidor.smax_robo_dev') THEN
    RAISE EXCEPTION 'Usuario sem permissao para executar o robo SMAX Global';
  END IF;

  IF p_equipe_id IS NULL THEN
    RAISE EXCEPTION 'Equipe obrigatoria';
  END IF;

  IF p_global_id IS NULL THEN
    RAISE EXCEPTION 'Global obrigatorio';
  END IF;

  SELECT cg.id, cg.numero, cg.equipe_id
    INTO v_global
  FROM public.chamados_globais cg
  WHERE cg.id = p_global_id
    AND cg.ativo = true;

  IF v_global.id IS NULL THEN
    RAISE EXCEPTION 'Chamado global nao encontrado ou encerrado';
  END IF;

  IF v_global.equipe_id <> p_equipe_id THEN
    RAISE EXCEPTION 'Chamado global nao pertence a equipe selecionada';
  END IF;

  SELECT COALESCE(array_agg(ge.gse), ARRAY[]::text[])
    INTO v_gses
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  RETURN QUERY
  WITH entrada AS (
    SELECT DISTINCT regexp_replace(trim(raw.numero), '[^0-9]', '', 'g') AS numero
    FROM unnest(COALESCE(p_numeros, ARRAY[]::text[])) AS raw(numero)
    WHERE regexp_replace(trim(COALESCE(raw.numero, '')), '[^0-9]', '', 'g') <> ''
  ),
  candidatos AS (
    SELECT
      e.numero AS numero_pesquisado,
      t.id AS ticket_uuid,
      t.numero_chamado,
      t.gse,
      t.descricao,
      t.status::text AS ticket_status,
      COALESCE(t.suspenso, false) AS ticket_suspenso,
      t.mantido_por,
      u.email AS mantido_por_email,
      t.chamado_global_id,
      tg.ticket_id AS vinculo_ticket_uuid,
      t.usuario_atual
    FROM entrada e
    LEFT JOIN public.tickets t ON t.numero_chamado = e.numero
    LEFT JOIN public.users u ON u.id = t.mantido_por
    LEFT JOIN public.tickets_globais tg ON tg.ticket_id = t.id
  )
  SELECT
    c.numero_pesquisado,
    c.ticket_uuid,
    c.numero_chamado,
    c.gse,
    c.descricao,
    c.ticket_status,
    c.ticket_suspenso,
    c.mantido_por,
    c.mantido_por_email,
    c.chamado_global_id,
    CASE
      WHEN c.ticket_uuid IS NULL THEN 'nao_encontrado'
      WHEN c.gse IS NULL OR NOT (c.gse = ANY(v_gses)) THEN 'fora_da_equipe'
      WHEN c.vinculo_ticket_uuid IS NOT NULL OR c.chamado_global_id IS NOT NULL THEN 'ja_em_global'
      WHEN c.ticket_suspenso THEN 'suspenso'
      WHEN c.ticket_status IS DISTINCT FROM 'aguardando' OR c.usuario_atual IS NOT NULL THEN 'status_invalido'
      ELSE 'livre'
    END AS motivo
  FROM candidatos c
  ORDER BY c.numero_pesquisado;
END;
$$;
CREATE OR REPLACE FUNCTION public.smax_global_anexar_livres(
  p_equipe_id uuid,
  p_global_id uuid,
  p_numeros text[]
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id uuid := auth.uid();
  v_global_numero text;
  v_gses text[] := ARRAY[]::text[];
  v_now timestamptz := now();
  v_anexados_ids uuid[] := ARRAY[]::uuid[];
  v_anexados jsonb := '[]'::jsonb;
  v_ignorados jsonb := '[]'::jsonb;
  v_por_motivo jsonb := '{}'::jsonb;
  v_total_anexados integer := 0;
  v_total_ignorados integer := 0;
BEGIN
  PERFORM 1
  FROM public.smax_global_classificar_numeros(p_equipe_id, p_global_id, p_numeros)
  LIMIT 1;

  SELECT cg.numero
    INTO v_global_numero
  FROM public.chamados_globais cg
  WHERE cg.id = p_global_id;

  SELECT COALESCE(array_agg(ge.gse), ARRAY[]::text[])
    INTO v_gses
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  WITH entrada AS (
    SELECT DISTINCT regexp_replace(trim(raw.numero), '[^0-9]', '', 'g') AS numero
    FROM unnest(COALESCE(p_numeros, ARRAY[]::text[])) AS raw(numero)
    WHERE regexp_replace(trim(COALESCE(raw.numero, '')), '[^0-9]', '', 'g') <> ''
  ),
  candidatos AS (
    SELECT t.id AS ticket_uuid, t.numero_chamado
    FROM entrada e
    JOIN public.tickets t ON t.numero_chamado = e.numero
    WHERE t.gse = ANY(v_gses)
      AND t.status = 'aguardando'
      AND t.usuario_atual IS NULL
      AND COALESCE(t.suspenso, false) = false
      AND t.chamado_global_id IS NULL
      AND NOT EXISTS (
        SELECT 1 FROM public.tickets_globais tg WHERE tg.ticket_id = t.id
      )
    FOR UPDATE OF t SKIP LOCKED
  ),
  inseridos AS (
    INSERT INTO public.tickets_globais (chamado_global_id, ticket_id, anexado_por)
    SELECT p_global_id, c.ticket_uuid, v_user_id
    FROM candidatos c
    ON CONFLICT (ticket_id) DO NOTHING
    RETURNING ticket_id
  ),
  atualizados AS (
    UPDATE public.tickets t
       SET mantido_por = v_user_id,
           mantido_at = v_now,
           comentario = COALESCE(t.comentario || E'\n', '') || 'Global ' || v_global_numero,
           chamado_global_id = p_global_id,
           suspenso = true,
           causa_suspensao = 'Anexado ao Global ' || v_global_numero,
           updated_at = v_now
      FROM inseridos i
      WHERE t.id = i.ticket_id
      RETURNING t.id AS ticket_uuid, t.numero_chamado
  )
  SELECT
    COALESCE(array_agg(a.ticket_uuid), ARRAY[]::uuid[]),
    COALESCE(jsonb_agg(
      jsonb_build_object('ticket_id', a.ticket_uuid, 'numero_chamado', a.numero_chamado)
      ORDER BY a.numero_chamado
    ), '[]'::jsonb),
    count(*)::integer
    INTO v_anexados_ids, v_anexados, v_total_anexados
  FROM atualizados a;

  WITH classificados AS (
    SELECT * FROM public.smax_global_classificar_numeros(p_equipe_id, p_global_id, p_numeros)
  ),
  ignorados AS (
    SELECT *
    FROM classificados c
    WHERE c.ticket_id IS NULL OR NOT (c.ticket_id = ANY(v_anexados_ids))
  ),
  lista AS (
    SELECT
      COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.numero_pesquisado), '[]'::jsonb) AS tickets,
      count(*)::integer AS total_ignorados
    FROM ignorados i
  ),
  motivos AS (
    SELECT COALESCE(jsonb_object_agg(m.motivo, m.total), '{}'::jsonb) AS por_motivo
    FROM (
      SELECT i.motivo, count(*)::integer AS total
      FROM ignorados i
      GROUP BY i.motivo
    ) m
  )
  SELECT lista.tickets, lista.total_ignorados, motivos.por_motivo
    INTO v_ignorados, v_total_ignorados, v_por_motivo
  FROM lista CROSS JOIN motivos;

  RETURN jsonb_build_object(
    'success', true,
    'global_numero', v_global_numero,
    'total_anexados', COALESCE(v_total_anexados, 0),
    'total_ignorados', COALESCE(v_total_ignorados, 0),
    'anexados', COALESCE(v_anexados, '[]'::jsonb),
    'ignorados', COALESCE(v_ignorados, '[]'::jsonb),
    'por_motivo', COALESCE(v_por_motivo, '{}'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_global_classificar_numeros(uuid, uuid, text[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.smax_global_anexar_livres(uuid, uuid, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_global_classificar_numeros(uuid, uuid, text[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.smax_global_anexar_livres(uuid, uuid, text[]) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

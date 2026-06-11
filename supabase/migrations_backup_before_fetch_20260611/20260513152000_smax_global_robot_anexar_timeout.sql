-- =====================================================
-- SMAX Global Robot - timeout de anexacao
-- Reduz custo de updates operacionais em tickets e evita
-- reclassificacao desnecessaria na RPC de anexacao.
-- =====================================================

BEGIN;
DO $$
BEGIN
  IF to_regprocedure('public.tickets_search_vector_trigger()') IS NOT NULL THEN
    DROP TRIGGER IF EXISTS trg_tickets_search_vector ON public.tickets;
    CREATE TRIGGER trg_tickets_search_vector
    BEFORE INSERT OR UPDATE OF descricao ON public.tickets
    FOR EACH ROW EXECUTE FUNCTION public.tickets_search_vector_trigger();
  END IF;
END $$;
DROP TRIGGER IF EXISTS trg_tickets_sos_evaluate ON public.tickets;
CREATE TRIGGER trg_tickets_sos_evaluate
BEFORE INSERT OR UPDATE OF descricao, gse, sos_override ON public.tickets
FOR EACH ROW EXECUTE FUNCTION public.tickets_sos_evaluate_trigger();
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
  v_global record;
  v_gses text[] := ARRAY[]::text[];
  v_now timestamptz := now();
  v_anexados_ids uuid[] := ARRAY[]::uuid[];
  v_anexados jsonb := '[]'::jsonb;
  v_ignorados jsonb := '[]'::jsonb;
  v_por_motivo jsonb := '{}'::jsonb;
  v_total_anexados integer := 0;
  v_total_ignorados integer := 0;
BEGIN
  IF v_user_id IS NULL THEN
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

  SELECT cg.id, cg.numero, cg.nome, cg.equipe_id
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

  WITH entrada AS (
    SELECT DISTINCT regexp_replace(trim(raw.numero), '[^0-9]', '', 'g') AS numero
    FROM unnest(COALESCE(p_numeros, ARRAY[]::text[])) AS raw(numero)
    WHERE regexp_replace(trim(COALESCE(raw.numero, '')), '[^0-9]', '', 'g') <> ''
  ),
  classificados AS (
    SELECT
      e.numero AS numero_pesquisado,
      t.id AS ticket_id,
      t.numero_chamado,
      t.gse,
      t.descricao,
      t.status::text AS status,
      COALESCE(t.suspenso, false) AS suspenso,
      t.mantido_por,
      u.email AS mantido_por_email,
      t.chamado_global_id,
      CASE
        WHEN t.id IS NULL THEN 'nao_encontrado'
        WHEN t.gse IS NULL OR NOT (t.gse = ANY(v_gses)) THEN 'fora_da_equipe'
        WHEN tg.ticket_id IS NOT NULL OR t.chamado_global_id IS NOT NULL THEN 'ja_em_global'
        WHEN COALESCE(t.suspenso, false) THEN 'suspenso'
        WHEN t.status IS DISTINCT FROM 'aguardando' OR t.usuario_atual IS NOT NULL THEN 'status_invalido'
        ELSE 'livre'
      END AS motivo
    FROM entrada e
    LEFT JOIN public.tickets t ON t.numero_chamado = e.numero
    LEFT JOIN public.users u ON u.id = t.mantido_por
    LEFT JOIN public.tickets_globais tg ON tg.ticket_id = t.id
  ),
  candidatos AS (
    SELECT t.id AS ticket_uuid, t.numero_chamado
    FROM classificados c
    JOIN public.tickets t ON t.id = c.ticket_id
    WHERE c.motivo = 'livre'
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
           comentario = COALESCE(t.comentario || E'\n', '') || 'Global ' || v_global.numero,
           chamado_global_id = p_global_id,
           suspenso = true,
           causa_suspensao = 'Anexado ao Global ' || v_global.numero,
           updated_at = v_now
      FROM inseridos i
      WHERE t.id = i.ticket_id
      RETURNING t.id AS ticket_uuid, t.numero_chamado
  ),
  anexados_aggr AS (
    SELECT
      COALESCE(array_agg(a.ticket_uuid), ARRAY[]::uuid[]) AS ids,
      COALESCE(jsonb_agg(
        jsonb_build_object('ticket_id', a.ticket_uuid, 'numero_chamado', a.numero_chamado)
        ORDER BY a.numero_chamado
      ), '[]'::jsonb) AS tickets,
      count(*)::integer AS total
    FROM atualizados a
  ),
  ignorados AS (
    SELECT c.*
    FROM classificados c
    WHERE c.ticket_id IS NULL
       OR NOT EXISTS (
         SELECT 1 FROM atualizados a WHERE a.ticket_uuid = c.ticket_id
       )
  ),
  ignorados_aggr AS (
    SELECT
      COALESCE(jsonb_agg(to_jsonb(i) ORDER BY i.numero_pesquisado), '[]'::jsonb) AS tickets,
      count(*)::integer AS total
    FROM ignorados i
  ),
  motivos_aggr AS (
    SELECT COALESCE(jsonb_object_agg(m.motivo, m.total), '{}'::jsonb) AS por_motivo
    FROM (
      SELECT i.motivo, count(*)::integer AS total
      FROM ignorados i
      GROUP BY i.motivo
    ) m
  )
  SELECT
    anexados_aggr.ids,
    anexados_aggr.tickets,
    anexados_aggr.total,
    ignorados_aggr.tickets,
    ignorados_aggr.total,
    motivos_aggr.por_motivo
    INTO v_anexados_ids, v_anexados, v_total_anexados, v_ignorados, v_total_ignorados, v_por_motivo
  FROM anexados_aggr CROSS JOIN ignorados_aggr CROSS JOIN motivos_aggr;

  RETURN jsonb_build_object(
    'success', true,
    'global_numero', v_global.numero,
    'total_anexados', COALESCE(v_total_anexados, 0),
    'total_ignorados', COALESCE(v_total_ignorados, 0),
    'anexados', COALESCE(v_anexados, '[]'::jsonb),
    'ignorados', COALESCE(v_ignorados, '[]'::jsonb),
    'por_motivo', COALESCE(v_por_motivo, '{}'::jsonb)
  );
END;
$$;
REVOKE ALL ON FUNCTION public.smax_global_anexar_livres(uuid, uuid, text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.smax_global_anexar_livres(uuid, uuid, text[]) TO authenticated;
NOTIFY pgrst, 'reload schema';
COMMIT;

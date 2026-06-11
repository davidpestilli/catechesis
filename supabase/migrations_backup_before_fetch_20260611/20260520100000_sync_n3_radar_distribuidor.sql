-- ============================================================================
-- Sincroniza Escalacoes N3 com Radar e Distribuidor
-- ============================================================================

BEGIN;
ALTER TABLE public.escalacoes_n3
  ADD COLUMN IF NOT EXISTS assunto text;
ALTER TABLE public.escalacoes_n3
  ADD COLUMN IF NOT EXISTS local_tramitacao text;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_escalacoes_n3_local_tramitacao'
      AND conrelid = 'public.escalacoes_n3'::regclass
  ) THEN
    ALTER TABLE public.escalacoes_n3
      ADD CONSTRAINT chk_escalacoes_n3_local_tramitacao
      CHECK (local_tramitacao IS NULL OR local_tramitacao IN ('STI', 'SGS 3', 'SPI'));
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_escalacoes_n3_assunto
  ON public.escalacoes_n3(assunto)
  WHERE assunto IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_escalacoes_n3_local_tramitacao
  ON public.escalacoes_n3(local_tramitacao)
  WHERE local_tramitacao IS NOT NULL;
CREATE OR REPLACE FUNCTION public.n3_tickets_relacionados(p_escalacao_id uuid)
RETURNS text[]
LANGUAGE sql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(numero_ticket ORDER BY numero_ticket), ARRAY[]::text[])
  FROM (
    SELECT DISTINCT NULLIF(BTRIM(e.numero_ticket), '') AS numero_ticket
    FROM public.escalacoes_n3_vinculos v
    JOIN public.escalacoes_n3 e
      ON e.id = CASE
        WHEN v.escalacao_a_id = p_escalacao_id THEN v.escalacao_b_id
        ELSE v.escalacao_a_id
      END
    WHERE p_escalacao_id IS NOT NULL
      AND (v.escalacao_a_id = p_escalacao_id OR v.escalacao_b_id = p_escalacao_id)
  ) relacionados
  WHERE numero_ticket IS NOT NULL;
$function$;
CREATE OR REPLACE FUNCTION public.sincronizar_radar_from_n3(p_escalacao_id uuid)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_escalacao record;
  v_assunto text;
  v_status_radar text;
  v_relacionados text[];
  v_atualizados integer := 0;
  v_tem_colunas boolean := false;
BEGIN
  IF p_escalacao_id IS NULL THEN
    RETURN 0;
  END IF;

  SELECT id, numero_ticket, motivo_envio, status, assunto, local_tramitacao
    INTO v_escalacao
  FROM public.escalacoes_n3
  WHERE id = p_escalacao_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF to_regclass('public.radar_tickets') IS NULL THEN
    RETURN 0;
  END IF;

  SELECT COUNT(*) = 10
    INTO v_tem_colunas
  FROM information_schema.columns
  WHERE table_schema = 'public'
    AND table_name = 'radar_tickets'
    AND column_name IN (
      'numero_ticket',
      'assunto',
      'descricao',
      'destino_n3',
      'status',
      'atualizado_em',
      'deletado',
      'tickets_relacionados_externos',
      'qtd_tickets_relacionados',
      'escalacao_n3_id'
    );

  IF NOT v_tem_colunas THEN
    RETURN 0;
  END IF;

  v_assunto := COALESCE(NULLIF(BTRIM(v_escalacao.assunto), ''), 'Migrado N3');
  v_status_radar := CASE WHEN v_escalacao.status = 'encerrado' THEN 'resolvido' ELSE 'aberto' END;
  v_relacionados := public.n3_tickets_relacionados(p_escalacao_id);

  EXECUTE $sql$
    UPDATE public.radar_tickets
       SET numero_ticket = $2,
           assunto = $3,
           descricao = $4,
           destino_n3 = $5,
           status = $6,
           tickets_relacionados_externos = $7,
           qtd_tickets_relacionados = COALESCE(cardinality($7), 0),
           atualizado_em = now()
     WHERE escalacao_n3_id = $1
       AND deletado = false
  $sql$
  USING
    p_escalacao_id,
    v_escalacao.numero_ticket,
    v_assunto,
    v_escalacao.motivo_envio,
    v_escalacao.local_tramitacao,
    v_status_radar,
    v_relacionados;

  GET DIAGNOSTICS v_atualizados = ROW_COUNT;
  RETURN v_atualizados;
END;
$function$;
CREATE OR REPLACE FUNCTION public.finalizar_ticket_distribuidor_from_n3(
  p_numero_ticket text,
  p_usuario_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_atualizados integer := 0;
  v_now timestamptz := now();
BEGIN
  IF p_usuario_id IS NULL OR NULLIF(BTRIM(p_numero_ticket), '') IS NULL THEN
    RETURN 0;
  END IF;

  UPDATE public.tickets
     SET status = 'finalizado',
         usuario_atual = p_usuario_id,
         resposta_ia = NULL,
         resposta_ia_editado_por_id = NULL,
         resposta_ia_editado_por_nome = NULL,
         resposta_ia_editado_em = NULL,
         assigned_at = COALESCE(assigned_at, v_now),
         started_at = COALESCE(started_at, v_now),
         finished_at = v_now,
         suspenso = false,
         causa_suspensao = NULL,
         mantido_por = NULL,
         mantido_at = NULL,
         updated_at = v_now
   WHERE numero_chamado = BTRIM(p_numero_ticket)
     AND status = 'aguardando'
     AND usuario_atual IS NULL;

  GET DIAGNOSTICS v_atualizados = ROW_COUNT;
  RETURN v_atualizados;
END;
$function$;
CREATE OR REPLACE FUNCTION public.fn_sync_n3_update()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_usuario_id uuid := auth.uid();
  v_relacionada_id uuid;
BEGIN
  PERFORM public.sincronizar_radar_from_n3(NEW.id);

  IF NEW.status = 'encerrado'
     AND OLD.status IS DISTINCT FROM NEW.status THEN
    PERFORM public.finalizar_ticket_distribuidor_from_n3(NEW.numero_ticket, v_usuario_id);
  END IF;

  IF OLD.numero_ticket IS DISTINCT FROM NEW.numero_ticket THEN
    FOR v_relacionada_id IN
      SELECT CASE
        WHEN v.escalacao_a_id = NEW.id THEN v.escalacao_b_id
        ELSE v.escalacao_a_id
      END
      FROM public.escalacoes_n3_vinculos v
      WHERE v.escalacao_a_id = NEW.id
         OR v.escalacao_b_id = NEW.id
    LOOP
      PERFORM public.sincronizar_radar_from_n3(v_relacionada_id);
    END LOOP;
  END IF;

  RETURN NEW;
END;
$function$;
CREATE OR REPLACE FUNCTION public.fn_sync_n3_vinculos_radar()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM public.sincronizar_radar_from_n3(NEW.escalacao_a_id);
    PERFORM public.sincronizar_radar_from_n3(NEW.escalacao_b_id);
    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    PERFORM public.sincronizar_radar_from_n3(OLD.escalacao_a_id);
    PERFORM public.sincronizar_radar_from_n3(OLD.escalacao_b_id);
    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.n3_tickets_relacionados(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sincronizar_radar_from_n3(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.finalizar_ticket_distribuidor_from_n3(text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_sync_n3_update() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_sync_n3_vinculos_radar() FROM PUBLIC;
DROP TRIGGER IF EXISTS trg_sync_n3_update ON public.escalacoes_n3;
CREATE TRIGGER trg_sync_n3_update
  AFTER UPDATE OF numero_ticket, motivo_envio, assunto, local_tramitacao, status
  ON public.escalacoes_n3
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_sync_n3_update();
DROP TRIGGER IF EXISTS trg_sync_n3_vinculos_radar ON public.escalacoes_n3_vinculos;
CREATE TRIGGER trg_sync_n3_vinculos_radar
  AFTER INSERT OR DELETE ON public.escalacoes_n3_vinculos
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_sync_n3_vinculos_radar();
COMMENT ON FUNCTION public.sincronizar_radar_from_n3(uuid) IS
  'Sincroniza campos de escalacoes_n3 no radar_tickets associado por escalacao_n3_id.';
COMMENT ON FUNCTION public.finalizar_ticket_distribuidor_from_n3(text, uuid) IS
  'Finaliza ticket do Distribuidor quando a escalacao N3 correspondente e encerrada, apenas se ainda estiver em Livres/Suspensos.';
NOTIFY pgrst, 'reload schema';
COMMIT;

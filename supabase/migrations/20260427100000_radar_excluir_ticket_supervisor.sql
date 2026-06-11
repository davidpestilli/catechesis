-- ============================================================
-- Migration: Radar de Tickets — Permitir supervisor excluir tickets
-- Data: 2026-04-27
-- Objetivo: Atualizar RPC radar_excluir_ticket para autorizar
--           tanto admin quanto supervisor (além do criador).
-- ============================================================

CREATE OR REPLACE FUNCTION public.radar_excluir_ticket(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_criado_por UUID;
  v_pode_excluir BOOLEAN;
BEGIN
  -- Buscar criador do ticket
  SELECT criado_por INTO v_criado_por
  FROM radar_tickets
  WHERE id = p_ticket_id AND NOT deletado;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Ticket não encontrado');
  END IF;

  -- Verificar se é admin ou supervisor
  SELECT EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
      AND role IN ('admin'::user_role, 'supervisor'::user_role)
  ) INTO v_pode_excluir;

  -- Autorizar se admin/supervisor ou criador
  IF NOT (v_pode_excluir OR v_criado_por = auth.uid()) THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Sem permissão');
  END IF;

  -- Soft-delete
  UPDATE radar_tickets SET deletado = true, atualizado_em = now() WHERE id = p_ticket_id;

  RETURN jsonb_build_object('ok', true);
END;
$function$;

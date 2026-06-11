-- ============================================================
-- Migration: Radar de Tickets — Permissões Supervisor
-- Data: 2026-04-24
-- Objetivo: Dar ao perfil 'supervisor' as mesmas permissões
--           que o 'admin' no Radar de Tickets
-- ============================================================

-- ============================================================
-- 1. Política de UPDATE em radar_tickets (era só admin)
-- ============================================================
DROP POLICY IF EXISTS "radar_tickets_update_admin" ON radar_tickets;
CREATE POLICY "radar_tickets_update_admin_or_supervisor"
  ON radar_tickets FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM users
    WHERE id = auth.uid()
      AND role IN ('admin', 'supervisor')
  ));
-- ============================================================
-- 2. Política de DELETE em radar_ticket_comentarios (era só admin)
-- ============================================================
DROP POLICY IF EXISTS "radar_coment_delete_own_or_admin" ON radar_ticket_comentarios;
CREATE POLICY "radar_coment_delete_own_or_admin"
  ON radar_ticket_comentarios FOR DELETE TO authenticated
  USING (
    autor_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM users
      WHERE id = auth.uid()
        AND role IN ('admin', 'supervisor')
    )
  );

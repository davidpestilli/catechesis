-- =====================================================
-- SMAX Rejeites - Realtime Sync
-- Habilita sincronizacao em tempo real do snapshot e meta
-- para refletir exclusoes e novas capturas entre clientes.
-- =====================================================

BEGIN;
ALTER TABLE public.smax_rejeites_snapshot REPLICA IDENTITY FULL;
ALTER TABLE public.smax_rejeites_snapshot_meta REPLICA IDENTITY FULL;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.smax_rejeites_snapshot;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.smax_rejeites_snapshot_meta;
EXCEPTION WHEN duplicate_object THEN
  NULL;
END $$;
NOTIFY pgrst, 'reload schema';
COMMIT;

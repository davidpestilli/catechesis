-- =====================================================
-- HOTFIX: Reatribuir todas as palavras SOS existentes à equipe 2.3.2
-- Motivo: backfill anterior distribuiu erradamente palavras a outras equipes.
-- Todas as palavras cadastradas até agora são da 2.3.2.
-- =====================================================

BEGIN;
-- Equipe 2.3.2
UPDATE public.sos_palavras_chave
   SET equipe_id = '11111111-1111-1111-1111-111111111111'::uuid
 WHERE equipe_id <> '11111111-1111-1111-1111-111111111111'::uuid
    OR equipe_id IS NULL;
-- Limpar tickets fora da 2.3.2 que tinham flags SOS espúrias
-- (tickets cuja equipe não é a 2.3.2 não devem ter sos=true por palavras dela)
UPDATE public.tickets t
   SET sos_palavras = '{}'::text[],
       sos = CASE WHEN t.sos_override IS TRUE THEN t.sos ELSE false END
 WHERE t.gse NOT IN (SELECT gse FROM public.gse_equipes WHERE equipe_id = '11111111-1111-1111-1111-111111111111'::uuid)
   AND (t.sos = true OR array_length(t.sos_palavras, 1) > 0);
-- Reavaliar fila ATIVA da 2.3.2 com as palavras corretas
SELECT public.sos_reavaliar_tickets_fila('11111111-1111-1111-1111-111111111111'::uuid) AS tickets_reavaliados;
COMMIT;

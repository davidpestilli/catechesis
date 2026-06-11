-- Conclui migração TIMESTAMP em oraculo_chamados.
-- Pré-requisito: tabela vazia (TRUNCATE antes do upload da nova planilha).
-- Em tabela vazia, ALTER COLUMN TYPE é instantâneo (sem rewrite, sem lock prolongado),
-- evitando o ACCESS EXCLUSIVE lock que travou o PostgREST na tentativa anterior.

BEGIN;
SET LOCAL lock_timeout = '5s';
SET LOCAL statement_timeout = '60s';
-- 1. Garantir tabela vazia (será preenchida pelo upload posterior)
TRUNCATE TABLE public.oraculo_chamados RESTART IDENTITY;
-- 2. Migrar data_envio_aceite de DATE para TIMESTAMP
--    (data_abertura já era TIMESTAMP)
ALTER TABLE public.oraculo_chamados
  ALTER COLUMN data_envio_aceite TYPE TIMESTAMP USING data_envio_aceite::timestamp;
COMMIT;
-- 3. Refresh da matview (vazia até o próximo upload)
REFRESH MATERIALIZED VIEW public.oraculo_mv_stats_diario;

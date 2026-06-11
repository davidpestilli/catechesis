-- ============================================================================
-- Migration: Converter colunas de data do oraculo_chamados para TIMESTAMP
-- ----------------------------------------------------------------------------
-- Motivo: Excel original possui hora (DD/MM/YY HH:MM:SS); estávamos truncando
-- Impacto:
--  * Linhas existentes ficam com hora 00:00:00 até reupload
--  * Materialized view oraculo_mv_stats_diario continua com granularidade diária
--    via cast c.data_abertura::date (mantém comportamento dos painéis atuais)
--  * Funções RPC que comparam com DATE continuam funcionando (cast implícito)
-- ============================================================================

-- 1) Garante que a coluna data_envio_aceite existe (homologação local pode não ter)
ALTER TABLE public.oraculo_chamados
  ADD COLUMN IF NOT EXISTS data_envio_aceite date;
-- 2) Remove materialized view dependente de data_abertura
DROP MATERIALIZED VIEW IF EXISTS public.oraculo_mv_stats_diario;
-- 3) Converte colunas para timestamp preservando data
ALTER TABLE public.oraculo_chamados
  ALTER COLUMN data_abertura TYPE timestamp without time zone
  USING data_abertura::timestamp;
ALTER TABLE public.oraculo_chamados
  ALTER COLUMN data_envio_aceite TYPE timestamp without time zone
  USING data_envio_aceite::timestamp;
COMMENT ON COLUMN public.oraculo_chamados.data_abertura IS
  'Data e hora de abertura do chamado (origem: coluna DATA DE ABERTURA do Excel)';
COMMENT ON COLUMN public.oraculo_chamados.data_envio_aceite IS
  'Data e hora do envio do aceite (origem: coluna DATA ENVIO ACEITE do Excel; NULL se não respondido)';
-- 4) Recria materialized view com granularidade diária (cast para date)
CREATE MATERIALIZED VIEW public.oraculo_mv_stats_diario AS
SELECT
  c.data_abertura::date                          AS data_abertura,
  c.grupo_designado,
  lower(btrim(c.nome_designado))                 AS nome_designado_lower,
  min(initcap(btrim(c.nome_designado)))          AS nome_designado_display,
  CASE
    WHEN e.nome IS NOT NULL THEN e.nome::text
    WHEN c.designado_localizacao = 'IT2B'::text THEN 'IT2B'::text
    ELSE 'Outros'::text
  END                                            AS equipe_sgs,
  c.designado_localizacao,
  COALESCE(c.status_operacional, 'Sem Status'::text) AS status_operacional,
  lower(btrim(c.email))                          AS email_lower,
  c.atendido_externo,
  count(*)::integer                              AS total_tickets,
  count(*) FILTER (
    WHERE c.solucao IS NOT NULL
      AND btrim(c.solucao) <> ''::text
      AND btrim(c.solucao) <> '-'::text
  )::integer                                     AS total_com_solucao,
  count(*) FILTER (
    WHERE c.solucao IS NULL
       OR btrim(c.solucao) = ''::text
       OR btrim(c.solucao) = '-'::text
  )::integer                                     AS total_sem_solucao,
  sum(COALESCE(c.qtd_rejeite, 0))::integer       AS total_rejeites,
  count(*) FILTER (WHERE c.qtd_rejeite > 0)::integer AS tickets_com_rejeite,
  count(*) FILTER (
    WHERE c.status_operacional = ANY (ARRAY['Fechado'::text, 'Aguardando Aceite Definitivo'::text])
  )::integer                                     AS total_atendidos
FROM public.oraculo_chamados c
LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
LEFT JOIN public.equipes      e  ON ge.equipe_id = e.id
GROUP BY
  c.data_abertura::date,
  c.grupo_designado,
  lower(btrim(c.nome_designado)),
  CASE
    WHEN e.nome IS NOT NULL THEN e.nome::text
    WHEN c.designado_localizacao = 'IT2B'::text THEN 'IT2B'::text
    ELSE 'Outros'::text
  END,
  c.designado_localizacao,
  COALESCE(c.status_operacional, 'Sem Status'::text),
  lower(btrim(c.email)),
  c.atendido_externo;
-- 5) Recria índices
CREATE UNIQUE INDEX idx_mv_stats_diario_unique
  ON public.oraculo_mv_stats_diario
  USING btree (data_abertura, grupo_designado, nome_designado_lower, equipe_sgs, designado_localizacao, status_operacional, email_lower, atendido_externo);
CREATE INDEX idx_mv_stats_diario_data           ON public.oraculo_mv_stats_diario USING btree (data_abertura);
CREATE INDEX idx_mv_stats_diario_data_equipe    ON public.oraculo_mv_stats_diario USING btree (data_abertura, equipe_sgs);
CREATE INDEX idx_mv_stats_diario_email          ON public.oraculo_mv_stats_diario USING btree (email_lower);
CREATE INDEX idx_mv_stats_diario_equipe         ON public.oraculo_mv_stats_diario USING btree (equipe_sgs);
CREATE INDEX idx_mv_stats_diario_equipe_grupo   ON public.oraculo_mv_stats_diario USING btree (equipe_sgs, grupo_designado);
CREATE INDEX idx_mv_stats_diario_grupo          ON public.oraculo_mv_stats_diario USING btree (grupo_designado);
CREATE INDEX idx_mv_stats_diario_respondente    ON public.oraculo_mv_stats_diario USING btree (nome_designado_lower);
CREATE INDEX idx_mv_stats_diario_status         ON public.oraculo_mv_stats_diario USING btree (status_operacional);
-- 6) Refresh inicial
REFRESH MATERIALIZED VIEW public.oraculo_mv_stats_diario;

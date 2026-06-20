-- Otimizacoes para reduzir custo da RPC obter_metricas_categorias
-- e melhorar filtros usados na analise da fila real.

CREATE INDEX IF NOT EXISTS idx_tickets_gse_status_usuario_ativos
  ON public.tickets (gse, status, usuario_atual)
  WHERE suspenso = false;
CREATE INDEX IF NOT EXISTS idx_tickets_gse_mantido_por_aguardando
  ON public.tickets (gse, mantido_por)
  WHERE status = 'aguardando' AND mantido_por IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_tickets_gse_status_finished
  ON public.tickets (gse, status, finished_at)
  WHERE finished_at IS NOT NULL;

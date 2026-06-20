-- Reduz custo residual da RPC obter_metricas_categorias sem alterar seu
-- contrato. O perfil em produção mostrou dois pontos dominantes:
-- 1) materialização de tickets_equipe a partir de tickets(gse)
-- 2) lookups repetidos em ticket_analises para calcular categoria_top
--
-- Os índices abaixo permitem planos com menos heap fetches e melhor suporte
-- a scans por equipe usados pela aba "Métricas".

CREATE INDEX IF NOT EXISTS idx_gse_equipes_equipe_gse
  ON public.gse_equipes (equipe_id, gse);
CREATE INDEX IF NOT EXISTS idx_tickets_gse_metrics_covering
  ON public.tickets (gse)
  INCLUDE (id, status, suspenso, usuario_atual, mantido_por, tempo_espera_origem, finished_at);
CREATE INDEX IF NOT EXISTS idx_ticket_analises_ticket_covering_categoria
  ON public.ticket_analises (ticket_id)
  INCLUDE (categoria_equipe_id, categoria_slug);

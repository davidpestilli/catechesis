ALTER TABLE public.tickets
ADD COLUMN IF NOT EXISTS fila_finalizacao_contexto text;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'tickets_fila_finalizacao_contexto_check'
  ) THEN
    ALTER TABLE public.tickets
    ADD CONSTRAINT tickets_fila_finalizacao_contexto_check
    CHECK (
      fila_finalizacao_contexto IS NULL
      OR fila_finalizacao_contexto = ANY (ARRAY['livres'::text, 'suspensos'::text])
    );
  END IF;
END;
$$;
COMMENT ON COLUMN public.tickets.fila_finalizacao_contexto
IS 'Snapshot do contexto (livres/suspensos) no momento em que o ticket foi finalizado.';
CREATE OR REPLACE FUNCTION public.tickets_definir_fila_finalizacao_contexto()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.status = 'finalizado' THEN
    IF TG_OP = 'INSERT' THEN
      NEW.fila_finalizacao_contexto := CASE
        WHEN COALESCE(NEW.suspenso, false) THEN 'suspensos'
        ELSE 'livres'
      END;
    ELSIF OLD.status IS DISTINCT FROM 'finalizado'
       OR NEW.fila_finalizacao_contexto IS NULL THEN
      NEW.fila_finalizacao_contexto := CASE
        WHEN COALESCE(OLD.suspenso, false) THEN 'suspensos'
        WHEN COALESCE(NEW.suspenso, false) THEN 'suspensos'
        ELSE 'livres'
      END;
    END IF;
  ELSIF NEW.status IS DISTINCT FROM 'finalizado' THEN
    NEW.fila_finalizacao_contexto := NULL;
  END IF;

  RETURN NEW;
END;
$function$;
DROP TRIGGER IF EXISTS trg_tickets_definir_fila_finalizacao_contexto ON public.tickets;
CREATE TRIGGER trg_tickets_definir_fila_finalizacao_contexto
BEFORE INSERT OR UPDATE OF status, suspenso
ON public.tickets
FOR EACH ROW
EXECUTE FUNCTION public.tickets_definir_fila_finalizacao_contexto();
SET statement_timeout = 0;
UPDATE public.tickets
SET fila_finalizacao_contexto = CASE
  WHEN COALESCE(suspenso, false) THEN 'suspensos'
  ELSE 'livres'
END
WHERE status = 'finalizado'
  AND fila_finalizacao_contexto IS NULL;
UPDATE public.tickets
SET fila_finalizacao_contexto = NULL
WHERE status <> 'finalizado'
  AND fila_finalizacao_contexto IS NOT NULL;
RESET statement_timeout;
CREATE OR REPLACE FUNCTION public.obter_estatisticas_gamificadas(
  p_equipe_id uuid,
  p_periodo text DEFAULT 'today'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_now_local timestamp;
  v_data_inicio_local timestamp;
  v_data_fim_local timestamp;
  v_data_inicio timestamptz;
  v_data_fim timestamptz;
  v_gses text[];
  v_resultado jsonb;
BEGIN
  v_now_local := now() AT TIME ZONE 'America/Sao_Paulo';

  IF p_periodo = 'today' THEN
    v_data_inicio_local := date_trunc('day', v_now_local);
    v_data_fim_local := v_data_inicio_local + INTERVAL '1 day';
  ELSIF p_periodo = '24h' THEN
    v_data_fim_local := date_trunc('hour', v_now_local) + INTERVAL '1 hour';
    v_data_inicio_local := v_data_fim_local - INTERVAL '24 hours';
  ELSIF p_periodo = '48h' THEN
    v_data_fim_local := date_trunc('hour', v_now_local) + INTERVAL '1 hour';
    v_data_inicio_local := v_data_fim_local - INTERVAL '48 hours';
  ELSIF p_periodo = '72h' THEN
    v_data_fim_local := date_trunc('hour', v_now_local) + INTERVAL '1 hour';
    v_data_inicio_local := v_data_fim_local - INTERVAL '72 hours';
  ELSIF p_periodo = '7d' THEN
    v_data_fim_local := date_trunc('day', v_now_local) + INTERVAL '1 day';
    v_data_inicio_local := v_data_fim_local - INTERVAL '7 days';
  ELSIF p_periodo = '30d' THEN
    v_data_fim_local := date_trunc('day', v_now_local) + INTERVAL '1 day';
    v_data_inicio_local := v_data_fim_local - INTERVAL '30 days';
  ELSIF p_periodo = 'all' THEN
    v_data_inicio_local := NULL;
    v_data_fim_local := NULL;
  ELSE
    v_data_inicio_local := date_trunc('day', v_now_local);
    v_data_fim_local := v_data_inicio_local + INTERVAL '1 day';
  END IF;

  v_data_inicio := CASE
    WHEN v_data_inicio_local IS NULL THEN NULL
    ELSE v_data_inicio_local AT TIME ZONE 'America/Sao_Paulo'
  END;

  v_data_fim := CASE
    WHEN v_data_fim_local IS NULL THEN NULL
    ELSE v_data_fim_local AT TIME ZONE 'America/Sao_Paulo'
  END;

  SELECT COALESCE(array_agg(ge.gse), ARRAY[]::text[])
  INTO v_gses
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  WITH membros_equipe AS (
    SELECT
      u.id::text AS usuario_id,
      COALESCE(NULLIF(TRIM(u.nome), ''), u.email, 'Membro') AS usuario_nome,
      up.gamificacao_avatar_id AS avatar_id
    FROM public.users u
    LEFT JOIN public.user_preferences up ON up.user_id = u.id
    WHERE u.equipe_id = p_equipe_id
      AND (u.ativo IS NULL OR u.ativo = true)
  ),
  tickets_base AS (
    SELECT
      COALESCE(me.usuario_id, '__outros__') AS usuario_id,
      COALESCE(me.usuario_nome, 'Outros') AS usuario_nome,
      CASE
        WHEN p_periodo IN ('today', '24h', '48h', '72h') THEN
          to_char(t.finished_at, 'DD/MM HH24"h"')
        WHEN p_periodo = 'all' THEN
          to_char(t.finished_at, 'YYYY-MM-DD')
        ELSE
          to_char(t.finished_at, 'DD/MM')
      END AS periodo,
      CASE
        WHEN p_periodo IN ('today', '24h', '48h', '72h') THEN
          date_trunc('hour', t.finished_at)
        ELSE
          date_trunc('day', t.finished_at)
      END AS periodo_ordem,
      calc.pontos_ticket_base,
      calc.multiplicador_ticket,
      (calc.pontos_ticket_base * calc.multiplicador_ticket) AS pontos_ticket,
      COALESCE(t.sos, false) AS ticket_sos,
      COALESCE(t.vip, false) AS ticket_vip,
      (t.tempo_espera_origem IS NULL) AS usou_fallback_origem
    FROM public.tickets t
    LEFT JOIN membros_equipe me ON me.usuario_id = t.usuario_atual::text
    CROSS JOIN LATERAL (
      SELECT
        CASE
          WHEN base.contexto_finalizacao = 'suspensos' THEN 1
          ELSE base.pontos_ticket_base_livres
        END AS pontos_ticket_base,
        CASE
          WHEN base.contexto_finalizacao = 'suspensos' THEN 1
          WHEN COALESCE(t.sos, false) THEN 3
          WHEN COALESCE(t.vip, false) THEN 2
          ELSE 1
        END AS multiplicador_ticket
      FROM (
        SELECT
          COALESCE(
            NULLIF(t.fila_finalizacao_contexto, ''),
            CASE WHEN COALESCE(t.suspenso, false) THEN 'suspensos' ELSE 'livres' END
          ) AS contexto_finalizacao,
          GREATEST(
            1,
            CEIL(
              GREATEST(
                0::numeric,
                EXTRACT(EPOCH FROM (t.finished_at - COALESCE(t.tempo_espera_origem, t.created_at, t.finished_at))) / 3600.0
              ) / 24.0
            )::integer
          ) AS pontos_ticket_base_livres
      ) base
    ) calc
    WHERE t.gse = ANY(v_gses)
      AND t.status = 'finalizado'
      AND t.finished_at IS NOT NULL
      AND t.usuario_atual IS NOT NULL
      AND (
        v_data_inicio_local IS NULL
        OR (
          t.finished_at >= v_data_inicio_local
          AND (v_data_fim_local IS NULL OR t.finished_at < v_data_fim_local)
        )
      )
  ),
  tickets_agg AS (
    SELECT
      tb.usuario_id,
      MIN(tb.usuario_nome) AS usuario_nome,
      COUNT(*)::integer AS tickets_total,
      COALESCE(SUM(tb.pontos_ticket), 0)::integer AS pontos_tickets,
      COUNT(*) FILTER (WHERE tb.pontos_ticket >= 3)::integer AS tickets_pesados,
      COUNT(*) FILTER (WHERE tb.ticket_sos)::integer AS tickets_sos_total,
      COALESCE(SUM(CASE WHEN tb.ticket_sos THEN tb.pontos_ticket - tb.pontos_ticket_base ELSE 0 END), 0)::integer AS pontos_bonus_sos,
      COUNT(*) FILTER (WHERE tb.ticket_vip AND NOT tb.ticket_sos)::integer AS tickets_vip_total,
      COALESCE(SUM(CASE WHEN tb.ticket_vip AND NOT tb.ticket_sos THEN tb.pontos_ticket - tb.pontos_ticket_base ELSE 0 END), 0)::integer AS pontos_bonus_vip,
      COUNT(*) FILTER (WHERE tb.usou_fallback_origem)::integer AS tickets_com_fallback_origem
    FROM tickets_base tb
    GROUP BY tb.usuario_id
  ),
  ticket_dias AS (
    SELECT
      dias.usuario_id,
      jsonb_agg(
        jsonb_build_object(
          'dias', dias.pontos_ticket,
          'tickets', dias.tickets,
          'pontos', dias.pontos
        )
        ORDER BY dias.pontos_ticket
      ) AS ticket_pontos_por_dia
    FROM (
      SELECT
        tb.usuario_id,
        tb.pontos_ticket,
        COUNT(*)::integer AS tickets,
        SUM(tb.pontos_ticket)::integer AS pontos
      FROM tickets_base tb
      GROUP BY tb.usuario_id, tb.pontos_ticket
    ) dias
    GROUP BY dias.usuario_id
  ),
  tickets_series AS (
    SELECT
      tb.usuario_id,
      tb.periodo,
      tb.periodo_ordem,
      COUNT(*)::integer AS tickets,
      SUM(tb.pontos_ticket)::integer AS pontos_tickets
    FROM tickets_base tb
    GROUP BY tb.usuario_id, tb.periodo, tb.periodo_ordem
  ),
  servicos_base AS (
    SELECT
      COALESCE(me.usuario_id, '__outros__') AS usuario_id,
      COALESCE(me.usuario_nome, NULLIF(TRIM(s.usuario_nome), ''), 'Outros') AS usuario_nome,
      CASE
        WHEN p_periodo IN ('today', '24h', '48h', '72h') THEN
          to_char(s.data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24"h"')
        WHEN p_periodo = 'all' THEN
          to_char(s.data_execucao AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD')
        ELSE
          to_char(s.data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM')
      END AS periodo,
      CASE
        WHEN p_periodo IN ('today', '24h', '48h', '72h') THEN
          date_trunc('hour', s.data_execucao AT TIME ZONE 'America/Sao_Paulo')
        ELSE
          date_trunc('day', s.data_execucao AT TIME ZONE 'America/Sao_Paulo')
      END AS periodo_ordem,
      s.tipo,
      GREATEST(COALESCE(s.quantidade, 0), 0)::integer AS quantidade,
      CASE
        WHEN s.tipo = ANY(ARRAY[
          'homologacao',
          'reuniao_interna',
          'reuniao_externa',
          'ouvidoria',
          'cpa',
          'agendamento_visitas',
          'visitas_virtuais',
          'visitas_presenciais',
          'dev_aplicacao',
          'resp_chamado_complexo',
          'criacao_apresentacao',
          'elaboracao_relatorio',
          'estudos_atualizacao'
        ]::text[]) THEN 10
        ELSE 1
      END AS multiplicador
    FROM public.servicos s
    LEFT JOIN membros_equipe me ON me.usuario_id = s.usuario_id::text
    WHERE s.equipe_id = p_equipe_id
      AND (
        v_data_inicio IS NULL
        OR (
          s.data_execucao >= v_data_inicio
          AND (v_data_fim IS NULL OR s.data_execucao < v_data_fim)
        )
      )
  ),
  servicos_agg AS (
    SELECT
      sb.usuario_id,
      MIN(sb.usuario_nome) AS usuario_nome,
      SUM(sb.quantidade)::integer AS servicos_total,
      COUNT(*)::integer AS servicos_registros,
      SUM(CASE WHEN sb.multiplicador = 10 THEN sb.quantidade ELSE 0 END)::integer AS servicos_horas,
      SUM(CASE WHEN sb.multiplicador = 1 THEN sb.quantidade ELSE 0 END)::integer AS servicos_unidades,
      SUM(sb.quantidade * sb.multiplicador)::integer AS pontos_servicos
    FROM servicos_base sb
    GROUP BY sb.usuario_id
  ),
  servicos_por_tipo AS (
    SELECT
      sb.usuario_id,
      sb.tipo,
      sb.multiplicador,
      SUM(sb.quantidade)::integer AS quantidade,
      COUNT(*)::integer AS registros,
      SUM(sb.quantidade * sb.multiplicador)::integer AS pontos
    FROM servicos_base sb
    GROUP BY sb.usuario_id, sb.tipo, sb.multiplicador
  ),
  servicos_por_tipo_json AS (
    SELECT
      spt.usuario_id,
      jsonb_agg(
        jsonb_build_object(
          'tipo', spt.tipo,
          'multiplicador', spt.multiplicador,
          'quantidade', spt.quantidade,
          'registros', spt.registros,
          'pontos', spt.pontos
        )
        ORDER BY spt.pontos DESC, spt.quantidade DESC, spt.tipo ASC
      ) AS servicos_por_tipo
    FROM servicos_por_tipo spt
    GROUP BY spt.usuario_id
  ),
  servicos_series AS (
    SELECT
      sb.usuario_id,
      sb.periodo,
      sb.periodo_ordem,
      SUM(sb.quantidade)::integer AS servicos,
      SUM(sb.quantidade * sb.multiplicador)::integer AS pontos_servicos
    FROM servicos_base sb
    GROUP BY sb.usuario_id, sb.periodo, sb.periodo_ordem
  ),
  participantes AS (
    SELECT usuario_id, usuario_nome, avatar_id FROM membros_equipe
    UNION
    SELECT usuario_id, usuario_nome, NULL::text AS avatar_id FROM tickets_agg WHERE usuario_id = '__outros__'
    UNION
    SELECT usuario_id, usuario_nome, NULL::text AS avatar_id FROM servicos_agg WHERE usuario_id = '__outros__'
  ),
  serie_unificada AS (
    SELECT
      COALESCE(ts.usuario_id, ss.usuario_id) AS usuario_id,
      COALESCE(ts.periodo, ss.periodo) AS periodo,
      COALESCE(ts.periodo_ordem, ss.periodo_ordem) AS periodo_ordem,
      COALESCE(ts.tickets, 0) AS tickets,
      COALESCE(ts.pontos_tickets, 0) AS pontos_tickets,
      COALESCE(ss.servicos, 0) AS servicos,
      COALESCE(ss.pontos_servicos, 0) AS pontos_servicos
    FROM tickets_series ts
    FULL OUTER JOIN servicos_series ss
      ON ss.usuario_id = ts.usuario_id
     AND ss.periodo_ordem = ts.periodo_ordem
  ),
  serie_json AS (
    SELECT
      su.usuario_id,
      jsonb_agg(
        jsonb_build_object(
          'periodo', su.periodo,
          'periodo_ordem', to_char(su.periodo_ordem, 'YYYY-MM-DD"T"HH24:MI:SS'),
          'pontos', su.pontos_tickets + su.pontos_servicos,
          'pontos_tickets', su.pontos_tickets,
          'pontos_servicos', su.pontos_servicos,
          'tickets', su.tickets,
          'servicos', su.servicos
        )
        ORDER BY su.periodo_ordem
      ) AS serie
    FROM serie_unificada su
    GROUP BY su.usuario_id
  ),
  periodos_ativos AS (
    SELECT
      su.usuario_id,
      COUNT(*) FILTER (WHERE su.pontos_tickets + su.pontos_servicos > 0)::integer AS periodos_ativos
    FROM serie_unificada su
    GROUP BY su.usuario_id
  ),
  consolidado AS (
    SELECT
      p.usuario_id,
      p.usuario_nome,
      p.avatar_id,
      COALESCE(ta.tickets_total, 0) AS tickets_total,
      COALESCE(ta.pontos_tickets, 0) AS pontos_tickets,
      COALESCE(ta.tickets_pesados, 0) AS tickets_pesados,
      COALESCE(ta.tickets_sos_total, 0) AS tickets_sos_total,
      COALESCE(ta.pontos_bonus_sos, 0) AS pontos_bonus_sos,
      COALESCE(ta.tickets_vip_total, 0) AS tickets_vip_total,
      COALESCE(ta.pontos_bonus_vip, 0) AS pontos_bonus_vip,
      COALESCE(ta.tickets_com_fallback_origem, 0) AS tickets_com_fallback_origem,
      COALESCE(sa.servicos_total, 0) AS servicos_total,
      COALESCE(sa.servicos_registros, 0) AS servicos_registros,
      COALESCE(sa.servicos_horas, 0) AS servicos_horas,
      COALESCE(sa.servicos_unidades, 0) AS servicos_unidades,
      COALESCE(sa.pontos_servicos, 0) AS pontos_servicos,
      COALESCE(pa.periodos_ativos, 0) AS periodos_ativos,
      COALESCE(td.ticket_pontos_por_dia, '[]'::jsonb) AS ticket_pontos_por_dia,
      COALESCE(stj.servicos_por_tipo, '[]'::jsonb) AS servicos_por_tipo,
      COALESCE(sj.serie, '[]'::jsonb) AS serie
    FROM participantes p
    LEFT JOIN tickets_agg ta ON ta.usuario_id = p.usuario_id
    LEFT JOIN servicos_agg sa ON sa.usuario_id = p.usuario_id
    LEFT JOIN periodos_ativos pa ON pa.usuario_id = p.usuario_id
    LEFT JOIN ticket_dias td ON td.usuario_id = p.usuario_id
    LEFT JOIN servicos_por_tipo_json stj ON stj.usuario_id = p.usuario_id
    LEFT JOIN serie_json sj ON sj.usuario_id = p.usuario_id
  ),
  ranqueado AS (
    SELECT
      c.*,
      (c.pontos_tickets + c.pontos_servicos) AS pontos_total,
      row_number() OVER (
        ORDER BY (c.pontos_tickets + c.pontos_servicos) DESC, c.usuario_nome ASC
      )::integer AS posicao,
      LEAST(10, GREATEST(1, FLOOR((c.pontos_tickets + c.pontos_servicos)::numeric / 100)::integer + 1)) AS nivel
    FROM consolidado c
  ),
  final AS (
    SELECT
      r.*,
      (
        SELECT COALESCE(jsonb_agg(b.badge), '[]'::jsonb)
        FROM (VALUES
          (CASE WHEN r.posicao = 1 AND r.pontos_total > 0 THEN jsonb_build_object('id', 'lider', 'label', 'Lider da rodada', 'tone', 'gold') END),
          (CASE WHEN r.tickets_total >= 10 THEN jsonb_build_object('id', 'maratonista_tickets', 'label', 'Maratonista de tickets', 'tone', 'blue') END),
          (CASE WHEN r.tickets_total >= 25 THEN jsonb_build_object('id', 'comandante_fila', 'label', 'Comandante da fila', 'tone', 'cyan') END),
          (CASE WHEN r.tickets_pesados >= 3 THEN jsonb_build_object('id', 'resgatador_backlog', 'label', 'Resgatador de backlog', 'tone', 'orange') END),
          (CASE WHEN r.pontos_tickets >= 20 AND r.pontos_tickets >= r.pontos_servicos * 2 THEN jsonb_build_object('id', 'especialista_fila', 'label', 'Especialista de fila', 'tone', 'blue') END),
          (CASE WHEN r.pontos_servicos > r.pontos_tickets AND r.pontos_servicos > 0 THEN jsonb_build_object('id', 'mestre_servicos', 'label', 'Mestre dos servicos', 'tone', 'green') END),
          (CASE WHEN r.servicos_registros >= 5 AND r.pontos_servicos >= 50 THEN jsonb_build_object('id', 'arquiteto_servicos', 'label', 'Arquiteto de servicos', 'tone', 'teal') END),
          (CASE WHEN r.servicos_horas >= 2 THEN jsonb_build_object('id', 'modo_hora', 'label', 'Modo hora extra', 'tone', 'purple') END),
          (CASE WHEN LEAST(r.pontos_tickets, r.pontos_servicos) > 0 AND LEAST(r.pontos_tickets, r.pontos_servicos)::numeric / GREATEST(r.pontos_tickets, r.pontos_servicos)::numeric >= 0.4 THEN jsonb_build_object('id', 'polivalente', 'label', 'Polivalente', 'tone', 'teal') END),
          (CASE WHEN r.pontos_total >= 100 AND (r.tickets_total + r.servicos_registros) <= 5 THEN jsonb_build_object('id', 'impacto_relampago', 'label', 'Impacto relampago', 'tone', 'amber') END),
          (CASE WHEN r.periodos_ativos >= 3 THEN jsonb_build_object('id', 'constancia_rodada', 'label', 'Constancia da rodada', 'tone', 'green') END),
          (CASE WHEN r.pontos_total >= 500 THEN jsonb_build_object('id', 'combo_alto', 'label', 'Combo alto', 'tone', 'purple') END),
          (CASE WHEN r.pontos_total >= 1000 THEN jsonb_build_object('id', 'lenda_arena', 'label', 'Lenda da Arena', 'tone', 'rose') END)
        ) AS b(badge)
        WHERE b.badge IS NOT NULL
      ) AS badges
    FROM ranqueado r
  )
  SELECT jsonb_build_object(
    'sucesso', true,
    'periodo', p_periodo,
    'periodo_inicio', v_data_inicio,
    'atualizado_em', now(),
    'ranking', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'posicao', f.posicao,
          'usuario_id', f.usuario_id,
          'usuario_nome', f.usuario_nome,
          'avatar_id', f.avatar_id,
          'pontos_total', f.pontos_total,
          'pontos_tickets', f.pontos_tickets,
          'pontos_servicos', f.pontos_servicos,
          'tickets_total', f.tickets_total,
          'tickets_sos_total', f.tickets_sos_total,
          'pontos_bonus_sos', f.pontos_bonus_sos,
          'tickets_vip_total', f.tickets_vip_total,
          'pontos_bonus_vip', f.pontos_bonus_vip,
          'servicos_total', f.servicos_total,
          'servicos_registros', f.servicos_registros,
          'servicos_horas', f.servicos_horas,
          'servicos_unidades', f.servicos_unidades,
          'ticket_pontos_por_dia', f.ticket_pontos_por_dia,
          'servicos_por_tipo', f.servicos_por_tipo,
          'serie', f.serie,
          'badges', f.badges,
          'nivel', f.nivel
        )
        ORDER BY f.posicao
      )
      FROM final f
    ), '[]'::jsonb),
    'totais', jsonb_build_object(
      'pontos_total', COALESCE((SELECT SUM(f.pontos_total) FROM final f), 0),
      'pontos_tickets', COALESCE((SELECT SUM(f.pontos_tickets) FROM final f), 0),
      'pontos_servicos', COALESCE((SELECT SUM(f.pontos_servicos) FROM final f), 0),
      'tickets_total', COALESCE((SELECT SUM(f.tickets_total) FROM final f), 0),
      'servicos_total', COALESCE((SELECT SUM(f.servicos_total) FROM final f), 0),
      'servicos_registros', COALESCE((SELECT SUM(f.servicos_registros) FROM final f), 0),
      'membros_total', COALESCE((SELECT COUNT(*) FROM final f), 0)
    ),
    'diagnostico', jsonb_build_object(
      'gse_count', COALESCE(cardinality(v_gses), 0),
      'tickets_com_fallback_origem', COALESCE((SELECT SUM(f.tickets_com_fallback_origem) FROM final f), 0),
      'tipos_hora_sincronizados_com_servicos_config', true,
      'janela_local_truncada', true
    )
  )
  INTO v_resultado;

  RETURN v_resultado;
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'periodo', p_periodo,
      'erro', 'Erro ao obter estatisticas gamificadas.',
      'detalhe', SQLERRM
    );
END;
$function$;
COMMENT ON FUNCTION public.obter_estatisticas_gamificadas(uuid, text)
IS 'Ranking gamificado por equipe. Tickets encerrados em Suspensos valem 1 ponto fixo; tickets encerrados em Livres usam a espera como base, com multiplicadores SOS 3x e VIP 2x. Servicos usam timestamptz convertido para America/Sao_Paulo. O periodo today usa o dia calendario local atual com buckets horarios; 24h/48h/72h continuam em janelas moveis truncadas por hora. O ranking tambem expoe badges expandidas, o avatar configurado pelo usuario e agregados de SOS/VIP para o drilldown.';
GRANT EXECUTE ON FUNCTION public.obter_estatisticas_gamificadas(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_estatisticas_gamificadas(uuid, text) TO service_role;
CREATE OR REPLACE FUNCTION public.obter_detalhes_tickets_gamificacao(
  p_equipe_id uuid,
  p_usuario_id text,
  p_periodo text DEFAULT 'today'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_now_local timestamp;
  v_data_inicio_local timestamp;
  v_data_fim_local timestamp;
  v_gses text[];
  v_resultado jsonb;
BEGIN
  v_now_local := now() AT TIME ZONE 'America/Sao_Paulo';

  IF p_periodo = 'today' THEN
    v_data_inicio_local := date_trunc('day', v_now_local);
    v_data_fim_local := v_data_inicio_local + INTERVAL '1 day';
  ELSIF p_periodo = '24h' THEN
    v_data_fim_local := date_trunc('hour', v_now_local) + INTERVAL '1 hour';
    v_data_inicio_local := v_data_fim_local - INTERVAL '24 hours';
  ELSIF p_periodo = '48h' THEN
    v_data_fim_local := date_trunc('hour', v_now_local) + INTERVAL '1 hour';
    v_data_inicio_local := v_data_fim_local - INTERVAL '48 hours';
  ELSIF p_periodo = '72h' THEN
    v_data_fim_local := date_trunc('hour', v_now_local) + INTERVAL '1 hour';
    v_data_inicio_local := v_data_fim_local - INTERVAL '72 hours';
  ELSIF p_periodo = '7d' THEN
    v_data_fim_local := date_trunc('day', v_now_local) + INTERVAL '1 day';
    v_data_inicio_local := v_data_fim_local - INTERVAL '7 days';
  ELSIF p_periodo = '30d' THEN
    v_data_fim_local := date_trunc('day', v_now_local) + INTERVAL '1 day';
    v_data_inicio_local := v_data_fim_local - INTERVAL '30 days';
  ELSIF p_periodo = 'all' THEN
    v_data_inicio_local := NULL;
    v_data_fim_local := NULL;
  ELSE
    v_data_inicio_local := date_trunc('day', v_now_local);
    v_data_fim_local := v_data_inicio_local + INTERVAL '1 day';
  END IF;

  SELECT COALESCE(array_agg(ge.gse), ARRAY[]::text[])
  INTO v_gses
  FROM public.gse_equipes ge
  WHERE ge.equipe_id = p_equipe_id;

  WITH membros_equipe AS (
    SELECT
      u.id::text AS usuario_id,
      COALESCE(NULLIF(TRIM(u.nome), ''), u.email, 'Membro') AS usuario_nome
    FROM public.users u
    WHERE u.equipe_id = p_equipe_id
      AND (u.ativo IS NULL OR u.ativo = true)
  ),
  tickets_detalhe AS (
    SELECT
      t.id::text AS ticket_id,
      NULLIF(TRIM(t.numero_chamado), '') AS numero_chamado,
      t.finished_at,
      COALESCE(me.usuario_id, '__outros__') AS usuario_id,
      COALESCE(me.usuario_nome, 'Outros') AS usuario_nome,
      calc.pontos_ticket_base AS pontos_base,
      calc.multiplicador_ticket AS multiplicador,
      (calc.pontos_ticket_base * calc.multiplicador_ticket) AS pontos_total,
      ((calc.pontos_ticket_base * calc.multiplicador_ticket) - calc.pontos_ticket_base) AS pontos_bonus,
      CASE
        WHEN calc.contexto_finalizacao = 'suspensos' THEN 'suspenso'
        WHEN COALESCE(t.sos, false) THEN 'sos'
        WHEN COALESCE(t.vip, false) THEN 'vip'
        ELSE 'base'
      END AS multiplicador_origem,
      COALESCE(t.sos, false) AS sos,
      COALESCE(t.vip, false) AS vip
    FROM public.tickets t
    LEFT JOIN membros_equipe me ON me.usuario_id = t.usuario_atual::text
    CROSS JOIN LATERAL (
      SELECT
        base.contexto_finalizacao,
        CASE
          WHEN base.contexto_finalizacao = 'suspensos' THEN 1
          ELSE base.pontos_ticket_base_livres
        END AS pontos_ticket_base,
        CASE
          WHEN base.contexto_finalizacao = 'suspensos' THEN 1
          WHEN COALESCE(t.sos, false) THEN 3
          WHEN COALESCE(t.vip, false) THEN 2
          ELSE 1
        END AS multiplicador_ticket
      FROM (
        SELECT
          COALESCE(
            NULLIF(t.fila_finalizacao_contexto, ''),
            CASE WHEN COALESCE(t.suspenso, false) THEN 'suspensos' ELSE 'livres' END
          ) AS contexto_finalizacao,
          GREATEST(
            1,
            CEIL(
              GREATEST(
                0::numeric,
                EXTRACT(EPOCH FROM (t.finished_at - COALESCE(t.tempo_espera_origem, t.created_at, t.finished_at))) / 3600.0
              ) / 24.0
            )::integer
          ) AS pontos_ticket_base_livres
      ) base
    ) calc
    WHERE t.gse = ANY(v_gses)
      AND t.status = 'finalizado'
      AND t.finished_at IS NOT NULL
      AND t.usuario_atual IS NOT NULL
      AND COALESCE(me.usuario_id, '__outros__') = p_usuario_id
      AND (
        v_data_inicio_local IS NULL
        OR (
          t.finished_at >= v_data_inicio_local
          AND (v_data_fim_local IS NULL OR t.finished_at < v_data_fim_local)
        )
      )
  )
  SELECT jsonb_build_object(
    'sucesso', true,
    'periodo', p_periodo,
    'tickets', COALESCE((
      SELECT jsonb_agg(
        jsonb_build_object(
          'ticket_id', td.ticket_id,
          'numero_chamado', td.numero_chamado,
          'finished_at', CASE
            WHEN td.finished_at IS NULL THEN NULL
            ELSE to_char(td.finished_at, 'YYYY-MM-DD"T"HH24:MI:SS')
          END,
          'pontos_base', td.pontos_base,
          'multiplicador', td.multiplicador,
          'pontos_total', td.pontos_total,
          'pontos_bonus', td.pontos_bonus,
          'multiplicador_origem', td.multiplicador_origem,
          'sos', td.sos,
          'vip', td.vip
        )
        ORDER BY td.pontos_total DESC, td.finished_at DESC NULLS LAST, td.numero_chamado ASC
      )
      FROM tickets_detalhe td
    ), '[]'::jsonb)
  )
  INTO v_resultado;

  RETURN v_resultado;
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'periodo', p_periodo,
      'tickets', '[]'::jsonb,
      'erro', 'Erro ao obter detalhes dos tickets da Arena.',
      'detalhe', SQLERRM
    );
END;
$function$;
COMMENT ON FUNCTION public.obter_detalhes_tickets_gamificacao(uuid, text, text)
IS 'Detalha tickets usados na Arena de Pontos para um usuario e periodo. Tickets encerrados em Suspensos retornam 1 ponto fixo; tickets encerrados em Livres retornam base por espera com multiplicadores SOS/VIP quando aplicavel.';
GRANT EXECUTE ON FUNCTION public.obter_detalhes_tickets_gamificacao(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_detalhes_tickets_gamificacao(uuid, text, text) TO service_role;

DROP FUNCTION IF EXISTS public.obter_estatisticas_gamificadas(uuid, text);
CREATE OR REPLACE FUNCTION public.obter_estatisticas_gamificadas(
  p_equipe_id uuid,
  p_periodo text DEFAULT '30d'
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_data_inicio timestamptz;
  v_gses text[];
  v_resultado jsonb;
BEGIN
  v_data_inicio := CASE p_periodo
    WHEN '24h' THEN now() - INTERVAL '24 hours'
    WHEN '48h' THEN now() - INTERVAL '48 hours'
    WHEN '72h' THEN now() - INTERVAL '72 hours'
    WHEN '7d' THEN now() - INTERVAL '7 days'
    WHEN '30d' THEN now() - INTERVAL '30 days'
    WHEN 'all' THEN NULL
    ELSE now() - INTERVAL '30 days'
  END;

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
  tickets_base AS (
    SELECT
      COALESCE(me.usuario_id, '__outros__') AS usuario_id,
      COALESCE(me.usuario_nome, 'Outros') AS usuario_nome,
      CASE
        WHEN p_periodo IN ('24h', '48h', '72h') THEN
          to_char(t.finished_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24"h"')
        WHEN p_periodo = 'all' THEN
          to_char(t.finished_at AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD')
        ELSE
          to_char(t.finished_at AT TIME ZONE 'America/Sao_Paulo', 'DD/MM')
      END AS periodo,
      CASE
        WHEN p_periodo IN ('24h', '48h', '72h') THEN
          date_trunc('hour', t.finished_at AT TIME ZONE 'America/Sao_Paulo')
        ELSE
          date_trunc('day', t.finished_at AT TIME ZONE 'America/Sao_Paulo')
      END AS periodo_ordem,
      GREATEST(
        1,
        CEIL(
          GREATEST(
            0::numeric,
            EXTRACT(EPOCH FROM (t.finished_at - COALESCE(t.tempo_espera_origem, t.created_at, t.finished_at))) / 3600.0
          ) / 24.0
        )::integer
      ) AS pontos_ticket,
      (t.tempo_espera_origem IS NULL) AS usou_fallback_origem
    FROM public.tickets t
    LEFT JOIN membros_equipe me ON me.usuario_id = t.usuario_atual::text
    WHERE t.gse = ANY(v_gses)
      AND t.status = 'finalizado'
      AND t.finished_at IS NOT NULL
      AND t.usuario_atual IS NOT NULL
      AND (v_data_inicio IS NULL OR t.finished_at >= v_data_inicio)
  ),
  tickets_agg AS (
    SELECT
      tb.usuario_id,
      MIN(tb.usuario_nome) AS usuario_nome,
      COUNT(*)::integer AS tickets_total,
      COALESCE(SUM(tb.pontos_ticket), 0)::integer AS pontos_tickets,
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
        WHEN p_periodo IN ('24h', '48h', '72h') THEN
          to_char(s.data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM HH24"h"')
        WHEN p_periodo = 'all' THEN
          to_char(s.data_execucao AT TIME ZONE 'America/Sao_Paulo', 'YYYY-MM-DD')
        ELSE
          to_char(s.data_execucao AT TIME ZONE 'America/Sao_Paulo', 'DD/MM')
      END AS periodo,
      CASE
        WHEN p_periodo IN ('24h', '48h', '72h') THEN
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
      AND (v_data_inicio IS NULL OR s.data_execucao >= v_data_inicio)
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
    SELECT usuario_id, usuario_nome FROM membros_equipe
    UNION
    SELECT usuario_id, usuario_nome FROM tickets_agg WHERE usuario_id = '__outros__'
    UNION
    SELECT usuario_id, usuario_nome FROM servicos_agg WHERE usuario_id = '__outros__'
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
     AND ss.periodo = ts.periodo
  ),
  serie_json AS (
    SELECT
      su.usuario_id,
      jsonb_agg(
        jsonb_build_object(
          'periodo', su.periodo,
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
  consolidado AS (
    SELECT
      p.usuario_id,
      p.usuario_nome,
      COALESCE(ta.tickets_total, 0) AS tickets_total,
      COALESCE(ta.pontos_tickets, 0) AS pontos_tickets,
      COALESCE(ta.tickets_com_fallback_origem, 0) AS tickets_com_fallback_origem,
      COALESCE(sa.servicos_total, 0) AS servicos_total,
      COALESCE(sa.servicos_registros, 0) AS servicos_registros,
      COALESCE(sa.servicos_horas, 0) AS servicos_horas,
      COALESCE(sa.servicos_unidades, 0) AS servicos_unidades,
      COALESCE(sa.pontos_servicos, 0) AS pontos_servicos,
      COALESCE(td.ticket_pontos_por_dia, '[]'::jsonb) AS ticket_pontos_por_dia,
      COALESCE(sj.serie, '[]'::jsonb) AS serie
    FROM participantes p
    LEFT JOIN tickets_agg ta ON ta.usuario_id = p.usuario_id
    LEFT JOIN servicos_agg sa ON sa.usuario_id = p.usuario_id
    LEFT JOIN ticket_dias td ON td.usuario_id = p.usuario_id
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
          (CASE WHEN r.pontos_servicos > r.pontos_tickets AND r.pontos_servicos > 0 THEN jsonb_build_object('id', 'mestre_servicos', 'label', 'Mestre dos servicos', 'tone', 'green') END),
          (CASE WHEN r.pontos_total >= 500 THEN jsonb_build_object('id', 'combo_alto', 'label', 'Combo alto', 'tone', 'purple') END)
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
          'pontos_total', f.pontos_total,
          'pontos_tickets', f.pontos_tickets,
          'pontos_servicos', f.pontos_servicos,
          'tickets_total', f.tickets_total,
          'servicos_total', f.servicos_total,
          'servicos_registros', f.servicos_registros,
          'servicos_horas', f.servicos_horas,
          'servicos_unidades', f.servicos_unidades,
          'ticket_pontos_por_dia', f.ticket_pontos_por_dia,
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
      'tipos_hora_sincronizados_com_servicos_config', true
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
IS 'Ranking gamificado por equipe. Tickets finalizados pontuam por dias de espera arredondados para cima; servicos em horas valem 10 pontos por hora e unidades valem 1 ponto por unidade. Manter a lista de tipos por hora sincronizada com src/services/servicosService.ts.';
GRANT EXECUTE ON FUNCTION public.obter_estatisticas_gamificadas(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_estatisticas_gamificadas(uuid, text) TO service_role;

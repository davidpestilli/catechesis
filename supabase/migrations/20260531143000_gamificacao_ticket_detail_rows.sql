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
        GREATEST(
          1,
          CEIL(
            GREATEST(
              0::numeric,
              EXTRACT(EPOCH FROM (t.finished_at - COALESCE(t.tempo_espera_origem, t.created_at, t.finished_at))) / 3600.0
            ) / 24.0
          )::integer
        ) AS pontos_ticket_base,
        CASE
          WHEN COALESCE(t.sos, false) THEN 3
          WHEN COALESCE(t.vip, false) THEN 2
          ELSE 1
        END AS multiplicador_ticket
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
IS 'Detalha tickets usados na Arena de Pontos para um usuario e periodo. Retorna linhas individuais com numero do chamado, pontos base, multiplicador aplicado, pontos finais e flags SOS/VIP.';
GRANT EXECUTE ON FUNCTION public.obter_detalhes_tickets_gamificacao(uuid, text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.obter_detalhes_tickets_gamificacao(uuid, text, text) TO service_role;

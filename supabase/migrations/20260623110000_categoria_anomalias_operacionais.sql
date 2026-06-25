-- Migration: 20260623110000_categoria_anomalias_operacionais
-- Objetivo:
-- 1. Reduzir falsos positivos de volume puro, exigindo sinais operacionais
--    adicionais para ativar alertas e criticos.
-- 2. Evitar duplicidade entre categoria e subcategoria quando a subcategoria
--    explica a maior parte do desvio.
-- 3. Consolidar a ocorrencia ativa para que apenas a execucao mais recente
--    permaneça ativa.
-- 4. Evitar nova notificacao in-app a cada hora para a mesma ocorrencia,
--    notificando apenas no primeiro disparo ou em escalacao real.

CREATE OR REPLACE FUNCTION public.executar_analise_anomalias_categorias(
  p_now timestamptz DEFAULT now(),
  p_equipe_id uuid DEFAULT NULL,
  p_dry_run boolean DEFAULT false
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_now_local timestamp without time zone := (p_now AT TIME ZONE 'America/Sao_Paulo')::timestamp;
  v_janela_fim timestamp without time zone := date_trunc('hour', (p_now AT TIME ZONE 'America/Sao_Paulo')::timestamp);
  v_janela_inicio timestamp without time zone;
  v_data_referencia date;
  v_hora_corte integer;
  v_dia_semana integer;
  v_alertas jsonb;
  v_total_equipes integer;
  v_total_itens integer;
  v_total_alertas integer;
  v_total_baseline_insuficiente integer;
BEGIN
  IF v_janela_fim = v_now_local THEN
    v_janela_fim := v_janela_fim - INTERVAL '1 hour';
  END IF;

  v_janela_inicio := v_janela_fim - INTERVAL '1 hour';
  v_data_referencia := v_janela_inicio::date;
  v_hora_corte := EXTRACT(hour FROM v_janela_inicio)::int;
  v_dia_semana := EXTRACT(dow FROM v_data_referencia)::int;

  IF p_dry_run IS NOT TRUE THEN
    PERFORM public.refresh_categoria_baseline_horaria();
  END IF;

  DROP TABLE IF EXISTS tmp_categoria_anomalia_target_equipes;
  CREATE TEMP TABLE tmp_categoria_anomalia_target_equipes ON COMMIT DROP AS
  SELECT DISTINCT ge.equipe_id
  FROM public.gse_equipes ge
  WHERE p_equipe_id IS NULL OR ge.equipe_id = p_equipe_id;

  IF p_equipe_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM tmp_categoria_anomalia_target_equipes) THEN
    INSERT INTO tmp_categoria_anomalia_target_equipes (equipe_id)
    VALUES (p_equipe_id);
  END IF;

  IF p_dry_run IS TRUE THEN
    DROP TABLE IF EXISTS tmp_categoria_anomalia_execucoes;
    CREATE TEMP TABLE tmp_categoria_anomalia_execucoes ON COMMIT DROP AS
    SELECT gen_random_uuid() AS execucao_id, equipe_id
    FROM tmp_categoria_anomalia_target_equipes;
  ELSE
    DROP TABLE IF EXISTS tmp_categoria_anomalia_execucoes;
    CREATE TEMP TABLE tmp_categoria_anomalia_execucoes ON COMMIT DROP AS
    WITH upserted AS (
      INSERT INTO public.categoria_anomalia_execucoes (
        equipe_id,
        started_at,
        finished_at,
        analisado_em,
        data_referencia,
        hora_corte,
        janela_inicio,
        janela_fim,
        status,
        total_itens,
        total_alertas,
        total_baseline_insuficiente,
        erro,
        updated_at
      )
      SELECT
        equipe_id,
        clock_timestamp(),
        NULL,
        p_now,
        v_data_referencia,
        v_hora_corte,
        v_data_referencia::timestamp,
        v_janela_fim,
        'executando',
        0,
        0,
        0,
        NULL,
        now()
      FROM tmp_categoria_anomalia_target_equipes
      ON CONFLICT (equipe_id, data_referencia, hora_corte) DO UPDATE SET
        started_at = EXCLUDED.started_at,
        finished_at = NULL,
        analisado_em = EXCLUDED.analisado_em,
        janela_inicio = EXCLUDED.janela_inicio,
        janela_fim = EXCLUDED.janela_fim,
        status = 'executando',
        total_itens = 0,
        total_alertas = 0,
        total_baseline_insuficiente = 0,
        erro = NULL,
        updated_at = now()
      RETURNING id AS execucao_id, equipe_id
    )
    SELECT execucao_id, equipe_id FROM upserted;
  END IF;

  DROP TABLE IF EXISTS tmp_categoria_anomalia_observados;
  CREATE TEMP TABLE tmp_categoria_anomalia_observados ON COMMIT DROP AS
  WITH eventos_entrada AS (
    SELECT DISTINCT
      ge.equipe_id,
      'categoria'::text AS nivel,
      CASE WHEN ta.categoria_equipe_id IS NOT NULL THEN 'hierarquico' ELSE 'flat' END AS key_tipo,
      COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) AS categoria_key,
      ''::text AS subcategoria_key,
      COALESCE(ce.nome, cc.nome, ta.categoria_slug) AS categoria_nome,
      NULL::text AS subcategoria_nome,
      t.id AS ticket_id,
      t.tempo_espera_origem
    FROM public.ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    JOIN tmp_categoria_anomalia_target_equipes te ON te.equipe_id = ge.equipe_id
    LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
    LEFT JOIN public.categorias_chamado cc ON cc.slug = ta.categoria_slug
    WHERE t.tempo_espera_origem >= v_data_referencia::timestamp
      AND t.tempo_espera_origem < v_janela_fim
      AND COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) IS NOT NULL
      AND COALESCE(ta.categoria_slug, '') <> 'indefinido'

    UNION ALL

    SELECT DISTINCT
      ge.equipe_id,
      'subcategoria'::text AS nivel,
      CASE WHEN ta.subcategoria_gse_id IS NOT NULL THEN 'hierarquico' ELSE 'flat' END AS key_tipo,
      COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) AS categoria_key,
      COALESCE(ta.subcategoria_gse_id::text, ta.subcategoria_slug) AS subcategoria_key,
      COALESCE(ce.nome, cc.nome, ta.categoria_slug) AS categoria_nome,
      COALESCE(sg.nome, sc.nome, ta.subcategoria_slug) AS subcategoria_nome,
      t.id AS ticket_id,
      t.tempo_espera_origem
    FROM public.ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    JOIN tmp_categoria_anomalia_target_equipes te ON te.equipe_id = ge.equipe_id
    LEFT JOIN public.categorias_equipe ce ON ce.id = ta.categoria_equipe_id
    LEFT JOIN public.categorias_chamado cc ON cc.slug = ta.categoria_slug
    LEFT JOIN public.subcategorias_gse sg ON sg.id = ta.subcategoria_gse_id
    LEFT JOIN public.subcategorias_chamado sc ON sc.categoria_slug = ta.categoria_slug AND sc.slug = ta.subcategoria_slug
    WHERE t.tempo_espera_origem >= v_data_referencia::timestamp
      AND t.tempo_espera_origem < v_janela_fim
      AND COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) IS NOT NULL
      AND COALESCE(ta.subcategoria_gse_id::text, ta.subcategoria_slug) IS NOT NULL
      AND COALESCE(ta.categoria_slug, '') <> 'indefinido'
  ),
  entradas_agregadas AS (
    SELECT
      equipe_id,
      nivel,
      key_tipo,
      categoria_key,
      subcategoria_key,
      MAX(categoria_nome) AS categoria_nome,
      MAX(subcategoria_nome) AS subcategoria_nome,
      COUNT(DISTINCT ticket_id)::int AS observado_acumulado,
      COUNT(DISTINCT ticket_id) FILTER (
        WHERE tempo_espera_origem >= v_janela_inicio
          AND tempo_espera_origem < v_janela_fim
      )::int AS observado_ultima_hora
    FROM eventos_entrada
    GROUP BY 1, 2, 3, 4, 5
  ),
  eventos_saida AS (
    SELECT DISTINCT
      ge.equipe_id,
      'categoria'::text AS nivel,
      CASE WHEN ta.categoria_equipe_id IS NOT NULL THEN 'hierarquico' ELSE 'flat' END AS key_tipo,
      COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) AS categoria_key,
      ''::text AS subcategoria_key,
      t.id AS ticket_id,
      t.finished_at AS momento_saida
    FROM public.ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    JOIN tmp_categoria_anomalia_target_equipes te ON te.equipe_id = ge.equipe_id
    WHERE t.finished_at >= v_data_referencia::timestamp
      AND t.finished_at < v_janela_fim
      AND COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) IS NOT NULL
      AND COALESCE(ta.categoria_slug, '') <> 'indefinido'

    UNION ALL

    SELECT DISTINCT
      ge.equipe_id,
      'subcategoria'::text AS nivel,
      CASE WHEN ta.subcategoria_gse_id IS NOT NULL THEN 'hierarquico' ELSE 'flat' END AS key_tipo,
      COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) AS categoria_key,
      COALESCE(ta.subcategoria_gse_id::text, ta.subcategoria_slug) AS subcategoria_key,
      t.id AS ticket_id,
      t.finished_at AS momento_saida
    FROM public.ticket_analises ta
    JOIN public.tickets t ON t.id = ta.ticket_id
    JOIN public.gse_equipes ge ON ge.gse = t.gse
    JOIN tmp_categoria_anomalia_target_equipes te ON te.equipe_id = ge.equipe_id
    WHERE t.finished_at >= v_data_referencia::timestamp
      AND t.finished_at < v_janela_fim
      AND COALESCE(ta.categoria_equipe_id::text, ta.categoria_slug) IS NOT NULL
      AND COALESCE(ta.subcategoria_gse_id::text, ta.subcategoria_slug) IS NOT NULL
      AND COALESCE(ta.categoria_slug, '') <> 'indefinido'
  ),
  saidas_agregadas AS (
    SELECT
      equipe_id,
      nivel,
      key_tipo,
      categoria_key,
      subcategoria_key,
      COUNT(DISTINCT ticket_id)::int AS respondido_acumulado,
      COUNT(DISTINCT ticket_id) FILTER (
        WHERE momento_saida >= v_janela_inicio
          AND momento_saida < v_janela_fim
      )::int AS respondido_ultima_hora
    FROM eventos_saida
    GROUP BY 1, 2, 3, 4, 5
  )
  SELECT
    ea.equipe_id,
    ea.nivel,
    ea.key_tipo,
    ea.categoria_key,
    ea.subcategoria_key,
    ea.categoria_nome,
    ea.subcategoria_nome,
    ea.observado_acumulado,
    ea.observado_ultima_hora,
    COALESCE(sa.respondido_acumulado, 0)::int AS respondido_acumulado,
    COALESCE(sa.respondido_ultima_hora, 0)::int AS respondido_ultima_hora,
    GREATEST(ea.observado_acumulado - COALESCE(sa.respondido_acumulado, 0), 0)::int AS saldo_acumulado
  FROM entradas_agregadas ea
  LEFT JOIN saidas_agregadas sa
    ON sa.equipe_id = ea.equipe_id
   AND sa.nivel = ea.nivel
   AND sa.key_tipo = ea.key_tipo
   AND sa.categoria_key = ea.categoria_key
   AND sa.subcategoria_key = ea.subcategoria_key;

  DROP TABLE IF EXISTS tmp_categoria_anomalia_resultados;
  CREATE TEMP TABLE tmp_categoria_anomalia_resultados ON COMMIT DROP AS
  WITH metricas AS (
    SELECT
      e.execucao_id,
      o.equipe_id,
      o.nivel,
      o.key_tipo,
      o.categoria_key,
      o.subcategoria_key,
      o.categoria_nome,
      o.subcategoria_nome,
      o.observado_acumulado,
      o.observado_ultima_hora,
      o.respondido_acumulado,
      o.respondido_ultima_hora,
      o.saldo_acumulado,
      b.media_acumulada,
      b.stddev_acumulado,
      b.p75_acumulada,
      b.p95_acumulada,
      b.maximo_acumulado,
      b.media_ultima_hora,
      b.stddev_ultima_hora,
      b.p75_ultima_hora,
      b.p95_ultima_hora,
      b.maximo_ultima_hora,
      b.dias_amostra,
      CASE
        WHEN b.stddev_acumulado > 0 THEN ROUND(((o.observado_acumulado - b.media_acumulada) / b.stddev_acumulado)::numeric, 2)
        ELSE NULL
      END AS z_score_acumulado,
      CASE
        WHEN b.stddev_ultima_hora > 0 THEN ROUND(((o.observado_ultima_hora - b.media_ultima_hora) / b.stddev_ultima_hora)::numeric, 2)
        ELSE NULL
      END AS z_score_ultima_hora,
      CASE
        WHEN b.media_acumulada > 0 THEN ROUND(((o.observado_acumulado - b.media_acumulada) / b.media_acumulada * 100)::numeric, 0)
        ELSE NULL
      END AS percentual_acima_acumulado,
      CASE
        WHEN b.media_ultima_hora > 0 THEN ROUND(((o.observado_ultima_hora - b.media_ultima_hora) / b.media_ultima_hora * 100)::numeric, 0)
        ELSE NULL
      END AS percentual_acima_ultima_hora,
      prev.status AS status_anterior,
      prev.analisado_em AS analisado_anterior
    FROM tmp_categoria_anomalia_observados o
    JOIN tmp_categoria_anomalia_execucoes e ON e.equipe_id = o.equipe_id
    LEFT JOIN public.mv_categoria_baseline_horaria_dow b
      ON b.equipe_id = o.equipe_id
     AND b.nivel = o.nivel
     AND b.key_tipo = o.key_tipo
     AND b.categoria_key = o.categoria_key
     AND b.subcategoria_key = o.subcategoria_key
     AND b.dia_semana = v_dia_semana
     AND b.hora_corte = v_hora_corte
    LEFT JOIN LATERAL (
      SELECT
        a.status,
        a.analisado_em
      FROM public.categoria_anomalia_alertas a
      WHERE a.equipe_id = o.equipe_id
        AND a.nivel = o.nivel
        AND a.key_tipo = o.key_tipo
        AND a.categoria_key = o.categoria_key
        AND a.subcategoria_key = o.subcategoria_key
        AND a.status IN ('aviso', 'alerta', 'critico')
        AND a.analisado_em < p_now
      ORDER BY a.analisado_em DESC
      LIMIT 1
    ) prev ON true
  ),
  classificacao_base AS (
    SELECT
      *,
      CASE
        WHEN dias_amostra IS NULL OR dias_amostra < 3 THEN 'baseline_insuficiente'
        WHEN (
          (z_score_acumulado >= 4 AND observado_acumulado - media_acumulada >= 3)
          OR (z_score_ultima_hora >= 4 AND observado_ultima_hora - media_ultima_hora >= 2)
          OR (media_acumulada > 0 AND observado_acumulado >= media_acumulada * 3 AND observado_acumulado - media_acumulada >= 5)
          OR (media_acumulada = 0 AND observado_acumulado >= 5)
        ) THEN 'critico'
        WHEN (
          (z_score_acumulado >= 3 AND observado_acumulado - media_acumulada >= 2)
          OR (z_score_ultima_hora >= 3 AND observado_ultima_hora - media_ultima_hora >= 2)
          OR (media_acumulada > 0 AND observado_acumulado >= media_acumulada * 2 AND observado_acumulado - media_acumulada >= 4)
          OR (p95_acumulada IS NOT NULL AND observado_acumulado > p95_acumulada AND observado_acumulado - media_acumulada >= 5)
        ) THEN 'alerta'
        WHEN (
          (z_score_acumulado >= 2.5 AND observado_acumulado - media_acumulada >= 3)
          OR (z_score_ultima_hora >= 3 AND observado_ultima_hora - media_ultima_hora >= 2)
          OR (p95_acumulada IS NOT NULL AND observado_acumulado > p95_acumulada AND observado_acumulado - media_acumulada >= 4)
          OR (media_acumulada = 0 AND observado_acumulado >= 4)
        ) THEN 'aviso'
        ELSE 'normal'
      END AS status_base
    FROM metricas
  ),
  sinais_operacionais AS (
    SELECT
      *,
      CASE
        WHEN status_anterior IN ('aviso', 'alerta', 'critico')
         AND analisado_anterior >= p_now - INTERVAL '6 hours'
        THEN true
        ELSE false
      END AS tem_persistencia,
      CASE
        WHEN observado_ultima_hora >= 3 AND respondido_ultima_hora = 0 THEN true
        ELSE false
      END AS tem_saida_desalinhada,
      CASE
        WHEN saldo_acumulado >= GREATEST(3, CEIL(observado_acumulado * 0.6)::int) THEN true
        ELSE false
      END AS tem_saldo_pressao,
      CASE
        WHEN COALESCE(z_score_acumulado, 0) >= 6
          OR COALESCE(z_score_ultima_hora, 0) >= 6
          OR (media_acumulada > 0 AND observado_acumulado - media_acumulada >= 10)
          OR observado_ultima_hora >= 8
        THEN true
        ELSE false
      END AS tem_volume_extremo
    FROM classificacao_base
  ),
  status_final_pre AS (
    SELECT
      *,
      CASE
        WHEN status_base = 'critico'
         AND (tem_persistencia OR tem_saida_desalinhada OR tem_saldo_pressao OR tem_volume_extremo)
        THEN 'critico'
        WHEN status_base = 'critico' THEN 'alerta'
        WHEN status_base = 'alerta'
         AND (tem_persistencia OR tem_saida_desalinhada OR tem_saldo_pressao OR tem_volume_extremo)
        THEN 'alerta'
        WHEN status_base = 'alerta' THEN 'aviso'
        ELSE status_base
      END AS status
    FROM sinais_operacionais
  ),
  classificados AS (
    SELECT
      sf.execucao_id,
      sf.equipe_id,
      sf.nivel,
      sf.key_tipo,
      sf.categoria_key,
      sf.subcategoria_key,
      sf.categoria_nome,
      sf.subcategoria_nome,
      sf.observado_acumulado,
      sf.observado_ultima_hora,
      sf.media_acumulada,
      sf.stddev_acumulado,
      sf.p75_acumulada,
      sf.p95_acumulada,
      sf.maximo_acumulado,
      sf.media_ultima_hora,
      sf.stddev_ultima_hora,
      sf.p75_ultima_hora,
      sf.p95_ultima_hora,
      sf.maximo_ultima_hora,
      sf.dias_amostra,
      sf.z_score_acumulado,
      sf.z_score_ultima_hora,
      sf.percentual_acima_acumulado,
      sf.percentual_acima_ultima_hora,
      sf.status,
      (
        sf.status IN ('alerta', 'critico')
        AND (sf.tem_persistencia OR sf.tem_saida_desalinhada OR sf.tem_saldo_pressao OR sf.tem_volume_extremo)
        AND NOT (
          sf.nivel = 'categoria'
          AND COALESCE((
            SELECT SUM(child.observado_acumulado)::int
            FROM status_final_pre child
            WHERE child.equipe_id = sf.equipe_id
              AND child.nivel = 'subcategoria'
              AND child.categoria_key = sf.categoria_key
              AND child.status IN ('alerta', 'critico')
          ), 0) >= GREATEST(3, CEIL(sf.observado_acumulado * 0.6)::int)
        )
      ) AS ativo,
      array_remove(ARRAY[
        CASE WHEN sf.dias_amostra IS NULL THEN 'sem_baseline' END,
        CASE WHEN sf.dias_amostra IS NOT NULL AND sf.dias_amostra < 3 THEN 'amostra_insuficiente' END,
        CASE WHEN sf.z_score_acumulado >= 2.5 AND sf.observado_acumulado - sf.media_acumulada >= 3 THEN 'zscore_acumulado' END,
        CASE WHEN sf.z_score_ultima_hora >= 3 AND sf.observado_ultima_hora - sf.media_ultima_hora >= 2 THEN 'zscore_ultima_hora' END,
        CASE WHEN sf.p95_acumulada IS NOT NULL AND sf.observado_acumulado > sf.p95_acumulada AND sf.observado_acumulado - sf.media_acumulada >= 4 THEN 'acima_p95_acumulado' END,
        CASE WHEN sf.p95_ultima_hora IS NOT NULL AND sf.observado_ultima_hora > sf.p95_ultima_hora AND sf.observado_ultima_hora - sf.media_ultima_hora >= 2 THEN 'acima_p95_ultima_hora' END,
        CASE WHEN sf.media_acumulada = 0 AND sf.observado_acumulado >= 4 THEN 'sem_historico_com_volume' END,
        CASE WHEN sf.tem_persistencia THEN 'persistencia_recente' END,
        CASE WHEN sf.tem_saida_desalinhada THEN 'sem_saida_ultima_hora' END,
        CASE WHEN sf.tem_saldo_pressao THEN 'saldo_entrada_saida' END,
        CASE WHEN sf.tem_volume_extremo THEN 'volume_extremo' END,
        CASE WHEN sf.status_base = 'critico' AND sf.status = 'alerta' THEN 'criticidade_reduzida_sem_sinal_operacional' END,
        CASE WHEN sf.status_base = 'alerta' AND sf.status = 'aviso' THEN 'volume_sem_sinal_operacional' END,
        CASE WHEN sf.nivel = 'categoria'
          AND COALESCE((
            SELECT SUM(child.observado_acumulado)::int
            FROM status_final_pre child
            WHERE child.equipe_id = sf.equipe_id
              AND child.nivel = 'subcategoria'
              AND child.categoria_key = sf.categoria_key
              AND child.status IN ('alerta', 'critico')
          ), 0) >= GREATEST(3, CEIL(sf.observado_acumulado * 0.6)::int)
        THEN 'suprimida_por_subcategoria' END
      ]::text[], NULL) AS motivos
    FROM status_final_pre sf
  )
  SELECT
    execucao_id,
    equipe_id,
    nivel,
    key_tipo,
    categoria_key,
    subcategoria_key,
    categoria_nome,
    subcategoria_nome,
    observado_acumulado,
    observado_ultima_hora,
    media_acumulada,
    stddev_acumulado,
    p75_acumulada,
    p95_acumulada,
    maximo_acumulado,
    media_ultima_hora,
    stddev_ultima_hora,
    p75_ultima_hora,
    p95_ultima_hora,
    maximo_ultima_hora,
    dias_amostra,
    z_score_acumulado,
    z_score_ultima_hora,
    percentual_acima_acumulado,
    percentual_acima_ultima_hora,
    status,
    motivos,
    ativo
  FROM classificados;

  IF p_dry_run IS NOT TRUE THEN
    UPDATE public.categoria_anomalia_alertas a
    SET ativo = false,
        normalizado_em = COALESCE(a.normalizado_em, now()),
        updated_at = now()
    WHERE a.ativo = true
      AND a.status IN ('aviso', 'alerta', 'critico')
      AND a.equipe_id IN (SELECT equipe_id FROM tmp_categoria_anomalia_target_equipes);

    INSERT INTO public.categoria_anomalia_alertas (
      execucao_id,
      equipe_id,
      nivel,
      key_tipo,
      categoria_key,
      subcategoria_key,
      categoria_nome,
      subcategoria_nome,
      data_referencia,
      hora_corte,
      janela_inicio,
      janela_fim,
      observado_acumulado,
      observado_ultima_hora,
      baseline_media_acumulada,
      baseline_stddev_acumulado,
      baseline_p75_acumulada,
      baseline_p95_acumulada,
      baseline_maximo_acumulado,
      baseline_media_ultima_hora,
      baseline_stddev_ultima_hora,
      baseline_p75_ultima_hora,
      baseline_p95_ultima_hora,
      baseline_maximo_ultima_hora,
      dias_amostra,
      z_score_acumulado,
      z_score_ultima_hora,
      percentual_acima_acumulado,
      percentual_acima_ultima_hora,
      status,
      motivos,
      ativo,
      normalizado_em,
      analisado_em,
      updated_at
    )
    SELECT
      execucao_id,
      equipe_id,
      nivel,
      key_tipo,
      categoria_key,
      subcategoria_key,
      categoria_nome,
      subcategoria_nome,
      v_data_referencia,
      v_hora_corte,
      v_data_referencia::timestamp,
      v_janela_fim,
      observado_acumulado,
      observado_ultima_hora,
      media_acumulada,
      stddev_acumulado,
      p75_acumulada,
      p95_acumulada,
      maximo_acumulado,
      media_ultima_hora,
      stddev_ultima_hora,
      p75_ultima_hora,
      p95_ultima_hora,
      maximo_ultima_hora,
      dias_amostra,
      z_score_acumulado,
      z_score_ultima_hora,
      percentual_acima_acumulado,
      percentual_acima_ultima_hora,
      status,
      motivos,
      ativo,
      CASE WHEN ativo THEN NULL ELSE now() END,
      p_now,
      now()
    FROM tmp_categoria_anomalia_resultados
    ON CONFLICT (equipe_id, nivel, key_tipo, categoria_key, subcategoria_key, data_referencia, hora_corte) DO UPDATE SET
      execucao_id = EXCLUDED.execucao_id,
      categoria_nome = EXCLUDED.categoria_nome,
      subcategoria_nome = EXCLUDED.subcategoria_nome,
      janela_inicio = EXCLUDED.janela_inicio,
      janela_fim = EXCLUDED.janela_fim,
      observado_acumulado = EXCLUDED.observado_acumulado,
      observado_ultima_hora = EXCLUDED.observado_ultima_hora,
      baseline_media_acumulada = EXCLUDED.baseline_media_acumulada,
      baseline_stddev_acumulado = EXCLUDED.baseline_stddev_acumulado,
      baseline_p75_acumulada = EXCLUDED.baseline_p75_acumulada,
      baseline_p95_acumulada = EXCLUDED.baseline_p95_acumulada,
      baseline_maximo_acumulado = EXCLUDED.baseline_maximo_acumulado,
      baseline_media_ultima_hora = EXCLUDED.baseline_media_ultima_hora,
      baseline_stddev_ultima_hora = EXCLUDED.baseline_stddev_ultima_hora,
      baseline_p75_ultima_hora = EXCLUDED.baseline_p75_ultima_hora,
      baseline_p95_ultima_hora = EXCLUDED.baseline_p95_ultima_hora,
      baseline_maximo_ultima_hora = EXCLUDED.baseline_maximo_ultima_hora,
      dias_amostra = EXCLUDED.dias_amostra,
      z_score_acumulado = EXCLUDED.z_score_acumulado,
      z_score_ultima_hora = EXCLUDED.z_score_ultima_hora,
      percentual_acima_acumulado = EXCLUDED.percentual_acima_acumulado,
      percentual_acima_ultima_hora = EXCLUDED.percentual_acima_ultima_hora,
      status = EXCLUDED.status,
      motivos = EXCLUDED.motivos,
      ativo = EXCLUDED.ativo,
      normalizado_em = EXCLUDED.normalizado_em,
      analisado_em = EXCLUDED.analisado_em,
      updated_at = now();

    UPDATE public.categoria_anomalia_execucoes e
    SET finished_at = clock_timestamp(),
        status = 'concluida',
        total_itens = COALESCE(r.total_itens, 0),
        total_alertas = COALESCE(r.total_alertas, 0),
        total_baseline_insuficiente = COALESCE(r.total_baseline_insuficiente, 0),
        updated_at = now()
    FROM (
      SELECT
        ex.execucao_id,
        COUNT(res.*)::int AS total_itens,
        COUNT(res.*) FILTER (WHERE res.ativo = true)::int AS total_alertas,
        COUNT(res.*) FILTER (WHERE res.status = 'baseline_insuficiente')::int AS total_baseline_insuficiente
      FROM tmp_categoria_anomalia_execucoes ex
      LEFT JOIN tmp_categoria_anomalia_resultados res ON res.execucao_id = ex.execucao_id
      GROUP BY ex.execucao_id
    ) r
    WHERE e.id = r.execucao_id;
  END IF;

  SELECT COUNT(*) INTO v_total_equipes FROM tmp_categoria_anomalia_target_equipes;
  SELECT COUNT(*) INTO v_total_itens FROM tmp_categoria_anomalia_resultados;
  SELECT COUNT(*) INTO v_total_alertas FROM tmp_categoria_anomalia_resultados WHERE ativo = true;
  SELECT COUNT(*) INTO v_total_baseline_insuficiente FROM tmp_categoria_anomalia_resultados WHERE status = 'baseline_insuficiente';

  SELECT COALESCE(jsonb_agg(to_jsonb(a)), '[]'::jsonb)
  INTO v_alertas
  FROM (
    SELECT
      equipe_id,
      nivel,
      key_tipo,
      categoria_key,
      NULLIF(subcategoria_key, '') AS subcategoria_key,
      categoria_nome,
      subcategoria_nome,
      observado_acumulado,
      observado_ultima_hora,
      media_acumulada AS baseline_media_acumulada,
      media_ultima_hora AS baseline_media_ultima_hora,
      z_score_acumulado,
      z_score_ultima_hora,
      percentual_acima_acumulado,
      percentual_acima_ultima_hora,
      dias_amostra,
      status,
      motivos
    FROM tmp_categoria_anomalia_resultados
    WHERE ativo = true
    ORDER BY CASE status WHEN 'critico' THEN 3 WHEN 'alerta' THEN 2 WHEN 'aviso' THEN 1 ELSE 0 END DESC,
             COALESCE(z_score_acumulado, z_score_ultima_hora, 0) DESC,
             observado_acumulado DESC
    LIMIT 50
  ) a;

  RETURN jsonb_build_object(
    'sucesso', true,
    'dry_run', p_dry_run,
    'data_referencia', v_data_referencia,
    'hora_corte', v_hora_corte,
    'janela_inicio', v_data_referencia::timestamp,
    'janela_fim', v_janela_fim,
    'equipes_analisadas', v_total_equipes,
    'total_itens', v_total_itens,
    'total_alertas', v_total_alertas,
    'total_baseline_insuficiente', v_total_baseline_insuficiente,
    'alertas', v_alertas
  );
EXCEPTION WHEN OTHERS THEN
  IF p_dry_run IS NOT TRUE THEN
    UPDATE public.categoria_anomalia_execucoes
    SET status = 'erro',
        erro = SQLERRM,
        finished_at = clock_timestamp(),
        updated_at = now()
    WHERE equipe_id IN (SELECT equipe_id FROM tmp_categoria_anomalia_target_equipes)
      AND data_referencia = v_data_referencia
      AND hora_corte = v_hora_corte;
  END IF;

  RAISE;
END;
$$;
COMMENT ON FUNCTION public.executar_analise_anomalias_categorias(timestamptz, uuid, boolean) IS
  'Executa a analise horaria de anomalias priorizando sinais operacionais: picos de volume sem pressao operacional viram apenas aviso historico.';
CREATE OR REPLACE FUNCTION public.sync_categoria_anomalia_notificacoes(
  p_alerta_id uuid
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_alerta public.categoria_anomalia_alertas%ROWTYPE;
  v_payload jsonb;
  v_total integer := 0;
  v_prev_status text;
  v_prev_analisado_em timestamptz;
  v_prev_rank integer := 0;
  v_current_rank integer := 0;
BEGIN
  SELECT *
  INTO v_alerta
  FROM public.categoria_anomalia_alertas
  WHERE id = p_alerta_id;

  IF NOT FOUND THEN
    RETURN 0;
  END IF;

  IF v_alerta.execucao_id IS NULL
     OR v_alerta.ativo IS DISTINCT FROM TRUE
     OR v_alerta.status NOT IN ('aviso', 'alerta', 'critico')
  THEN
    RETURN 0;
  END IF;

  IF v_alerta.status = 'aviso' THEN
    UPDATE public.categoria_anomalia_notificacoes
    SET status = v_alerta.status,
        observado_acumulado = v_alerta.observado_acumulado,
        observado_ultima_hora = v_alerta.observado_ultima_hora,
        payload = payload || jsonb_build_object('severidade', v_alerta.status),
        lida = true,
        lida_em = COALESCE(lida_em, now()),
        updated_at = now()
    WHERE alerta_id = v_alerta.id
      AND lida = false;

    GET DIAGNOSTICS v_total = ROW_COUNT;
    RETURN v_total;
  END IF;

  v_current_rank := CASE v_alerta.status
    WHEN 'critico' THEN 3
    WHEN 'alerta' THEN 2
    WHEN 'aviso' THEN 1
    ELSE 0
  END;

  SELECT
    a.status,
    a.analisado_em,
    CASE a.status
      WHEN 'critico' THEN 3
      WHEN 'alerta' THEN 2
      WHEN 'aviso' THEN 1
      ELSE 0
    END AS status_rank
  INTO v_prev_status, v_prev_analisado_em, v_prev_rank
  FROM public.categoria_anomalia_alertas a
  WHERE a.id <> v_alerta.id
    AND a.equipe_id = v_alerta.equipe_id
    AND a.nivel = v_alerta.nivel
    AND a.key_tipo = v_alerta.key_tipo
    AND a.categoria_key = v_alerta.categoria_key
    AND a.subcategoria_key = v_alerta.subcategoria_key
    AND a.status IN ('aviso', 'alerta', 'critico')
    AND a.analisado_em < v_alerta.analisado_em
  ORDER BY a.analisado_em DESC
  LIMIT 1;

  IF v_prev_status IS NOT NULL
     AND v_prev_analisado_em >= v_alerta.analisado_em - INTERVAL '6 hours'
     AND v_prev_rank >= v_current_rank
  THEN
    RETURN 0;
  END IF;

  v_payload := jsonb_build_object(
    'titulo',
      CASE
        WHEN v_alerta.nivel = 'subcategoria'
          THEN concat_ws(' > ', NULLIF(v_alerta.categoria_nome, ''), NULLIF(v_alerta.subcategoria_nome, ''))
        ELSE COALESCE(NULLIF(v_alerta.categoria_nome, ''), NULLIF(v_alerta.categoria_key, ''))
      END,
    'contexto', format(
      '%s ate %sh | %s acumulado | %s ultima hora',
      to_char(v_alerta.data_referencia, 'DD/MM/YYYY'),
      v_alerta.hora_corte,
      COALESCE(v_alerta.observado_acumulado, 0),
      COALESCE(v_alerta.observado_ultima_hora, 0)
    ),
    'nivel', v_alerta.nivel,
    'severidade', v_alerta.status,
    'categoria_nome', v_alerta.categoria_nome,
    'subcategoria_nome', v_alerta.subcategoria_nome,
    'data_referencia', v_alerta.data_referencia,
    'hora_corte', v_alerta.hora_corte
  );

  INSERT INTO public.categoria_anomalia_notificacoes (
    destinatario_id,
    equipe_id,
    execucao_id,
    alerta_id,
    nivel,
    key_tipo,
    categoria_key,
    subcategoria_key,
    categoria_nome,
    subcategoria_nome,
    data_referencia,
    hora_corte,
    status,
    observado_acumulado,
    observado_ultima_hora,
    payload,
    lida,
    lida_em,
    created_at,
    updated_at
  )
  SELECT
    destinatarios.user_id,
    v_alerta.equipe_id,
    v_alerta.execucao_id,
    v_alerta.id,
    v_alerta.nivel,
    v_alerta.key_tipo,
    v_alerta.categoria_key,
    v_alerta.subcategoria_key,
    v_alerta.categoria_nome,
    v_alerta.subcategoria_nome,
    v_alerta.data_referencia,
    v_alerta.hora_corte,
    v_alerta.status,
    v_alerta.observado_acumulado,
    v_alerta.observado_ultima_hora,
    v_payload,
    false,
    NULL,
    now(),
    now()
  FROM public.notificacoes_destinatarios('notificacoes.anomalia_categorias', v_alerta.equipe_id) AS destinatarios
  ON CONFLICT (destinatario_id, alerta_id) DO UPDATE SET
    execucao_id = EXCLUDED.execucao_id,
    equipe_id = EXCLUDED.equipe_id,
    nivel = EXCLUDED.nivel,
    key_tipo = EXCLUDED.key_tipo,
    categoria_key = EXCLUDED.categoria_key,
    subcategoria_key = EXCLUDED.subcategoria_key,
    categoria_nome = EXCLUDED.categoria_nome,
    subcategoria_nome = EXCLUDED.subcategoria_nome,
    data_referencia = EXCLUDED.data_referencia,
    hora_corte = EXCLUDED.hora_corte,
    status = EXCLUDED.status,
    observado_acumulado = EXCLUDED.observado_acumulado,
    observado_ultima_hora = EXCLUDED.observado_ultima_hora,
    payload = EXCLUDED.payload,
    lida = CASE
      WHEN public.categoria_anomalia_notificacoes.status IS DISTINCT FROM EXCLUDED.status THEN false
      ELSE public.categoria_anomalia_notificacoes.lida
    END,
    lida_em = CASE
      WHEN public.categoria_anomalia_notificacoes.status IS DISTINCT FROM EXCLUDED.status THEN NULL
      ELSE public.categoria_anomalia_notificacoes.lida_em
    END,
    updated_at = now();

  GET DIAGNOSTICS v_total = ROW_COUNT;
  RETURN v_total;
END;
$$;
COMMENT ON FUNCTION public.sync_categoria_anomalia_notificacoes(uuid) IS
  'Sincroniza notificacoes in-app apenas no primeiro disparo ativo ou em escalacao real de severidade para a mesma chave de anomalia.';

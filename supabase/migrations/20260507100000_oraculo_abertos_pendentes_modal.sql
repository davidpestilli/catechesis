-- Separa a listagem de tickets abertos da listagem de tickets ainda pendentes
-- no modal do grafico Abertos x Atendidos, mantendo alinhamento com filtro de equipe.

DROP FUNCTION IF EXISTS public.obter_filtros_pendentes_periodo(TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.obter_filtros_pendentes_periodo(TEXT, INTEGER, TEXT[]);
DROP FUNCTION IF EXISTS public.obter_contagem_tickets_pendentes_periodo(TEXT, INTEGER);
DROP FUNCTION IF EXISTS public.obter_contagem_tickets_pendentes_periodo(TEXT, INTEGER, TEXT[], TEXT, TEXT);
DROP FUNCTION IF EXISTS public.obter_contagem_tickets_pendentes_periodo(TEXT, INTEGER, TEXT[], TEXT, TEXT, TEXT[]);
DROP FUNCTION IF EXISTS public.obter_tickets_pendentes_periodo(TEXT, INTEGER, INTEGER, INTEGER);
DROP FUNCTION IF EXISTS public.obter_tickets_pendentes_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT);
DROP FUNCTION IF EXISTS public.obter_tickets_pendentes_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT, TEXT[]);
CREATE OR REPLACE FUNCTION public.obter_filtros_abertos_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL,
  p_equipes TEXT[] DEFAULT NULL
)
RETURNS TABLE(tipo TEXT, valor TEXT)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_today_local DATE := (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE;
BEGIN
  RETURN QUERY
  WITH base AS (
    SELECT
      COALESCE(c.status_operacional, 'Sem Status') AS status_operacional,
      c.grupo_designado,
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
  )
  SELECT 'status'::TEXT AS tipo, b.status_operacional AS valor
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
  GROUP BY b.status_operacional
  ORDER BY b.status_operacional;

  RETURN QUERY
  WITH base AS (
    SELECT
      c.grupo_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
  )
  SELECT 'gse'::TEXT AS tipo, b.grupo_designado AS valor
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND b.grupo_designado IS NOT NULL
    AND TRIM(b.grupo_designado) <> ''
  GROUP BY b.grupo_designado
  ORDER BY b.grupo_designado;

  RETURN QUERY
  WITH base AS (
    SELECT
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
  )
  SELECT 'usuario'::TEXT AS tipo, INITCAP(TRIM(b.nome_designado)) AS valor
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND b.nome_designado IS NOT NULL
    AND TRIM(b.nome_designado) <> ''
  GROUP BY INITCAP(TRIM(b.nome_designado))
  ORDER BY INITCAP(TRIM(b.nome_designado));

  RETURN QUERY
  SELECT 'usuario'::TEXT AS tipo, '(Sem usuário)'::TEXT AS valor
  WHERE EXISTS (
    SELECT 1
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = '')
      AND (
        p_equipes IS NULL
        OR array_length(p_equipes, 1) IS NULL
        OR CASE
          WHEN e.nome IS NOT NULL THEN e.nome::TEXT
          WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
          ELSE 'Outros'
        END = ANY(p_equipes)
      )
  );
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_contagem_tickets_abertos_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL,
  p_status TEXT[] DEFAULT NULL,
  p_gse TEXT DEFAULT NULL,
  p_usuario TEXT DEFAULT NULL,
  p_equipes TEXT[] DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_today_local DATE := (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE;
  v_total BIGINT;
BEGIN
  WITH base AS (
    SELECT
      COALESCE(c.status_operacional, 'Sem Status') AS status_operacional,
      c.grupo_designado,
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
  )
  SELECT COUNT(*)::BIGINT
  INTO v_total
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND (p_status IS NULL OR b.status_operacional = ANY(p_status))
    AND (p_gse IS NULL OR b.grupo_designado = p_gse)
    AND (
      p_usuario IS NULL
      OR (p_usuario IN ('(Sem usuario)', '(Sem usuário)') AND (b.nome_designado IS NULL OR TRIM(b.nome_designado) = ''))
      OR (p_usuario NOT IN ('(Sem usuario)', '(Sem usuário)') AND LOWER(TRIM(b.nome_designado)) = LOWER(TRIM(p_usuario)))
    );

  RETURN COALESCE(v_total, 0);
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_tickets_abertos_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0,
  p_status TEXT[] DEFAULT NULL,
  p_gse TEXT DEFAULT NULL,
  p_usuario TEXT DEFAULT NULL,
  p_equipes TEXT[] DEFAULT NULL
)
RETURNS TABLE(
  numero_chamado TEXT,
  data_abertura DATE,
  grupo_designado TEXT,
  descricao TEXT,
  status_operacional TEXT,
  nome_designado TEXT
)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_today_local DATE := (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE;
BEGIN
  RETURN QUERY
  WITH base AS (
    SELECT
      c.numero_chamado,
      c.data_abertura,
      c.grupo_designado,
      c.descricao,
      COALESCE(c.status_operacional, 'Sem Status') AS status_operacional,
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
  )
  SELECT
    b.numero_chamado,
    b.data_abertura::DATE,
    b.grupo_designado,
    LEFT(b.descricao, 200) AS descricao,
    b.status_operacional,
    CASE
      WHEN b.nome_designado IS NULL OR TRIM(b.nome_designado) = '' THEN NULL
      ELSE INITCAP(TRIM(b.nome_designado))
    END AS nome_designado
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND (p_status IS NULL OR b.status_operacional = ANY(p_status))
    AND (p_gse IS NULL OR b.grupo_designado = p_gse)
    AND (
      p_usuario IS NULL
      OR (p_usuario IN ('(Sem usuario)', '(Sem usuário)') AND (b.nome_designado IS NULL OR TRIM(b.nome_designado) = ''))
      OR (p_usuario NOT IN ('(Sem usuario)', '(Sem usuário)') AND LOWER(TRIM(b.nome_designado)) = LOWER(TRIM(p_usuario)))
    )
  ORDER BY b.data_abertura DESC, b.numero_chamado DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_filtros_pendentes_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL,
  p_equipes TEXT[] DEFAULT NULL
)
RETURNS TABLE(tipo TEXT, valor TEXT)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_today_local DATE := (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE;
BEGIN
  RETURN QUERY
  WITH base AS (
    SELECT
      COALESCE(c.status_operacional, 'Sem Status') AS status_operacional,
      c.grupo_designado,
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND COALESCE(c.status_operacional, 'Sem Status') NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
  )
  SELECT 'status'::TEXT AS tipo, b.status_operacional AS valor
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
  GROUP BY b.status_operacional
  ORDER BY b.status_operacional;

  RETURN QUERY
  WITH base AS (
    SELECT
      c.grupo_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND COALESCE(c.status_operacional, 'Sem Status') NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
  )
  SELECT 'gse'::TEXT AS tipo, b.grupo_designado AS valor
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND b.grupo_designado IS NOT NULL
    AND TRIM(b.grupo_designado) <> ''
  GROUP BY b.grupo_designado
  ORDER BY b.grupo_designado;

  RETURN QUERY
  WITH base AS (
    SELECT
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND COALESCE(c.status_operacional, 'Sem Status') NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
  )
  SELECT 'usuario'::TEXT AS tipo, INITCAP(TRIM(b.nome_designado)) AS valor
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND b.nome_designado IS NOT NULL
    AND TRIM(b.nome_designado) <> ''
  GROUP BY INITCAP(TRIM(b.nome_designado))
  ORDER BY INITCAP(TRIM(b.nome_designado));

  RETURN QUERY
  SELECT 'usuario'::TEXT AS tipo, '(Sem usuário)'::TEXT AS valor
  WHERE EXISTS (
    SELECT 1
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND COALESCE(c.status_operacional, 'Sem Status') NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
      AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = '')
      AND (
        p_equipes IS NULL
        OR array_length(p_equipes, 1) IS NULL
        OR CASE
          WHEN e.nome IS NOT NULL THEN e.nome::TEXT
          WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
          ELSE 'Outros'
        END = ANY(p_equipes)
      )
  );
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_contagem_tickets_pendentes_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL,
  p_status TEXT[] DEFAULT NULL,
  p_gse TEXT DEFAULT NULL,
  p_usuario TEXT DEFAULT NULL,
  p_equipes TEXT[] DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_today_local DATE := (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE;
  v_total BIGINT;
BEGIN
  WITH base AS (
    SELECT
      COALESCE(c.status_operacional, 'Sem Status') AS status_operacional,
      c.grupo_designado,
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND COALESCE(c.status_operacional, 'Sem Status') NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
  )
  SELECT COUNT(*)::BIGINT
  INTO v_total
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND (p_status IS NULL OR b.status_operacional = ANY(p_status))
    AND (p_gse IS NULL OR b.grupo_designado = p_gse)
    AND (
      p_usuario IS NULL
      OR (p_usuario IN ('(Sem usuario)', '(Sem usuário)') AND (b.nome_designado IS NULL OR TRIM(b.nome_designado) = ''))
      OR (p_usuario NOT IN ('(Sem usuario)', '(Sem usuário)') AND LOWER(TRIM(b.nome_designado)) = LOWER(TRIM(p_usuario)))
    );

  RETURN COALESCE(v_total, 0);
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_tickets_pendentes_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0,
  p_status TEXT[] DEFAULT NULL,
  p_gse TEXT DEFAULT NULL,
  p_usuario TEXT DEFAULT NULL,
  p_equipes TEXT[] DEFAULT NULL
)
RETURNS TABLE(
  numero_chamado TEXT,
  data_abertura DATE,
  grupo_designado TEXT,
  descricao TEXT,
  status_operacional TEXT,
  nome_designado TEXT
)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_today_local DATE := (NOW() AT TIME ZONE 'America/Sao_Paulo')::DATE;
BEGIN
  RETURN QUERY
  WITH base AS (
    SELECT
      c.numero_chamado,
      c.data_abertura,
      c.grupo_designado,
      c.descricao,
      COALESCE(c.status_operacional, 'Sem Status') AS status_operacional,
      c.nome_designado,
      CASE
        WHEN e.nome IS NOT NULL THEN e.nome::TEXT
        WHEN c.designado_localizacao = 'IT2B' THEN 'IT2B'
        ELSE 'Outros'
      END AS equipe_sgs
    FROM public.oraculo_chamados c
    LEFT JOIN public.gse_equipes ge ON c.grupo_designado = ge.gse
    LEFT JOIN public.equipes e ON ge.equipe_id = e.id
    WHERE
      (p_dias IS NULL OR c.data_abertura::DATE >= v_today_local - (GREATEST(p_dias, 1) - 1))
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND COALESCE(c.status_operacional, 'Sem Status') NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
  )
  SELECT
    b.numero_chamado,
    b.data_abertura::DATE,
    b.grupo_designado,
    LEFT(b.descricao, 200) AS descricao,
    b.status_operacional,
    CASE
      WHEN b.nome_designado IS NULL OR TRIM(b.nome_designado) = '' THEN NULL
      ELSE INITCAP(TRIM(b.nome_designado))
    END AS nome_designado
  FROM base b
  WHERE (p_equipes IS NULL OR array_length(p_equipes, 1) IS NULL OR b.equipe_sgs = ANY(p_equipes))
    AND (p_status IS NULL OR b.status_operacional = ANY(p_status))
    AND (p_gse IS NULL OR b.grupo_designado = p_gse)
    AND (
      p_usuario IS NULL
      OR (p_usuario IN ('(Sem usuario)', '(Sem usuário)') AND (b.nome_designado IS NULL OR TRIM(b.nome_designado) = ''))
      OR (p_usuario NOT IN ('(Sem usuario)', '(Sem usuário)') AND LOWER(TRIM(b.nome_designado)) = LOWER(TRIM(p_usuario)))
    )
  ORDER BY b.data_abertura DESC, b.numero_chamado DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$;
GRANT EXECUTE ON FUNCTION public.obter_filtros_abertos_periodo(TEXT, INTEGER, TEXT[]) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.obter_contagem_tickets_abertos_periodo(TEXT, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.obter_tickets_abertos_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.obter_filtros_pendentes_periodo(TEXT, INTEGER, TEXT[]) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.obter_contagem_tickets_pendentes_periodo(TEXT, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.obter_tickets_pendentes_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) TO authenticated, anon, service_role;
COMMENT ON FUNCTION public.obter_filtros_abertos_periodo(TEXT, INTEGER, TEXT[]) IS
  'Filtros disponiveis para tickets abertos no periodo do grafico Abertos x Atendidos, com filtro opcional de equipe SGS.';
COMMENT ON FUNCTION public.obter_tickets_abertos_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) IS
  'Lista paginada de todos os tickets abertos no periodo do grafico Abertos x Atendidos, com filtros e equipe SGS.';
COMMENT ON FUNCTION public.obter_contagem_tickets_abertos_periodo(TEXT, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) IS
  'Contagem de todos os tickets abertos no periodo do grafico Abertos x Atendidos, com filtros e equipe SGS.';
COMMENT ON FUNCTION public.obter_filtros_pendentes_periodo(TEXT, INTEGER, TEXT[]) IS
  'Filtros disponiveis para tickets do periodo que ainda nao estao em status atendido, com filtro opcional de equipe SGS.';
COMMENT ON FUNCTION public.obter_tickets_pendentes_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) IS
  'Lista paginada de tickets do periodo que ainda nao estao em status atendido, com filtros e equipe SGS.';
COMMENT ON FUNCTION public.obter_contagem_tickets_pendentes_periodo(TEXT, INTEGER, TEXT[], TEXT, TEXT, TEXT[]) IS
  'Contagem de tickets do periodo que ainda nao estao em status atendido, com filtros e equipe SGS.';
NOTIFY pgrst, 'reload schema';

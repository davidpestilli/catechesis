-- Suporte ao filtro "(Sem usuario)" nos drill-downs do Oraculo.
-- Mantem as assinaturas existentes usadas pelo frontend.

CREATE OR REPLACE FUNCTION public.obter_filtros_pendentes_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL
)
RETURNS TABLE(tipo TEXT, valor TEXT)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT 'status'::TEXT AS tipo, c.status_operacional AS valor
  FROM public.oraculo_chamados c
  WHERE
    (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND CASE
      WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
      WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
      ELSE TO_CHAR(c.data_abertura, 'DD/MM')
    END = p_periodo
    AND c.status_operacional NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
  GROUP BY c.status_operacional
  ORDER BY c.status_operacional;

  RETURN QUERY
  SELECT 'gse'::TEXT AS tipo, c.grupo_designado AS valor
  FROM public.oraculo_chamados c
  WHERE
    (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND CASE
      WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
      WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
      ELSE TO_CHAR(c.data_abertura, 'DD/MM')
    END = p_periodo
    AND c.status_operacional NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
    AND c.grupo_designado IS NOT NULL
    AND TRIM(c.grupo_designado) <> ''
  GROUP BY c.grupo_designado
  ORDER BY c.grupo_designado;

  RETURN QUERY
  SELECT 'usuario'::TEXT AS tipo, INITCAP(TRIM(c.nome_designado)) AS valor
  FROM public.oraculo_chamados c
  WHERE
    (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND CASE
      WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
      WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
      ELSE TO_CHAR(c.data_abertura, 'DD/MM')
    END = p_periodo
    AND c.status_operacional NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
    AND c.nome_designado IS NOT NULL
    AND TRIM(c.nome_designado) <> ''
  GROUP BY INITCAP(TRIM(c.nome_designado))
  ORDER BY INITCAP(TRIM(c.nome_designado));

  RETURN QUERY
  SELECT 'usuario'::TEXT AS tipo, '(Sem usuário)'::TEXT AS valor
  WHERE EXISTS (
    SELECT 1
    FROM public.oraculo_chamados c
    WHERE
      (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
      AND CASE
        WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
        WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
        ELSE TO_CHAR(c.data_abertura, 'DD/MM')
      END = p_periodo
      AND c.status_operacional NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
      AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = '')
  );
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_contagem_tickets_pendentes_periodo(
  p_periodo TEXT,
  p_dias INTEGER DEFAULT NULL,
  p_status TEXT[] DEFAULT NULL,
  p_gse TEXT DEFAULT NULL,
  p_usuario TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_total BIGINT;
BEGIN
  SELECT COUNT(*)::BIGINT
  INTO v_total
  FROM public.oraculo_chamados c
  WHERE
    (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND CASE
      WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
      WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
      ELSE TO_CHAR(c.data_abertura, 'DD/MM')
    END = p_periodo
    AND c.status_operacional NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
    AND (p_status IS NULL OR c.status_operacional = ANY(p_status))
    AND (p_gse IS NULL OR c.grupo_designado = p_gse)
    AND (
      p_usuario IS NULL
      OR (p_usuario = '(Sem usuário)' AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = ''))
      OR (p_usuario <> '(Sem usuário)' AND LOWER(TRIM(c.nome_designado)) = LOWER(TRIM(p_usuario)))
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
  p_usuario TEXT DEFAULT NULL
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
BEGIN
  RETURN QUERY
  SELECT
    c.numero_chamado,
    c.data_abertura,
    c.grupo_designado,
    LEFT(c.descricao, 200) AS descricao,
    c.status_operacional,
    CASE
      WHEN c.nome_designado IS NULL OR TRIM(c.nome_designado) = '' THEN NULL
      ELSE INITCAP(TRIM(c.nome_designado))
    END AS nome_designado
  FROM public.oraculo_chamados c
  WHERE
    (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND CASE
      WHEN p_dias IS NULL OR p_dias > 90 THEN TO_CHAR(c.data_abertura, 'Mon/YY')
      WHEN p_dias > 30 THEN TO_CHAR(c.data_abertura, 'DD/Mon')
      ELSE TO_CHAR(c.data_abertura, 'DD/MM')
    END = p_periodo
    AND c.status_operacional NOT IN ('Fechado', 'Aguardando Aceite Definitivo')
    AND (p_status IS NULL OR c.status_operacional = ANY(p_status))
    AND (p_gse IS NULL OR c.grupo_designado = p_gse)
    AND (
      p_usuario IS NULL
      OR (p_usuario = '(Sem usuário)' AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = ''))
      OR (p_usuario <> '(Sem usuário)' AND LOWER(TRIM(c.nome_designado)) = LOWER(TRIM(p_usuario)))
    )
  ORDER BY c.data_abertura DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_filtros_rejeite_equipe_sgs(
  p_equipe TEXT,
  p_grupo_designado TEXT DEFAULT NULL,
  p_dias INTEGER DEFAULT NULL
)
RETURNS TABLE(tipo TEXT, valor TEXT)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT 'status'::TEXT AS tipo, c.status_operacional AS valor
  FROM public.oraculo_chamados c
  WHERE c.designado_localizacao = p_equipe
    AND c.qtd_rejeite > 0
    AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado)
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
  GROUP BY c.status_operacional
  ORDER BY c.status_operacional;

  RETURN QUERY
  SELECT 'gse'::TEXT AS tipo, c.grupo_designado AS valor
  FROM public.oraculo_chamados c
  WHERE c.designado_localizacao = p_equipe
    AND c.qtd_rejeite > 0
    AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado)
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND c.grupo_designado IS NOT NULL
    AND TRIM(c.grupo_designado) <> ''
  GROUP BY c.grupo_designado
  ORDER BY c.grupo_designado;

  RETURN QUERY
  SELECT 'usuario'::TEXT AS tipo, INITCAP(TRIM(c.nome_designado)) AS valor
  FROM public.oraculo_chamados c
  WHERE c.designado_localizacao = p_equipe
    AND c.qtd_rejeite > 0
    AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado)
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND c.nome_designado IS NOT NULL
    AND TRIM(c.nome_designado) <> ''
  GROUP BY INITCAP(TRIM(c.nome_designado))
  ORDER BY INITCAP(TRIM(c.nome_designado));

  RETURN QUERY
  SELECT 'usuario'::TEXT AS tipo, '(Sem usuário)'::TEXT AS valor
  WHERE EXISTS (
    SELECT 1
    FROM public.oraculo_chamados c
    WHERE c.designado_localizacao = p_equipe
      AND c.qtd_rejeite > 0
      AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado)
      AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
      AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = '')
  );
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_contagem_tickets_rejeite_por_equipe_sgs(
  p_equipe TEXT,
  p_grupo_designado TEXT DEFAULT NULL,
  p_dias INTEGER DEFAULT NULL,
  p_status_operacional TEXT[] DEFAULT NULL,
  p_nome_designado TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_total BIGINT;
BEGIN
  SELECT COUNT(*)::BIGINT
  INTO v_total
  FROM public.oraculo_chamados c
  WHERE
    c.designado_localizacao = p_equipe
    AND c.qtd_rejeite > 0
    AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado)
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND (p_status_operacional IS NULL OR c.status_operacional = ANY(p_status_operacional))
    AND (
      p_nome_designado IS NULL
      OR (p_nome_designado = '(Sem usuário)' AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = ''))
      OR (p_nome_designado <> '(Sem usuário)' AND LOWER(TRIM(c.nome_designado)) = LOWER(TRIM(p_nome_designado)))
    );

  RETURN COALESCE(v_total, 0);
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_tickets_rejeite_por_equipe_sgs(
  p_equipe TEXT,
  p_grupo_designado TEXT DEFAULT NULL,
  p_dias INTEGER DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0,
  p_ordenacao TEXT DEFAULT 'desc',
  p_status_operacional TEXT[] DEFAULT NULL,
  p_nome_designado TEXT DEFAULT NULL
)
RETURNS TABLE(
  numero_chamado TEXT,
  data_abertura DATE,
  grupo_designado TEXT,
  descricao TEXT,
  qtd_rejeite INTEGER,
  status_operacional TEXT,
  nome_designado TEXT
)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    c.numero_chamado,
    c.data_abertura,
    c.grupo_designado,
    LEFT(c.descricao, 200) AS descricao,
    c.qtd_rejeite::INT,
    c.status_operacional,
    CASE
      WHEN c.nome_designado IS NULL OR TRIM(c.nome_designado) = '' THEN NULL
      ELSE INITCAP(TRIM(c.nome_designado))
    END AS nome_designado
  FROM public.oraculo_chamados c
  WHERE
    c.designado_localizacao = p_equipe
    AND c.qtd_rejeite > 0
    AND (p_grupo_designado IS NULL OR c.grupo_designado = p_grupo_designado)
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND (p_status_operacional IS NULL OR c.status_operacional = ANY(p_status_operacional))
    AND (
      p_nome_designado IS NULL
      OR (p_nome_designado = '(Sem usuário)' AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = ''))
      OR (p_nome_designado <> '(Sem usuário)' AND LOWER(TRIM(c.nome_designado)) = LOWER(TRIM(p_nome_designado)))
    )
  ORDER BY
    CASE WHEN p_ordenacao = 'desc' THEN c.qtd_rejeite END DESC,
    CASE WHEN p_ordenacao = 'asc' THEN c.qtd_rejeite END ASC,
    c.data_abertura DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_tickets_gse_sem_solucao(
  p_grupo TEXT,
  p_dias INT DEFAULT NULL,
  p_status TEXT[] DEFAULT NULL,
  p_gse TEXT DEFAULT NULL,
  p_nome_designado TEXT DEFAULT NULL,
  p_modo TEXT DEFAULT NULL,
  p_ord TEXT DEFAULT 'desc',
  p_limit INT DEFAULT 100,
  p_offset INT DEFAULT 0
)
RETURNS TABLE(
  numero_chamado TEXT,
  data_abertura TEXT,
  grupo_designado TEXT,
  nome_designado TEXT,
  status_operacional TEXT,
  atendido_externo BOOLEAN
)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    c.numero_chamado::TEXT,
    TO_CHAR(c.data_abertura::DATE, 'YYYY-MM-DD') AS data_abertura,
    c.grupo_designado,
    NULLIF(TRIM(c.nome_designado), '') AS nome_designado,
    COALESCE(c.status_operacional, 'Sem Status') AS status_operacional,
    COALESCE(c.atendido_externo, FALSE) AS atendido_externo
  FROM public.oraculo_chamados c
  WHERE
    c.grupo_designado = p_grupo
    AND (c.solucao IS NULL OR TRIM(c.solucao) = '' OR TRIM(c.solucao) = '-')
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND (p_status IS NULL OR COALESCE(c.status_operacional, 'Sem Status') = ANY(p_status))
    AND (p_gse IS NULL OR c.grupo_designado = p_gse)
    AND (
      (p_modo = 'externo' AND COALESCE(c.atendido_externo, FALSE) = TRUE)
      OR (p_modo = 'vazio' AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = ''))
      OR (p_modo IS NULL AND (p_nome_designado IS NULL OR c.nome_designado = p_nome_designado))
    )
  ORDER BY
    CASE WHEN LOWER(p_ord) = 'asc' THEN c.data_abertura END ASC,
    CASE WHEN LOWER(p_ord) <> 'asc' THEN c.data_abertura END DESC,
    c.numero_chamado DESC
  LIMIT p_limit
  OFFSET p_offset;
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_contagem_tickets_gse_sem_solucao(
  p_grupo TEXT,
  p_dias INT DEFAULT NULL,
  p_status TEXT[] DEFAULT NULL,
  p_gse TEXT DEFAULT NULL,
  p_nome_designado TEXT DEFAULT NULL,
  p_modo TEXT DEFAULT NULL
)
RETURNS BIGINT
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_total BIGINT;
BEGIN
  SELECT COUNT(*)::BIGINT
  INTO v_total
  FROM public.oraculo_chamados c
  WHERE
    c.grupo_designado = p_grupo
    AND (c.solucao IS NULL OR TRIM(c.solucao) = '' OR TRIM(c.solucao) = '-')
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND (p_status IS NULL OR COALESCE(c.status_operacional, 'Sem Status') = ANY(p_status))
    AND (p_gse IS NULL OR c.grupo_designado = p_gse)
    AND (
      (p_modo = 'externo' AND COALESCE(c.atendido_externo, FALSE) = TRUE)
      OR (p_modo = 'vazio' AND (c.nome_designado IS NULL OR TRIM(c.nome_designado) = ''))
      OR (p_modo IS NULL AND (p_nome_designado IS NULL OR c.nome_designado = p_nome_designado))
    );

  RETURN COALESCE(v_total, 0);
END;
$function$;
CREATE OR REPLACE FUNCTION public.obter_filtros_tickets_gse_sem_solucao(
  p_grupo TEXT,
  p_dias INT DEFAULT NULL
)
RETURNS TABLE(tipo TEXT, valor TEXT)
LANGUAGE plpgsql
STABLE
AS $function$
BEGIN
  RETURN QUERY
  SELECT 'status'::TEXT AS tipo, COALESCE(c.status_operacional, 'Sem Status')::TEXT AS valor
  FROM public.oraculo_chamados c
  WHERE
    c.grupo_designado = p_grupo
    AND (c.solucao IS NULL OR TRIM(c.solucao) = '' OR TRIM(c.solucao) = '-')
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
  GROUP BY COALESCE(c.status_operacional, 'Sem Status')
  ORDER BY COALESCE(c.status_operacional, 'Sem Status');

  RETURN QUERY
  SELECT 'gse'::TEXT AS tipo, p_grupo::TEXT AS valor;

  RETURN QUERY
  SELECT 'usuario'::TEXT AS tipo, TRIM(c.nome_designado)::TEXT AS valor
  FROM public.oraculo_chamados c
  WHERE
    c.grupo_designado = p_grupo
    AND (c.solucao IS NULL OR TRIM(c.solucao) = '' OR TRIM(c.solucao) = '-')
    AND (p_dias IS NULL OR c.data_abertura >= CURRENT_DATE - (p_dias || ' days')::INTERVAL)
    AND c.nome_designado IS NOT NULL
    AND TRIM(c.nome_designado) <> ''
  GROUP BY TRIM(c.nome_designado)
  ORDER BY TRIM(c.nome_designado);
END;
$function$;
GRANT EXECUTE ON FUNCTION public.obter_filtros_pendentes_periodo(TEXT, INTEGER) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_contagem_tickets_pendentes_periodo(TEXT, INTEGER, TEXT[], TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_tickets_pendentes_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_filtros_rejeite_equipe_sgs(TEXT, TEXT, INTEGER) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_contagem_tickets_rejeite_por_equipe_sgs(TEXT, TEXT, INTEGER, TEXT[], TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_tickets_rejeite_por_equipe_sgs(TEXT, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT[], TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_tickets_gse_sem_solucao(TEXT, INT, TEXT[], TEXT, TEXT, TEXT, TEXT, INT, INT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_contagem_tickets_gse_sem_solucao(TEXT, INT, TEXT[], TEXT, TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_filtros_tickets_gse_sem_solucao(TEXT, INT) TO authenticated, anon;

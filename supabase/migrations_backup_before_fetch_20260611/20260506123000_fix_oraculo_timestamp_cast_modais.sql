-- Corrige regressao introduzida ao regravar RPCs dos modais do Oraculo:
-- oraculo_chamados.data_abertura e TIMESTAMP, mas essas funcoes mantem
-- contrato RETURNS TABLE(... data_abertura DATE ...).
-- Sem cast explicito, PostgreSQL retorna 42804.

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
    c.data_abertura::DATE,
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
    c.data_abertura::DATE,
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
GRANT EXECUTE ON FUNCTION public.obter_tickets_pendentes_periodo(TEXT, INTEGER, INTEGER, INTEGER, TEXT[], TEXT, TEXT) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.obter_tickets_rejeite_por_equipe_sgs(TEXT, TEXT, INTEGER, INTEGER, INTEGER, TEXT, TEXT[], TEXT) TO authenticated, anon;

CREATE INDEX IF NOT EXISTS idx_chamados_equipe_numero
ON public.chamados (equipe_id, numero);
CREATE INDEX IF NOT EXISTS idx_chamados_equipe_ordenacao
ON public.chamados (equipe_id, COALESCE(data_abertura, created_at) DESC);
CREATE OR REPLACE FUNCTION public.buscar_chamados_registrados_paginado(
  p_equipe_id uuid,
  p_limit integer DEFAULT 30,
  p_offset integer DEFAULT 0,
  p_status text DEFAULT 'todos',
  p_numero text DEFAULT NULL,
  p_solicitante text DEFAULT NULL,
  p_atendente text DEFAULT NULL,
  p_especifico text DEFAULT NULL,
  p_data_inicio date DEFAULT NULL,
  p_data_fim date DEFAULT NULL,
  p_tags text DEFAULT NULL,
  p_funcionalidade text DEFAULT NULL,
  p_busca text DEFAULT NULL,
  p_ordenacao text DEFAULT 'recentes'
)
RETURNS TABLE(
  id uuid,
  numero text,
  data_abertura timestamp with time zone,
  solicitante text,
  especifico text,
  atendente text,
  funcionalidade text,
  tags text[],
  status text,
  situacao text,
  data_encerramento date,
  created_at timestamp with time zone,
  satisfacao text,
  data_solicitacao_info timestamp with time zone,
  data_inicio_pausa timestamp with time zone,
  horas_pausadas integer,
  motivo_pausa text,
  chamadas_telefonicas integer,
  telefone_contato text,
  observacoes text,
  total_count bigint
)
LANGUAGE sql
STABLE
AS $function$
  WITH filtrados AS (
    SELECT c.*
    FROM public.chamados c
    WHERE c.equipe_id = p_equipe_id
      AND (p_numero IS NULL OR c.numero ILIKE '%' || p_numero || '%')
      AND (p_solicitante IS NULL OR c.solicitante ILIKE '%' || p_solicitante || '%')
      AND (p_atendente IS NULL OR c.atendente ILIKE '%' || p_atendente || '%')
      AND (p_especifico IS NULL OR c.especifico ILIKE '%' || p_especifico || '%')
      AND (p_funcionalidade IS NULL OR c.funcionalidade ILIKE '%' || p_funcionalidade || '%')
      AND (p_data_inicio IS NULL OR c.data_abertura::date >= p_data_inicio)
      AND (p_data_fim IS NULL OR c.data_abertura::date <= p_data_fim)
      AND (
        p_tags IS NULL
        OR EXISTS (
          SELECT 1
          FROM unnest(COALESCE(c.tags, ARRAY[]::text[])) tag
          WHERE tag ILIKE '%' || p_tags || '%'
        )
      )
      AND (
        p_busca IS NULL
        OR (
          c.numero ILIKE '%' || p_busca || '%'
          OR (
            p_busca !~ '^[0-9]+$'
            AND (
              c.texto_chamado ILIKE '%' || p_busca || '%'
              OR c.texto_resposta ILIKE '%' || p_busca || '%'
            )
          )
        )
      )
      AND (
        COALESCE(p_status, 'todos') = 'todos'
        OR (
          p_status = 'verde'
          AND c.situacao = 'Encerrado'
        )
        OR (
          p_status = 'pausa'
          AND (
            c.atendente IS NULL
            OR BTRIM(c.atendente) = ''
            OR c.situacao IN ('Suspenso', 'Informação Solicitada')
            OR c.data_inicio_pausa IS NOT NULL
          )
        )
        OR (
          p_status = 'amarelo_etapa1'
          AND c.created_at IS NOT NULL
          AND c.situacao IS DISTINCT FROM 'Encerrado'
          AND NOT (
            c.atendente IS NULL
            OR BTRIM(c.atendente) = ''
            OR c.situacao IN ('Suspenso', 'Informação Solicitada')
            OR c.data_inicio_pausa IS NOT NULL
          )
          AND c.created_at >= NOW() - INTERVAL '48 hours'
        )
        OR (
          p_status = 'amarelo_etapa2'
          AND c.created_at IS NOT NULL
          AND c.situacao IS DISTINCT FROM 'Encerrado'
          AND NOT (
            c.atendente IS NULL
            OR BTRIM(c.atendente) = ''
            OR c.situacao IN ('Suspenso', 'Informação Solicitada')
            OR c.data_inicio_pausa IS NOT NULL
          )
          AND c.created_at < NOW() - INTERVAL '48 hours'
          AND c.created_at >= NOW() - INTERVAL '96 hours'
        )
        OR (
          p_status = 'amarelo_etapa3'
          AND c.created_at IS NOT NULL
          AND c.situacao IS DISTINCT FROM 'Encerrado'
          AND NOT (
            c.atendente IS NULL
            OR BTRIM(c.atendente) = ''
            OR c.situacao IN ('Suspenso', 'Informação Solicitada')
            OR c.data_inicio_pausa IS NOT NULL
          )
          AND c.created_at < NOW() - INTERVAL '96 hours'
          AND c.created_at >= NOW() - INTERVAL '120 hours'
        )
        OR (
          p_status = 'vermelho'
          AND c.created_at IS NOT NULL
          AND c.situacao IS DISTINCT FROM 'Encerrado'
          AND NOT (
            c.atendente IS NULL
            OR BTRIM(c.atendente) = ''
            OR c.situacao IN ('Suspenso', 'Informação Solicitada')
            OR c.data_inicio_pausa IS NOT NULL
          )
          AND c.created_at < NOW() - INTERVAL '120 hours'
        )
      )
  ),
  contados AS (
    SELECT
      f.*,
      COUNT(*) OVER() AS total_count
    FROM filtrados f
  )
  SELECT
    c.id,
    c.numero,
    c.data_abertura,
    c.solicitante,
    c.especifico,
    c.atendente,
    c.funcionalidade,
    c.tags,
    c.status,
    c.situacao,
    c.data_encerramento,
    c.created_at,
    c.satisfacao,
    c.data_solicitacao_info,
    c.data_inicio_pausa,
    c.horas_pausadas,
    c.motivo_pausa,
    c.chamadas_telefonicas,
    c.telefone_contato,
    c.observacoes,
    c.total_count
  FROM contados c
  ORDER BY
    CASE WHEN COALESCE(p_ordenacao, 'recentes') = 'antigos' THEN COALESCE(c.data_abertura, c.created_at) END ASC,
    CASE WHEN COALESCE(p_ordenacao, 'recentes') <> 'antigos' THEN COALESCE(c.data_abertura, c.created_at) END DESC,
    c.id DESC
  LIMIT GREATEST(COALESCE(p_limit, 30), 1)
  OFFSET GREATEST(COALESCE(p_offset, 0), 0);
$function$;
GRANT EXECUTE ON FUNCTION public.buscar_chamados_registrados_paginado(
  uuid,
  integer,
  integer,
  text,
  text,
  text,
  text,
  text,
  date,
  date,
  text,
  text,
  text,
  text
) TO authenticated;
COMMENT ON FUNCTION public.buscar_chamados_registrados_paginado(
  uuid,
  integer,
  integer,
  text,
  text,
  text,
  text,
  text,
  date,
  date,
  text,
  text,
  text,
  text
) IS 'Busca paginada de chamados registrados com filtros server-side para evitar carregar toda a tabela no frontend.';

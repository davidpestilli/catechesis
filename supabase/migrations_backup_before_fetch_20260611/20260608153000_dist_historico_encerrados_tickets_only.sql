-- Usa apenas public.tickets para os encerrados do Distribuidor.
-- Evita dependência do Oráculo e cria índice dedicado por email/status finalizado.

CREATE INDEX IF NOT EXISTS idx_tickets_email_finalizado
  ON public.tickets USING btree (lower(btrim(email)), finished_at DESC)
  WHERE status = 'finalizado'::text AND email IS NOT NULL;
CREATE OR REPLACE FUNCTION public.dist_contar_tickets_encerrados_por_email(p_emails text[])
RETURNS TABLE(email text, total bigint)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $function$
  WITH emails_normalizados AS (
    SELECT DISTINCT lower(btrim(item)) AS email
    FROM unnest(COALESCE(p_emails, ARRAY[]::text[])) AS item
    WHERE item IS NOT NULL
      AND btrim(item) <> ''
  )
  SELECT
    e.email,
    COUNT(t.id)::bigint AS total
  FROM emails_normalizados e
  LEFT JOIN public.tickets t
    ON lower(btrim(t.email)) = e.email
   AND t.status = 'finalizado'
  GROUP BY e.email
  ORDER BY e.email;
$function$;
GRANT EXECUTE ON FUNCTION public.dist_contar_tickets_encerrados_por_email(text[]) TO authenticated;
COMMENT ON FUNCTION public.dist_contar_tickets_encerrados_por_email(text[]) IS
  'Conta tickets encerrados por email usando exclusivamente a tabela public.tickets.';
CREATE OR REPLACE FUNCTION public.dist_buscar_tickets_encerrados_solicitante(
  p_email text,
  p_excluir_chamado text DEFAULT NULL::text,
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $function$
DECLARE
  v_email text := lower(btrim(COALESCE(p_email, '')));
  v_limit integer := GREATEST(COALESCE(p_limit, 20), 1);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_total integer := 0;
  v_ultimo_numero text;
  v_ultimo_data timestamptz;
  v_chamados jsonb := '[]'::jsonb;
BEGIN
  IF v_email = '' THEN
    RETURN jsonb_build_object(
      'email', '',
      'total', 0,
      'ultimo_chamado', NULL,
      'ultimo_data', NULL,
      'chamados', '[]'::jsonb,
      'has_more', false
    );
  END IF;

  SELECT COUNT(*)
    INTO v_total
  FROM public.tickets
  WHERE lower(btrim(email)) = v_email
    AND status = 'finalizado'
    AND (p_excluir_chamado IS NULL OR numero_chamado <> p_excluir_chamado);

  SELECT
    numero_chamado,
    COALESCE(finished_at, created_at)
    INTO v_ultimo_numero, v_ultimo_data
  FROM public.tickets
  WHERE lower(btrim(email)) = v_email
    AND status = 'finalizado'
    AND (p_excluir_chamado IS NULL OR numero_chamado <> p_excluir_chamado)
  ORDER BY COALESCE(finished_at, created_at) DESC, created_at DESC
  LIMIT 1;

  SELECT COALESCE(jsonb_agg(row_to_json(c)), '[]'::jsonb)
    INTO v_chamados
  FROM (
    SELECT
      numero_chamado,
      descricao,
      COALESCE(finished_at, created_at)::text AS data
    FROM public.tickets
    WHERE lower(btrim(email)) = v_email
      AND status = 'finalizado'
      AND (p_excluir_chamado IS NULL OR numero_chamado <> p_excluir_chamado)
    ORDER BY COALESCE(finished_at, created_at) DESC, created_at DESC
    LIMIT v_limit OFFSET v_offset
  ) c;

  RETURN jsonb_build_object(
    'email', v_email,
    'total', COALESCE(v_total, 0),
    'ultimo_chamado', v_ultimo_numero,
    'ultimo_data', v_ultimo_data,
    'chamados', v_chamados,
    'has_more', (COALESCE(v_total, 0) > (v_limit + v_offset))
  );
END;
$function$;
GRANT EXECUTE ON FUNCTION public.dist_buscar_tickets_encerrados_solicitante(text, text, integer, integer) TO authenticated;
COMMENT ON FUNCTION public.dist_buscar_tickets_encerrados_solicitante(text, text, integer, integer) IS
  'Busca tickets encerrados de um solicitante usando exclusivamente a tabela public.tickets.';

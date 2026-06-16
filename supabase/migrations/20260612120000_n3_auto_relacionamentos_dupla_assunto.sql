BEGIN;
ALTER TABLE public.escalacoes_n3_vinculos
  ADD COLUMN IF NOT EXISTS origem text NOT NULL DEFAULT 'manual';
ALTER TABLE public.escalacoes_n3_vinculos
  ADD COLUMN IF NOT EXISTS assinatura_assunto_par text;
ALTER TABLE public.escalacoes_n3_vinculos
  ADD COLUMN IF NOT EXISTS equipe_contexto_id uuid;
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM pg_constraint
    WHERE conname = 'chk_escalacoes_n3_vinculos_origem'
      AND conrelid = 'public.escalacoes_n3_vinculos'::regclass
  ) THEN
    ALTER TABLE public.escalacoes_n3_vinculos
      ADD CONSTRAINT chk_escalacoes_n3_vinculos_origem
      CHECK (origem IN ('manual', 'assunto_par'));
  END IF;
END $$;
CREATE INDEX IF NOT EXISTS idx_escalacoes_n3_vinculos_origem_assinatura
  ON public.escalacoes_n3_vinculos(origem, equipe_contexto_id, assinatura_assunto_par);
COMMENT ON COLUMN public.escalacoes_n3_vinculos.origem IS
  'Origem do vínculo: manual ou gerado automaticamente pela dupla ordenada dos dois primeiros assuntos.';
COMMENT ON COLUMN public.escalacoes_n3_vinculos.assinatura_assunto_par IS
  'Assinatura normalizada no formato assunto1::assunto2 usada pelos vínculos automáticos.';
COMMENT ON COLUMN public.escalacoes_n3_vinculos.equipe_contexto_id IS
  'Equipe usada para segmentar a reconstrução de vínculos automáticos por dupla de assuntos.';
CREATE OR REPLACE FUNCTION public.n3_assunto_dupla_assinatura(p_assunto text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path TO 'public'
AS $function$
  WITH partes AS (
    SELECT
      lower(regexp_replace(btrim(tag), '\s+', ' ', 'g')) AS normalized_tag,
      ord
    FROM regexp_split_to_table(coalesce(p_assunto, ''), ';') WITH ORDINALITY AS partes(tag, ord)
  ),
  deduplicadas AS (
    SELECT normalized_tag, min(ord) AS first_ord
    FROM partes
    WHERE normalized_tag <> ''
    GROUP BY normalized_tag
  ),
  primeiras_duas AS (
    SELECT normalized_tag, first_ord
    FROM deduplicadas
    ORDER BY first_ord
    LIMIT 2
  )
  SELECT CASE
    WHEN COUNT(*) = 2 THEN string_agg(normalized_tag, '::' ORDER BY first_ord)
    ELSE NULL
  END
  FROM primeiras_duas;
$function$;
CREATE OR REPLACE FUNCTION public.n3_rebuild_auto_vinculos_for_signature(
  p_equipe_id uuid,
  p_assinatura text,
  p_actor uuid DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_total integer := 0;
  v_total_ativos integer := 0;
  v_inseridos integer := 0;
  v_actor uuid := p_actor;
BEGIN
  IF p_equipe_id IS NULL OR NULLIF(BTRIM(p_assinatura), '') IS NULL THEN
    RETURN 0;
  END IF;

  DELETE FROM public.escalacoes_n3_vinculos
  WHERE origem = 'assunto_par'
    AND equipe_contexto_id = p_equipe_id
    AND assinatura_assunto_par = p_assinatura;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'ativo')
  INTO
    v_total,
    v_total_ativos
  FROM public.escalacoes_n3
  WHERE equipe_id = p_equipe_id
    AND public.n3_assunto_dupla_assinatura(assunto) = p_assinatura;

  IF v_total < 2 THEN
    RETURN 0;
  END IF;

  INSERT INTO public.escalacoes_n3_vinculos (
    escalacao_a_id,
    escalacao_b_id,
    criado_por,
    origem,
    assinatura_assunto_par,
    equipe_contexto_id
  )
  SELECT
    a.id,
    b.id,
    COALESCE(v_actor, a.criado_por, b.criado_por),
    'assunto_par',
    p_assinatura,
    p_equipe_id
  FROM public.escalacoes_n3 a
  JOIN public.escalacoes_n3 b
    ON a.id < b.id
   AND a.equipe_id = b.equipe_id
  WHERE a.equipe_id = p_equipe_id
    AND public.n3_assunto_dupla_assinatura(a.assunto) = p_assinatura
    AND public.n3_assunto_dupla_assinatura(b.assunto) = p_assinatura
    AND (
      v_total <= 10
      OR (a.status = 'ativo' AND b.status = 'ativo')
    )
  ON CONFLICT (escalacao_a_id, escalacao_b_id) DO NOTHING;

  GET DIAGNOSTICS v_inseridos = ROW_COUNT;
  RETURN v_inseridos;
END;
$function$;
CREATE OR REPLACE FUNCTION public.n3_rebuild_all_auto_vinculos(
  p_equipe_id uuid DEFAULT NULL,
  p_actor uuid DEFAULT NULL
)
RETURNS TABLE(
  equipe_id uuid,
  assinatura_assunto_par text,
  total_registros integer,
  total_ativos integer,
  vinculos_registrados integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_grupo record;
BEGIN
  DELETE FROM public.escalacoes_n3_vinculos
  WHERE origem = 'assunto_par'
    AND (p_equipe_id IS NULL OR equipe_contexto_id = p_equipe_id);

  FOR v_grupo IN
    SELECT
      e.equipe_id,
      public.n3_assunto_dupla_assinatura(e.assunto) AS assinatura_assunto_par,
      COUNT(*)::integer AS total_registros,
      COUNT(*) FILTER (WHERE e.status = 'ativo')::integer AS total_ativos
    FROM public.escalacoes_n3 e
    WHERE public.n3_assunto_dupla_assinatura(e.assunto) IS NOT NULL
      AND (p_equipe_id IS NULL OR e.equipe_id = p_equipe_id)
    GROUP BY
      e.equipe_id,
      public.n3_assunto_dupla_assinatura(e.assunto)
  LOOP
    equipe_id := v_grupo.equipe_id;
    assinatura_assunto_par := v_grupo.assinatura_assunto_par;
    total_registros := v_grupo.total_registros;
    total_ativos := v_grupo.total_ativos;
    vinculos_registrados := public.n3_rebuild_auto_vinculos_for_signature(
      v_grupo.equipe_id,
      v_grupo.assinatura_assunto_par,
      p_actor
    );
    RETURN NEXT;
  END LOOP;
END;
$function$;
CREATE OR REPLACE FUNCTION public.fn_n3_auto_vinculos_after_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_old_assinatura text;
  v_new_assinatura text;
  v_actor uuid;
BEGIN
  v_actor := COALESCE(
    auth.uid(),
    CASE
      WHEN TG_OP = 'DELETE' THEN OLD.criado_por
      ELSE NEW.criado_por
    END
  );

  IF TG_OP = 'INSERT' THEN
    v_new_assinatura := public.n3_assunto_dupla_assinatura(NEW.assunto);

    IF v_new_assinatura IS NOT NULL THEN
      PERFORM public.n3_rebuild_auto_vinculos_for_signature(NEW.equipe_id, v_new_assinatura, v_actor);
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE' THEN
    v_old_assinatura := public.n3_assunto_dupla_assinatura(OLD.assunto);
    v_new_assinatura := public.n3_assunto_dupla_assinatura(NEW.assunto);

    IF OLD.equipe_id IS DISTINCT FROM NEW.equipe_id
       OR OLD.assunto IS DISTINCT FROM NEW.assunto
       OR OLD.status IS DISTINCT FROM NEW.status THEN
      IF v_old_assinatura IS NOT NULL THEN
        PERFORM public.n3_rebuild_auto_vinculos_for_signature(OLD.equipe_id, v_old_assinatura, v_actor);
      END IF;

      IF v_new_assinatura IS NOT NULL
         AND (OLD.equipe_id IS DISTINCT FROM NEW.equipe_id OR v_old_assinatura IS DISTINCT FROM v_new_assinatura) THEN
        PERFORM public.n3_rebuild_auto_vinculos_for_signature(NEW.equipe_id, v_new_assinatura, v_actor);
      END IF;
    END IF;

    RETURN NEW;
  END IF;

  IF TG_OP = 'DELETE' THEN
    v_old_assinatura := public.n3_assunto_dupla_assinatura(OLD.assunto);

    IF v_old_assinatura IS NOT NULL THEN
      PERFORM public.n3_rebuild_auto_vinculos_for_signature(OLD.equipe_id, v_old_assinatura, v_actor);
    END IF;

    RETURN OLD;
  END IF;

  RETURN NULL;
END;
$function$;
REVOKE ALL ON FUNCTION public.n3_assunto_dupla_assinatura(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.n3_rebuild_auto_vinculos_for_signature(uuid, text, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.n3_rebuild_all_auto_vinculos(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fn_n3_auto_vinculos_after_change() FROM PUBLIC;
DROP TRIGGER IF EXISTS trg_n3_auto_vinculos_after_change ON public.escalacoes_n3;
CREATE TRIGGER trg_n3_auto_vinculos_after_change
  AFTER INSERT OR UPDATE OF equipe_id, assunto, status OR DELETE
  ON public.escalacoes_n3
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_n3_auto_vinculos_after_change();
COMMENT ON FUNCTION public.n3_assunto_dupla_assinatura(text) IS
  'Retorna a assinatura normalizada assunto1::assunto2 usando os dois primeiros assuntos da escalação N3.';
COMMENT ON FUNCTION public.n3_rebuild_auto_vinculos_for_signature(uuid, text, uuid) IS
  'Reconstrói os vínculos automáticos de uma equipe para uma dupla ordenada de assuntos.';
COMMENT ON FUNCTION public.n3_rebuild_all_auto_vinculos(uuid, uuid) IS
  'Refaz o backfill completo dos vínculos automáticos de Escalações N3 com base nos dois primeiros assuntos.';
NOTIFY pgrst, 'reload schema';
COMMIT;

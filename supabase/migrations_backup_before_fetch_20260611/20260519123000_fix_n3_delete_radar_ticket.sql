-- ============================================================================
-- Corrige exclusao de escalacoes N3 com copia associada no Radar
-- ============================================================================

BEGIN;
DO $$
DECLARE
  v_constraint record;
BEGIN
  IF to_regclass('public.radar_tickets') IS NOT NULL
     AND EXISTS (
       SELECT 1
       FROM information_schema.columns
       WHERE table_schema = 'public'
         AND table_name = 'radar_tickets'
         AND column_name = 'escalacao_n3_id'
     ) THEN
    ALTER TABLE public.radar_tickets
      ALTER COLUMN escalacao_n3_id DROP NOT NULL;

    FOR v_constraint IN
      SELECT c.conname
      FROM pg_constraint c
      JOIN pg_attribute a
        ON a.attrelid = c.conrelid
       AND a.attnum = ANY(c.conkey)
      WHERE c.conrelid = 'public.radar_tickets'::regclass
        AND c.contype = 'f'
        AND a.attname = 'escalacao_n3_id'
    LOOP
      EXECUTE format('ALTER TABLE public.radar_tickets DROP CONSTRAINT IF EXISTS %I', v_constraint.conname);
    END LOOP;

    ALTER TABLE public.radar_tickets
      ADD CONSTRAINT radar_tickets_escalacao_n3_id_fkey
      FOREIGN KEY (escalacao_n3_id)
      REFERENCES public.escalacoes_n3(id)
      ON DELETE SET NULL;

    CREATE INDEX IF NOT EXISTS idx_radar_tickets_escalacao_n3_id
      ON public.radar_tickets(escalacao_n3_id)
      WHERE escalacao_n3_id IS NOT NULL;

    COMMENT ON COLUMN public.radar_tickets.escalacao_n3_id IS
      'Referencia a escalacao N3 que originou este ticket no radar. Ao excluir a escalacao, a copia no Radar e removida por soft-delete via RPC.';
  END IF;
END $$;
CREATE OR REPLACE FUNCTION public.deletar_escalacao_n3(p_escalacao_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_criado_por uuid;
  v_usuario_id uuid := auth.uid();
  v_radar_removidos integer := 0;
  v_escalacao_removida integer := 0;
  v_tem_radar boolean;
  v_tem_coluna_escalacao boolean;
  v_tem_coluna_deletado boolean;
  v_tem_coluna_atualizado boolean;
BEGIN
  IF p_escalacao_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Escalacao N3 nao informada');
  END IF;

  IF v_usuario_id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Usuario nao autenticado');
  END IF;

  SELECT criado_por
    INTO v_criado_por
  FROM public.escalacoes_n3
  WHERE id = p_escalacao_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Escalacao N3 nao encontrada');
  END IF;

  IF v_criado_por IS DISTINCT FROM v_usuario_id THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Sem permissao para remover esta escalacao');
  END IF;

  v_tem_radar := to_regclass('public.radar_tickets') IS NOT NULL;

  IF v_tem_radar THEN
    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'radar_tickets'
        AND column_name = 'escalacao_n3_id'
    ) INTO v_tem_coluna_escalacao;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'radar_tickets'
        AND column_name = 'deletado'
    ) INTO v_tem_coluna_deletado;

    SELECT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema = 'public'
        AND table_name = 'radar_tickets'
        AND column_name = 'atualizado_em'
    ) INTO v_tem_coluna_atualizado;

    IF v_tem_coluna_escalacao AND v_tem_coluna_deletado AND v_tem_coluna_atualizado THEN
      EXECUTE $sql$
        UPDATE public.radar_tickets
           SET deletado = true,
               atualizado_em = now(),
               escalacao_n3_id = NULL
         WHERE escalacao_n3_id = $1
      $sql$
      USING p_escalacao_id;

      GET DIAGNOSTICS v_radar_removidos = ROW_COUNT;
    ELSIF v_tem_coluna_escalacao THEN
      EXECUTE $sql$
        UPDATE public.radar_tickets
           SET escalacao_n3_id = NULL
         WHERE escalacao_n3_id = $1
      $sql$
      USING p_escalacao_id;

      GET DIAGNOSTICS v_radar_removidos = ROW_COUNT;
    END IF;
  END IF;

  DELETE FROM public.escalacoes_n3
  WHERE id = p_escalacao_id
    AND criado_por = v_usuario_id;

  GET DIAGNOSTICS v_escalacao_removida = ROW_COUNT;

  IF v_escalacao_removida <> 1 THEN
    RETURN jsonb_build_object('ok', false, 'erro', 'Nao foi possivel remover a escalacao N3');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'radar_removidos', v_radar_removidos,
    'escalacao_removida', v_escalacao_removida
  );
EXCEPTION
  WHEN foreign_key_violation THEN
    RETURN jsonb_build_object(
      'ok', false,
      'erro', 'Nao foi possivel remover a escalacao porque ainda existem registros vinculados',
      'codigo', SQLSTATE
    );
  WHEN OTHERS THEN
    RETURN jsonb_build_object(
      'ok', false,
      'erro', SQLERRM,
      'codigo', SQLSTATE
    );
END;
$function$;
GRANT EXECUTE ON FUNCTION public.deletar_escalacao_n3(uuid) TO authenticated;
CREATE OR REPLACE FUNCTION public.fn_soft_delete_radar_from_n3()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_tem_radar boolean;
  v_tem_coluna_escalacao boolean;
  v_tem_coluna_deletado boolean;
  v_tem_coluna_atualizado boolean;
BEGIN
  v_tem_radar := to_regclass('public.radar_tickets') IS NOT NULL;

  IF NOT v_tem_radar THEN
    RETURN OLD;
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'radar_tickets'
      AND column_name = 'escalacao_n3_id'
  ) INTO v_tem_coluna_escalacao;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'radar_tickets'
      AND column_name = 'deletado'
  ) INTO v_tem_coluna_deletado;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'radar_tickets'
      AND column_name = 'atualizado_em'
  ) INTO v_tem_coluna_atualizado;

  IF v_tem_coluna_escalacao AND v_tem_coluna_deletado AND v_tem_coluna_atualizado THEN
    EXECUTE $sql$
      UPDATE public.radar_tickets
         SET deletado = true,
             atualizado_em = now(),
             escalacao_n3_id = NULL
       WHERE escalacao_n3_id = $1
    $sql$
    USING OLD.id;
  ELSIF v_tem_coluna_escalacao THEN
    EXECUTE $sql$
      UPDATE public.radar_tickets
         SET escalacao_n3_id = NULL
       WHERE escalacao_n3_id = $1
    $sql$
    USING OLD.id;
  END IF;

  RETURN OLD;
END;
$function$;
DROP TRIGGER IF EXISTS trg_soft_delete_radar_from_n3 ON public.escalacoes_n3;
CREATE TRIGGER trg_soft_delete_radar_from_n3
  BEFORE DELETE ON public.escalacoes_n3
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_soft_delete_radar_from_n3();
NOTIFY pgrst, 'reload schema';
COMMIT;

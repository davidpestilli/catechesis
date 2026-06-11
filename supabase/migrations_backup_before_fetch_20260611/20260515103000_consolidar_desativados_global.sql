SET search_path TO public, extensions;
DO $$
DECLARE
  v_main_folder_id uuid;
BEGIN
  SELECT id
    INTO v_main_folder_id
  FROM public.pastas_scripts
  WHERE nome = '🗑️ Desativados'
  ORDER BY ordem NULLS LAST, criado_em ASC, id ASC
  LIMIT 1;

  IF v_main_folder_id IS NULL THEN
    RAISE NOTICE 'Nenhuma pasta Desativados encontrada para consolidar.';
    RETURN;
  END IF;

  UPDATE public.scripts_customizados
  SET pasta_id = v_main_folder_id
  WHERE pasta_id IN (
    SELECT id
    FROM public.pastas_scripts
    WHERE nome = '🗑️ Desativados'
      AND id <> v_main_folder_id
  );

  UPDATE public.pastas_scripts
  SET pasta_pai_id = v_main_folder_id
  WHERE pasta_pai_id IN (
    SELECT id
    FROM public.pastas_scripts
    WHERE nome = '🗑️ Desativados'
      AND id <> v_main_folder_id
  );

  DELETE FROM public.pastas_scripts
  WHERE nome = '🗑️ Desativados'
    AND id <> v_main_folder_id;

  UPDATE public.pastas_scripts
  SET pasta_pai_id = NULL,
      ordem = 9999,
      icone = '🗑️',
      cor = '#3B82F6'
  WHERE id = v_main_folder_id;
END $$;
CREATE OR REPLACE FUNCTION public.get_pasta_desativados_id(p_equipe_id uuid)
RETURNS uuid
LANGUAGE plpgsql
AS $function$
DECLARE
  v_pasta_id uuid;
BEGIN
  SELECT id
    INTO v_pasta_id
  FROM public.pastas_scripts
  WHERE nome = '🗑️ Desativados'
  ORDER BY ordem NULLS LAST, criado_em ASC, id ASC
  LIMIT 1;

  IF v_pasta_id IS NULL THEN
    INSERT INTO public.pastas_scripts (nome, icone, equipe_id, ordem, pasta_pai_id)
    VALUES ('🗑️ Desativados', '🗑️', p_equipe_id, 9999, NULL)
    RETURNING id INTO v_pasta_id;
  END IF;

  RETURN v_pasta_id;
END;
$function$;
DO $$
DECLARE
  v_total integer;
BEGIN
  SELECT count(*)
    INTO v_total
  FROM public.pastas_scripts
  WHERE nome = '🗑️ Desativados';

  IF v_total > 1 THEN
    RAISE EXCEPTION 'Consolidacao de Desativados incompleta: % pastas restantes.', v_total;
  END IF;
END $$;

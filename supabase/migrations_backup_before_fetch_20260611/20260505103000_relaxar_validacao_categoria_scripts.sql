-- Permite salvar scripts mesmo quando categoria/subcategoria estao ausentes
-- ou inconsistentes com a taxonomia atual.

CREATE OR REPLACE FUNCTION public.validar_script_categoria_hierarquica()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'distribuidor'
AS $function$
BEGIN
  RETURN NEW;
END;
$function$;
COMMENT ON FUNCTION public.validar_script_categoria_hierarquica()
IS 'Compatibilidade para triggers de scripts; categoria/subcategoria sao metadados opcionais e nao bloqueiam INSERT/UPDATE.';

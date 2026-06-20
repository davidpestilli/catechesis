CREATE OR REPLACE FUNCTION public.solicitar_exclusao_script(
  p_script_id uuid,
  p_usuario_id uuid,
  p_motivo text DEFAULT NULL::text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_email_enviado BOOLEAN;
  v_script_nome TEXT;
  v_exclusao_pendente BOOLEAN;
  v_admin_record RECORD;
  v_script_data JSONB;
BEGIN
  -- Verificar se o script existe e obter estado atual
  SELECT
    email_enviado,
    nome,
    COALESCE(exclusao_pendente, false)
  INTO
    v_email_enviado,
    v_script_nome,
    v_exclusao_pendente
  FROM scripts_customizados
  WHERE id = p_script_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Script não encontrado'
    );
  END IF;

  IF v_exclusao_pendente THEN
    RETURN jsonb_build_object(
      'sucesso', false,
      'erro', 'Já existe uma solicitação de exclusão pendente para este script'
    );
  END IF;

  -- Capturar dados do script para log
  SELECT to_jsonb(sc.*) INTO v_script_data
  FROM scripts_customizados sc
  WHERE sc.id = p_script_id;

  IF v_email_enviado IS NULL OR v_email_enviado = false THEN
    -- HARD DELETE: email não foi enviado, pode excluir diretamente
    INSERT INTO scripts_exclusao_log (script_id, tipo_exclusao, solicitante_id, motivo, dados_script)
    VALUES (p_script_id, 'hard', p_usuario_id, p_motivo, v_script_data);

    DELETE FROM scripts_customizados WHERE id = p_script_id;

    RETURN jsonb_build_object(
      'sucesso', true,
      'tipo_exclusao', 'hard',
      'mensagem', 'Script excluído permanentemente'
    );
  END IF;

  -- SOFT DELETE: email foi enviado, precisa de aprovação
  UPDATE scripts_customizados
  SET
    exclusao_pendente = true,
    exclusao_solicitada_em = NOW(),
    exclusao_solicitada_por = p_usuario_id,
    motivo_exclusao = p_motivo
  WHERE id = p_script_id;

  INSERT INTO scripts_exclusao_log (script_id, tipo_exclusao, solicitante_id, motivo, dados_script)
  VALUES (p_script_id, 'soft', p_usuario_id, p_motivo, v_script_data);

  -- Notificar apenas admins válidos em auth.users e evitar duplicidade de pendência
  FOR v_admin_record IN
    SELECT u.id
    FROM public.users u
    INNER JOIN auth.users au ON au.id = u.id
    WHERE u.role = 'admin'
      AND u.ativo = true
  LOOP
    INSERT INTO notificacoes_exclusao_scripts (
      script_id,
      script_nome,
      admin_id,
      solicitante_id,
      motivo
    )
    SELECT
      p_script_id,
      v_script_nome,
      v_admin_record.id,
      p_usuario_id,
      p_motivo
    WHERE NOT EXISTS (
      SELECT 1
      FROM notificacoes_exclusao_scripts n
      WHERE n.script_id = p_script_id
        AND n.admin_id = v_admin_record.id
        AND n.lida = false
    );
  END LOOP;

  RETURN jsonb_build_object(
    'sucesso', true,
    'tipo_exclusao', 'soft',
    'mensagem', 'Solicitação de exclusão enviada para aprovação'
  );
END;
$function$;

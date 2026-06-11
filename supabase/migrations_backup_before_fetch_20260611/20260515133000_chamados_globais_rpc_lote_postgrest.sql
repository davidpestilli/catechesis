-- Adiciona encerramento de chamados globais por lotes para evitar timeout no PostgREST.

CREATE OR REPLACE FUNCTION public.responder_chamado_global_lote(
  p_global_id uuid,
  p_resposta text,
  p_limite integer DEFAULT 300
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_equipe_id uuid;
  v_limite int := LEAST(GREATEST(COALESCE(p_limite, 300), 1), 1000);
  v_total_membros int := 0;
  v_total_pendentes int := 0;
  v_processados int := 0;
  v_restantes int := 0;
  v_tickets_sem_registro int := 0;
  v_now timestamp without time zone := now();
BEGIN
  SELECT equipe_id
    INTO v_equipe_id
  FROM chamados_globais
  WHERE id = p_global_id
    AND ativo = true
  FOR UPDATE;

  IF v_equipe_id IS NULL THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Chamado global não encontrado ou já encerrado'
    );
  END IF;

  SELECT count(*)::int
    INTO v_total_pendentes
  FROM tickets_globais
  WHERE chamado_global_id = p_global_id
    AND respondido = false;

  IF v_total_pendentes = 0 THEN
    UPDATE chamados_globais
    SET
      resposta = p_resposta,
      ativo = false,
      encerrado_at = now(),
      updated_at = now()
    WHERE id = p_global_id;

    RETURN jsonb_build_object(
      'success', true,
      'sucesso', 0,
      'processados', 0,
      'restantes', 0,
      'total_tickets', 0,
      'total_membros', 0,
      'finalizado', true,
      'message', 'Global encerrado sem tickets pendentes'
    );
  END IF;

  SELECT count(*)::int
    INTO v_total_membros
  FROM users
  WHERE equipe_id = v_equipe_id
    AND ativo = true;

  IF v_total_membros = 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Nenhum membro ativo encontrado na equipe para distribuir tickets'
    );
  END IF;

  SELECT count(*)::int
    INTO v_tickets_sem_registro
  FROM tickets_globais tg
  LEFT JOIN tickets t ON t.id = tg.ticket_id
  WHERE tg.chamado_global_id = p_global_id
    AND tg.respondido = false
    AND t.id IS NULL;

  IF v_tickets_sem_registro > 0 THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', format('Existem %s vínculos sem ticket correspondente. Encerramento cancelado.', v_tickets_sem_registro)
    );
  END IF;

  WITH membros AS (
    SELECT
      id,
      row_number() OVER (ORDER BY nome NULLS LAST, email NULLS LAST, id) AS rn
    FROM users
    WHERE equipe_id = v_equipe_id
      AND ativo = true
  ),
  pendentes_base AS (
    SELECT
      tg.id AS vinculo_id,
      tg.ticket_id,
      tg.anexado_at
    FROM tickets_globais tg
    WHERE tg.chamado_global_id = p_global_id
      AND tg.respondido = false
    ORDER BY tg.anexado_at, tg.id
    LIMIT v_limite
  ),
  pendentes AS (
    SELECT
      pb.vinculo_id,
      pb.ticket_id,
      row_number() OVER (ORDER BY pb.anexado_at, pb.vinculo_id) AS rn
    FROM pendentes_base pb
  ),
  distribuicao AS (
    SELECT
      p.vinculo_id,
      p.ticket_id,
      m.id AS membro_id
    FROM pendentes p
    JOIN membros m
      ON m.rn = ((p.rn - 1) % v_total_membros) + 1
  ),
  tickets_atualizados AS (
    UPDATE tickets t
    SET
      usuario_atual = d.membro_id,
      status = 'finalizado',
      resposta_ia = p_resposta,
      finished_at = v_now,
      mantido_por = NULL,
      mantido_at = NULL,
      suspenso = false,
      causa_suspensao = NULL,
      updated_at = v_now
    FROM distribuicao d
    WHERE t.id = d.ticket_id
    RETURNING t.id
  ),
  vinculos_atualizados AS (
    UPDATE tickets_globais tg
    SET respondido = true
    FROM distribuicao d
    JOIN tickets_atualizados ta ON ta.id = d.ticket_id
    WHERE tg.id = d.vinculo_id
      AND tg.respondido = false
    RETURNING tg.id
  )
  SELECT count(*)::int
    INTO v_processados
  FROM vinculos_atualizados;

  IF v_processados = 0 THEN
    RAISE EXCEPTION 'Nenhum ticket foi atualizado no lote do chamado global %', p_global_id;
  END IF;

  v_restantes := GREATEST(v_total_pendentes - v_processados, 0);

  IF v_restantes = 0 THEN
    UPDATE chamados_globais
    SET
      resposta = p_resposta,
      ativo = false,
      encerrado_at = now(),
      updated_at = now()
    WHERE id = p_global_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'sucesso', v_processados,
    'processados', v_processados,
    'restantes', v_restantes,
    'total_tickets', v_total_pendentes,
    'total_pendentes_antes', v_total_pendentes,
    'total_membros', v_total_membros,
    'finalizado', v_restantes = 0,
    'message', CASE
      WHEN v_restantes = 0 THEN format('Finalizados %s tickets no ultimo lote. Global encerrado.', v_processados)
      ELSE format('Finalizados %s tickets neste lote. Restam %s.', v_processados, v_restantes)
    END
  );
END;
$$;
COMMENT ON FUNCTION public.responder_chamado_global_lote(uuid, text, integer) IS
'Processa o encerramento de um chamado global em lotes curtos para evitar timeout do PostgREST. Chamadas sucessivas retomam pelos tickets pendentes.';
GRANT EXECUTE ON FUNCTION public.responder_chamado_global_lote(uuid, text, integer) TO authenticated;
NOTIFY pgrst, 'reload schema';

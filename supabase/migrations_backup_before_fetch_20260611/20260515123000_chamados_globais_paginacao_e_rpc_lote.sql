-- Corrige chamados globais com grandes volumes de tickets anexados.
-- 1. Adiciona índices para listagem e encerramento por lote.
-- 2. Troca responder_chamado_global para operações set-based, evitando loop por ticket.

CREATE INDEX IF NOT EXISTS idx_tickets_globais_global_anexado_desc
  ON public.tickets_globais (chamado_global_id, anexado_at DESC, id DESC);
CREATE INDEX IF NOT EXISTS idx_tickets_globais_global_pendentes
  ON public.tickets_globais (chamado_global_id, anexado_at, id)
  WHERE respondido = false;
CREATE OR REPLACE FUNCTION public.responder_chamado_global(
  p_global_id uuid,
  p_resposta text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO public
AS $$
DECLARE
  v_equipe_id uuid;
  v_total_membros int := 0;
  v_total_tickets int := 0;
  v_tickets_sem_registro int := 0;
  v_sucesso int := 0;
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
    INTO v_total_tickets
  FROM tickets_globais
  WHERE chamado_global_id = p_global_id
    AND respondido = false;

  IF v_total_tickets = 0 THEN
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
      'erros', 0,
      'total_membros', 0,
      'total_tickets', 0,
      'message', 'Global encerrado sem tickets anexados'
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
  pendentes AS (
    SELECT
      tg.ticket_id,
      row_number() OVER (ORDER BY tg.anexado_at, tg.id) AS rn
    FROM tickets_globais tg
    WHERE tg.chamado_global_id = p_global_id
      AND tg.respondido = false
  ),
  distribuicao AS (
    SELECT
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
    FROM tickets_atualizados ta
    WHERE tg.chamado_global_id = p_global_id
      AND tg.ticket_id = ta.id
      AND tg.respondido = false
    RETURNING tg.id
  )
  SELECT count(*)::int
    INTO v_sucesso
  FROM vinculos_atualizados;

  IF v_sucesso <> v_total_tickets THEN
    RAISE EXCEPTION 'Encerramento cancelado: % de % tickets foram atualizados', v_sucesso, v_total_tickets;
  END IF;

  UPDATE chamados_globais
  SET
    resposta = p_resposta,
    ativo = false,
    encerrado_at = now(),
    updated_at = now()
  WHERE id = p_global_id;

  RETURN jsonb_build_object(
    'success', true,
    'sucesso', v_sucesso,
    'erros', 0,
    'total_membros', v_total_membros,
    'total_tickets', v_total_tickets,
    'message', format('Finalizados %s tickets, distribuídos entre %s membros ativos', v_sucesso, v_total_membros)
  );
END;
$$;
COMMENT ON FUNCTION public.responder_chamado_global(uuid, text) IS
'Responde e finaliza todos os tickets de um chamado global em lote, distribuindo entre membros ativos, limpando suspensão e permitindo encerrar globals sem tickets.';
NOTIFY pgrst, 'reload schema';

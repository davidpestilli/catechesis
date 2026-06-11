-- =====================================================
-- RPC: upsert_ticket_embedding(s) — permite ao frontend gravar embeddings
-- de tickets respeitando escopo de equipe sem precisar de GRANT direto na tabela.
-- =====================================================

CREATE OR REPLACE FUNCTION public.upsert_ticket_embedding(
  p_ticket_id uuid,
  p_embedding vector(2000),
  p_descricao_hash text,
  p_embedding_model text DEFAULT 'text-embedding-3-large'
)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket record;
  v_equipe_id uuid;
  v_user_equipe uuid;
BEGIN
  -- Carrega ticket (sem coluna equipe_id — resolvida via GSE)
  SELECT id, numero_chamado, gse, status, updated_at
    INTO v_ticket
  FROM public.tickets
  WHERE id = p_ticket_id;

  IF v_ticket.id IS NULL THEN
    RAISE EXCEPTION 'Ticket % não encontrado', p_ticket_id;
  END IF;

  -- Resolve equipe pelo GSE (mesmo padrão de get_ticket_equipe_id)
  SELECT public.get_ticket_equipe_id(v_ticket.gse) INTO v_equipe_id;
  IF v_equipe_id IS NULL THEN
    RAISE EXCEPTION 'GSE % do ticket % não está mapeado para nenhuma equipe', v_ticket.gse, v_ticket.numero_chamado;
  END IF;

  -- Verifica que o usuário pertence à mesma equipe
  SELECT equipe_id INTO v_user_equipe
  FROM public.users
  WHERE id = auth.uid();

  IF v_user_equipe IS NULL OR v_user_equipe <> v_equipe_id THEN
    RAISE EXCEPTION 'Sem permissão para gerar embedding deste ticket';
  END IF;

  -- Tipo vector(2000) já garante a dimensão correta no parâmetro

  INSERT INTO public.ticket_embeddings (
    ticket_id, numero_chamado, gse, equipe_id, status,
    descricao_hash, embedding, embedding_model, embedding_dim,
    ticket_updated_at, updated_at
  ) VALUES (
    v_ticket.id, v_ticket.numero_chamado, v_ticket.gse, v_equipe_id, v_ticket.status,
    p_descricao_hash, p_embedding, p_embedding_model, 2000,
    v_ticket.updated_at, now()
  )
  ON CONFLICT (ticket_id) DO UPDATE SET
    numero_chamado    = EXCLUDED.numero_chamado,
    gse               = EXCLUDED.gse,
    equipe_id         = EXCLUDED.equipe_id,
    status            = EXCLUDED.status,
    descricao_hash    = EXCLUDED.descricao_hash,
    embedding         = EXCLUDED.embedding,
    embedding_model   = EXCLUDED.embedding_model,
    embedding_dim     = EXCLUDED.embedding_dim,
    ticket_updated_at = EXCLUDED.ticket_updated_at,
    updated_at        = now();

  -- Remove da fila para o worker não reprocessar
  DELETE FROM public.ticket_embeddings_queue WHERE ticket_id = p_ticket_id;

  RETURN true;
END;
$$;
GRANT EXECUTE ON FUNCTION public.upsert_ticket_embedding(uuid, vector, text, text) TO authenticated;
-- =====================================================
-- RPC: listar IDs de tickets que JÁ TÊM embedding (para o frontend filtrar)
-- =====================================================
CREATE OR REPLACE FUNCTION public.tickets_com_embedding(p_ticket_ids uuid[])
RETURNS TABLE (ticket_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT te.ticket_id
  FROM public.ticket_embeddings te
  JOIN public.users u ON u.id = auth.uid()
  WHERE te.ticket_id = ANY(p_ticket_ids)
    AND te.equipe_id = u.equipe_id;
$$;
GRANT EXECUTE ON FUNCTION public.tickets_com_embedding(uuid[]) TO authenticated;

INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem)
VALUES (
  'distribuidor.excluir_ticket_hml',
  'Excluir ticket HML do Distribuidor',
  'Permite excluir permanentemente tickets HML nas filas Livres e Suspensos do Distribuidor.',
  'distribuidor',
  'src/components/DistribuidorFila.tsx'
)
ON CONFLICT (codigo) DO UPDATE
SET nome = EXCLUDED.nome,
    descricao = EXCLUDED.descricao,
    categoria = EXCLUDED.categoria,
    origem = EXCLUDED.origem;
CREATE OR REPLACE FUNCTION public.distribuidor_excluir_ticket_hml(p_ticket_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_ticket public.tickets%ROWTYPE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Usuário não autenticado');
  END IF;

  IF NOT public.tem_permissao('distribuidor.excluir_ticket_hml') THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Sem permissão para excluir tickets HML');
  END IF;

  SELECT *
  INTO v_ticket
  FROM public.tickets
  WHERE id = p_ticket_id;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Ticket não encontrado');
  END IF;

  IF NOT public.is_gse_homologacao(v_ticket.gse) THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'A exclusão é permitida apenas para tickets HML');
  END IF;

  IF v_ticket.status <> 'aguardando' OR v_ticket.usuario_atual IS NOT NULL THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'A exclusão só é permitida para tickets HML nas filas Livres ou Suspensos');
  END IF;

  DELETE FROM public.tickets
  WHERE id = p_ticket_id;

  RETURN jsonb_build_object(
    'sucesso', true,
    'ticket_id', p_ticket_id,
    'numero_chamado', v_ticket.numero_chamado
  );
EXCEPTION
  WHEN OTHERS THEN
    RETURN jsonb_build_object('sucesso', false, 'erro', 'Erro ao excluir ticket HML. Tente novamente.');
END;
$$;
REVOKE ALL ON FUNCTION public.distribuidor_excluir_ticket_hml(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.distribuidor_excluir_ticket_hml(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.distribuidor_excluir_ticket_hml(uuid) TO service_role;
NOTIFY pgrst, 'reload schema';

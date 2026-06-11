-- =====================================================================
-- Fix: admin_atualizar_usuario não permitia limpar equipe_id ou setor_id
-- =====================================================================
-- Problema: a função usava COALESCE(p_equipe_id, equipe_id), de modo que
-- ao receber NULL o campo NÃO era atualizado. Resultado: ao tentar
-- "Nenhuma" no select de Equipe (BossOnly → Editar Usuário), o valor
-- continuava o anterior, embora a UI mostrasse "salvo com sucesso".
--
-- Solução: adicionar parâmetros booleanos opcionais p_clear_equipe_id e
-- p_clear_setor_id. Quando TRUE, força o campo para NULL. Mantém o
-- comportamento anterior (COALESCE) quando FALSE/omitido.
-- =====================================================================

DROP FUNCTION IF EXISTS public.admin_atualizar_usuario(UUID, TEXT, TEXT, UUID, UUID);
DROP FUNCTION IF EXISTS public.admin_atualizar_usuario(UUID, TEXT, TEXT, UUID, UUID, BOOLEAN, BOOLEAN);
CREATE OR REPLACE FUNCTION public.admin_atualizar_usuario(
  p_user_id UUID,
  p_nome TEXT DEFAULT NULL,
  p_role TEXT DEFAULT NULL,
  p_equipe_id UUID DEFAULT NULL,
  p_setor_id UUID DEFAULT NULL,
  p_clear_equipe_id BOOLEAN DEFAULT FALSE,
  p_clear_setor_id BOOLEAN DEFAULT FALSE
) RETURNS JSONB AS $$
BEGIN
  -- Verificar permissão (admin/boss)
  IF NOT is_boss() THEN
    RETURN jsonb_build_object('success', false, 'error', 'Acesso negado');
  END IF;

  -- Verificar se usuário existe
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = p_user_id) THEN
    RETURN jsonb_build_object('success', false, 'error', 'Usuário não encontrado');
  END IF;

  UPDATE users SET
    nome = COALESCE(p_nome, nome),
    role = COALESCE(p_role::user_role, role),
    equipe_id = CASE
      WHEN p_clear_equipe_id THEN NULL
      ELSE COALESCE(p_equipe_id, equipe_id)
    END,
    setor_id = CASE
      WHEN p_clear_setor_id THEN NULL
      ELSE COALESCE(p_setor_id, setor_id)
    END
  WHERE id = p_user_id;

  RETURN jsonb_build_object(
    'success', true,
    'message', 'Usuário atualizado com sucesso'
  );

EXCEPTION WHEN OTHERS THEN
  RETURN jsonb_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
GRANT EXECUTE ON FUNCTION public.admin_atualizar_usuario(
  UUID, TEXT, TEXT, UUID, UUID, BOOLEAN, BOOLEAN
) TO authenticated;
COMMENT ON FUNCTION public.admin_atualizar_usuario IS
  'Atualiza dados de um usuário (nome, role, equipe, setor). Apenas admin/boss. '
  'Use p_clear_equipe_id=TRUE/p_clear_setor_id=TRUE para definir o campo como NULL.';

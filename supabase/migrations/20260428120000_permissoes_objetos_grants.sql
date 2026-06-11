-- =====================================================
-- Sistema de Gerenciamento de Autorizações
-- =====================================================
-- Catálogo de objetos protegidos + grants por equipe/perfil/usuário.
-- Admin SEMPRE tem acesso (independente de grants).
-- A ausência de grant = acesso negado para não-admins.
-- =====================================================

-- 1) Catálogo de objetos protegidos
CREATE TABLE IF NOT EXISTS public.permissoes_objetos (
  codigo       TEXT PRIMARY KEY,
  nome         TEXT NOT NULL,
  descricao    TEXT,
  categoria    TEXT NOT NULL,
  origem       TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_permissoes_objetos_categoria
  ON public.permissoes_objetos (categoria);
COMMENT ON TABLE public.permissoes_objetos IS
  'Catálogo de objetos do sistema sujeitos a controle de autorização. Cada código identifica um recurso/ação que pode ser concedida a equipes, perfis ou usuários específicos.';
COMMENT ON COLUMN public.permissoes_objetos.codigo IS
  'Identificador estável do objeto. Convenção: <area>.<acao> em snake_case (ex: distribuidor.upload_excel).';
COMMENT ON COLUMN public.permissoes_objetos.categoria IS
  'Agrupamento lógico para apresentação na UI (admin, distribuidor, scripts, radar, etc).';
COMMENT ON COLUMN public.permissoes_objetos.origem IS
  'Referência opcional ao arquivo/linha onde o check hardcoded original existe (para rastreio durante a migração).';
-- 2) Grants: quem tem acesso a quais objetos
CREATE TABLE IF NOT EXISTS public.permissoes_grants (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  objeto_codigo   TEXT NOT NULL REFERENCES public.permissoes_objetos(codigo) ON DELETE CASCADE,
  target_type     TEXT NOT NULL CHECK (target_type IN ('equipe','role','usuario')),
  target_id       TEXT NOT NULL,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_by      UUID REFERENCES public.users(id) ON DELETE SET NULL,
  CONSTRAINT permissoes_grants_unique UNIQUE (objeto_codigo, target_type, target_id)
);
CREATE INDEX IF NOT EXISTS idx_permissoes_grants_objeto
  ON public.permissoes_grants (objeto_codigo);
CREATE INDEX IF NOT EXISTS idx_permissoes_grants_target
  ON public.permissoes_grants (target_type, target_id);
COMMENT ON TABLE public.permissoes_grants IS
  'Concessões de acesso. A presença de uma linha = grant ativo. Para revogar, basta remover a linha. Admins têm acesso a tudo independente desta tabela.';
COMMENT ON COLUMN public.permissoes_grants.target_type IS
  'Tipo do alvo: equipe (target_id = equipes.id), role (target_id = nome do user_role), usuario (target_id = users.id).';
-- 3) RLS: leitura pública (autenticado), escrita só admin
ALTER TABLE public.permissoes_objetos ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.permissoes_grants  ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "permissoes_objetos_select_all" ON public.permissoes_objetos;
CREATE POLICY "permissoes_objetos_select_all"
  ON public.permissoes_objetos FOR SELECT
  TO authenticated USING (true);
DROP POLICY IF EXISTS "permissoes_objetos_admin_write" ON public.permissoes_objetos;
CREATE POLICY "permissoes_objetos_admin_write"
  ON public.permissoes_objetos FOR ALL
  TO authenticated
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));
DROP POLICY IF EXISTS "permissoes_grants_select_all" ON public.permissoes_grants;
CREATE POLICY "permissoes_grants_select_all"
  ON public.permissoes_grants FOR SELECT
  TO authenticated USING (true);
DROP POLICY IF EXISTS "permissoes_grants_admin_write" ON public.permissoes_grants;
CREATE POLICY "permissoes_grants_admin_write"
  ON public.permissoes_grants FOR ALL
  TO authenticated
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));
-- 4) Função de verificação (uso futuro pelo backend)
CREATE OR REPLACE FUNCTION public.tem_permissao(p_codigo TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_role    TEXT;
  v_equipe  UUID;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  SELECT role::TEXT, equipe_id INTO v_role, v_equipe
  FROM public.users WHERE id = v_user_id;

  -- Admin sempre passa
  IF v_role = 'admin' THEN
    RETURN TRUE;
  END IF;

  -- Grant por usuário
  IF EXISTS (
    SELECT 1 FROM public.permissoes_grants
    WHERE objeto_codigo = p_codigo
      AND target_type = 'usuario'
      AND target_id = v_user_id::TEXT
  ) THEN RETURN TRUE; END IF;

  -- Grant por perfil
  IF v_role IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.permissoes_grants
    WHERE objeto_codigo = p_codigo
      AND target_type = 'role'
      AND target_id = v_role
  ) THEN RETURN TRUE; END IF;

  -- Grant por equipe
  IF v_equipe IS NOT NULL AND EXISTS (
    SELECT 1 FROM public.permissoes_grants
    WHERE objeto_codigo = p_codigo
      AND target_type = 'equipe'
      AND target_id = v_equipe::TEXT
  ) THEN RETURN TRUE; END IF;

  RETURN FALSE;
END;
$$;
COMMENT ON FUNCTION public.tem_permissao(TEXT) IS
  'Verifica se o usuário autenticado tem permissão para o objeto informado. Admin sempre retorna TRUE.';
-- 5) RPCs de gestão (somente admin)
CREATE OR REPLACE FUNCTION public.permissoes_listar_objetos()
RETURNS TABLE (
  codigo       TEXT,
  nome         TEXT,
  descricao    TEXT,
  categoria    TEXT,
  origem       TEXT,
  total_grants BIGINT
)
LANGUAGE sql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
  SELECT o.codigo, o.nome, o.descricao, o.categoria, o.origem,
         COALESCE(g.total, 0) AS total_grants
  FROM public.permissoes_objetos o
  LEFT JOIN (
    SELECT objeto_codigo, COUNT(*)::BIGINT AS total
    FROM public.permissoes_grants
    GROUP BY objeto_codigo
  ) g ON g.objeto_codigo = o.codigo
  ORDER BY o.categoria, o.nome;
$$;
CREATE OR REPLACE FUNCTION public.permissoes_listar_grants(p_objeto_codigo TEXT)
RETURNS TABLE (
  id            UUID,
  objeto_codigo TEXT,
  target_type   TEXT,
  target_id     TEXT,
  target_nome   TEXT,
  created_at    TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT g.id, g.objeto_codigo, g.target_type, g.target_id,
         (CASE g.target_type
           WHEN 'equipe'  THEN (SELECT e.nome::TEXT FROM public.equipes e WHERE e.id::TEXT = g.target_id)
           WHEN 'role'    THEN g.target_id
           WHEN 'usuario' THEN (SELECT u.nome::TEXT FROM public.users u WHERE u.id::TEXT = g.target_id)
         END)::TEXT AS target_nome,
         g.created_at
  FROM public.permissoes_grants g
  WHERE g.objeto_codigo = p_objeto_codigo
  ORDER BY g.target_type, target_nome NULLS LAST;
END;
$$;
CREATE OR REPLACE FUNCTION public.permissoes_set_grant(
  p_objeto_codigo TEXT,
  p_target_type   TEXT,
  p_target_id     TEXT,
  p_granted       BOOLEAN
) RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller UUID := auth.uid();
  v_is_admin BOOLEAN;
BEGIN
  SELECT EXISTS (SELECT 1 FROM public.users WHERE id = v_caller AND role = 'admin')
    INTO v_is_admin;

  IF NOT v_is_admin THEN
    RAISE EXCEPTION 'Apenas administradores podem alterar permissões';
  END IF;

  IF p_target_type NOT IN ('equipe','role','usuario') THEN
    RAISE EXCEPTION 'target_type inválido: %', p_target_type;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.permissoes_objetos WHERE codigo = p_objeto_codigo) THEN
    RAISE EXCEPTION 'Objeto de permissão inexistente: %', p_objeto_codigo;
  END IF;

  IF p_granted THEN
    INSERT INTO public.permissoes_grants (objeto_codigo, target_type, target_id, created_by)
    VALUES (p_objeto_codigo, p_target_type, p_target_id, v_caller)
    ON CONFLICT (objeto_codigo, target_type, target_id) DO NOTHING;
  ELSE
    DELETE FROM public.permissoes_grants
    WHERE objeto_codigo = p_objeto_codigo
      AND target_type = p_target_type
      AND target_id = p_target_id;
  END IF;

  RETURN TRUE;
END;
$$;
GRANT EXECUTE ON FUNCTION public.tem_permissao(TEXT)              TO authenticated;
GRANT EXECUTE ON FUNCTION public.permissoes_listar_objetos()      TO authenticated;
GRANT EXECUTE ON FUNCTION public.permissoes_listar_grants(TEXT)   TO authenticated;
GRANT EXECUTE ON FUNCTION public.permissoes_set_grant(TEXT,TEXT,TEXT,BOOLEAN) TO authenticated;
-- 6) Seed do catálogo
INSERT INTO public.permissoes_objetos (codigo, nome, descricao, categoria, origem) VALUES
  -- ADMIN / HOME
  ('admin.boss_only_modal',             'Abrir modal Admin (BossOnly)',                'Acesso ao painel administrativo (botão escudo na Home).',                       'admin',        'src/pages/Home.tsx'),
  ('admin.smith_consulta',              'Abrir Smith (consulta KB)',                   'Botão Smith na Home — chat com base de conhecimento.',                          'admin',        'src/pages/Home.tsx'),
  ('admin.sinatra',                     'Abrir Sinatra (transcrição)',                 'Botão Sinatra na Home — transcrição de áudios.',                                'admin',        'src/pages/Home.tsx'),
  ('admin.embeddings_dev',              'Abrir painel Embeddings (Dev)',               'Botão visível só em DEV — gerenciamento de embeddings.',                        'admin',        'src/pages/Home.tsx'),

  -- SCRIPTS
  ('scripts.curadoria_acesso',          'Curadoria de Scripts',                        'Acesso aos controles de curadoria (revisão/aprovação de scripts).',             'scripts',      'src/hooks/useScriptsModal.ts'),
  ('scripts.n1_controles',              'Controles de envio N1 (Qualidade)',           'Filtros e ações de validação/envio para N1 nos scripts.',                       'scripts',      'src/hooks/useScriptsModal.ts'),
  ('scripts.em_numeros_modal',          'Abrir Scripts em Números',                    'Modal de analytics dos scripts.',                                               'scripts',      'src/pages/Home.tsx'),
  ('scripts.aprovar_exclusao',          'Aprovar/negar exclusão de scripts',           'Aba de exclusões pendentes no modal Admin.',                                    'scripts',      'src/services/notificacaoExclusaoService.ts'),

  -- DISTRIBUIDOR
  ('distribuidor.upload_excel',         'Importar Excel no Distribuidor',              'Botão "Importar Excel" no header do Distribuidor.',                             'distribuidor', 'src/components/DistribuidorHeader.tsx'),
  ('distribuidor.sos_keywords',         'Gerenciar palavras-chave SOS',                'Botão SOS no header do Distribuidor.',                                          'distribuidor', 'src/components/DistribuidorHeader.tsx'),
  ('distribuidor.suspender_mantidos',   'Suspender tickets mantidos em massa',         'Botão "Suspender Mantidos" no header.',                                         'distribuidor', 'src/components/DistribuidorHeader.tsx'),
  ('distribuidor.liberar_ticket_outro', 'Liberar tickets retidos por outros',          'Permite liberar/suspender ticket que está com outro usuário.',                  'distribuidor', 'src/components/DistribuidorFila.tsx'),

  -- RADAR DE TICKETS
  ('radar.dashboard_admin',             'Dashboard administrativo do Radar',           'Acesso completo de gestão dos radar tickets.',                                  'radar',        'src/components/radar/RadarTicketsModal.tsx'),
  ('radar.ticket_editar_qualquer',      'Editar qualquer ticket no Radar',             'Editar tickets de qualquer autor.',                                             'radar',        'src/components/radar/RadarTicketDetalheModal.tsx'),
  ('radar.ticket_excluir_qualquer',     'Excluir qualquer ticket no Radar',            'Excluir tickets de qualquer autor.',                                            'radar',        'src/components/radar/RadarTicketDetalheModal.tsx'),
  ('radar.comentario_excluir_qualquer', 'Excluir qualquer comentário no Radar',        'Excluir comentários de qualquer autor.',                                        'radar',        'src/components/radar/RadarTicketComentarios.tsx')
ON CONFLICT (codigo) DO UPDATE SET
  nome = EXCLUDED.nome,
  descricao = EXCLUDED.descricao,
  categoria = EXCLUDED.categoria,
  origem = EXCLUDED.origem,
  updated_at = NOW();

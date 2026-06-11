-- ============================================================
-- Migration: Sistema Melhorias Eproc
-- Data: 2026-04-10
-- Descrição: Tabelas, RLS, triggers e RPCs para o sistema
--            de sugestões de melhoria do Eproc
-- ============================================================

-- ============================================================
-- 1. TABELAS
-- ============================================================

-- 1.1 Tabela principal
CREATE TABLE melhorias_eproc (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tipo              TEXT NOT NULL CHECK (tipo IN ('nova_funcionalidade', 'correcao_configuracao')),
  subtipo           TEXT CHECK (
                      (tipo = 'correcao_configuracao' AND subtipo IN ('bug', 'parametro'))
                      OR (tipo = 'nova_funcionalidade' AND subtipo IS NULL)
                    ),
  titulo            TEXT NOT NULL,
  descricao         TEXT NOT NULL,
  justificativa     TEXT,
  modulo_eproc      TEXT,
  tickets_exemplo   TEXT[] DEFAULT '{}',
  status            TEXT NOT NULL DEFAULT 'rascunho'
                    CHECK (status IN ('rascunho', 'proposta', 'em_analise', 'aprovada', 'rejeitada', 'implementada')),
  prioridade        TEXT NOT NULL DEFAULT 'media'
                    CHECK (prioridade IN ('alta', 'media', 'baixa')),
  votos_count       INT NOT NULL DEFAULT 0,
  criado_por        UUID NOT NULL REFERENCES public.users(id),
  equipe_id         UUID NOT NULL REFERENCES equipes(id),
  criado_em         TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  deletado          BOOLEAN NOT NULL DEFAULT false,

  CONSTRAINT titulo_melhorias_nao_vazio CHECK (trim(titulo) != ''),
  CONSTRAINT descricao_melhorias_nao_vazia CHECK (trim(descricao) != '')
);
CREATE INDEX idx_melhorias_eproc_tipo ON melhorias_eproc(tipo) WHERE NOT deletado;
CREATE INDEX idx_melhorias_eproc_status ON melhorias_eproc(status) WHERE NOT deletado;
CREATE INDEX idx_melhorias_eproc_criado_em ON melhorias_eproc(criado_em DESC);
CREATE INDEX idx_melhorias_eproc_equipe_id ON melhorias_eproc(equipe_id);
CREATE INDEX idx_melhorias_eproc_criado_por ON melhorias_eproc(criado_por);
CREATE INDEX idx_melhorias_eproc_votos ON melhorias_eproc(votos_count DESC) WHERE NOT deletado;
CREATE INDEX idx_melhorias_eproc_prioridade ON melhorias_eproc(prioridade) WHERE NOT deletado;
CREATE INDEX idx_melhorias_eproc_deletado ON melhorias_eproc(deletado) WHERE deletado = false;
-- 1.2 Votos
CREATE TABLE melhorias_eproc_votos (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  melhoria_id   UUID NOT NULL REFERENCES melhorias_eproc(id) ON DELETE CASCADE,
  usuario_id    UUID NOT NULL REFERENCES public.users(id),
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT voto_unico UNIQUE (melhoria_id, usuario_id)
);
CREATE INDEX idx_melhorias_votos_melhoria ON melhorias_eproc_votos(melhoria_id);
CREATE INDEX idx_melhorias_votos_usuario ON melhorias_eproc_votos(usuario_id);
-- 1.3 Comentários
CREATE TABLE melhorias_eproc_comentarios (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  melhoria_id   UUID NOT NULL REFERENCES melhorias_eproc(id) ON DELETE CASCADE,
  autor_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
  conteudo      TEXT NOT NULL,
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT now(),
  atualizado_em TIMESTAMPTZ NOT NULL DEFAULT now(),

  CONSTRAINT conteudo_melhorias_nao_vazio CHECK (trim(conteudo) != '')
);
CREATE INDEX idx_melhorias_coment_melhoria ON melhorias_eproc_comentarios(melhoria_id);
CREATE INDEX idx_melhorias_coment_autor ON melhorias_eproc_comentarios(autor_id);
CREATE INDEX idx_melhorias_coment_criado ON melhorias_eproc_comentarios(criado_em DESC);
-- 1.4 Menções
CREATE TABLE melhorias_eproc_mencoes (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  melhoria_id           UUID NOT NULL REFERENCES melhorias_eproc(id) ON DELETE CASCADE,
  comentario_id         UUID NOT NULL REFERENCES melhorias_eproc_comentarios(id) ON DELETE CASCADE,
  usuario_mencionado_id UUID NOT NULL REFERENCES public.users(id),
  mencionado_por_id     UUID NOT NULL REFERENCES public.users(id),
  criado_em             TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_melhorias_mencao_usuario ON melhorias_eproc_mencoes(usuario_mencionado_id);
CREATE INDEX idx_melhorias_mencao_melhoria ON melhorias_eproc_mencoes(melhoria_id);
CREATE INDEX idx_melhorias_mencao_comentario ON melhorias_eproc_mencoes(comentario_id);
-- 1.5 Notificações
CREATE TABLE melhorias_eproc_notificacoes (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  melhoria_id     UUID NOT NULL REFERENCES melhorias_eproc(id) ON DELETE CASCADE,
  comentario_id   UUID REFERENCES melhorias_eproc_comentarios(id) ON DELETE SET NULL,
  destinatario_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  remetente_id    UUID REFERENCES public.users(id) ON DELETE SET NULL,
  tipo            TEXT NOT NULL CHECK (tipo IN ('comentario', 'mencao', 'status_alterado', 'novo_voto')),
  dados           JSONB,
  lida            BOOLEAN NOT NULL DEFAULT false,
  lida_em         TIMESTAMPTZ,
  criado_em       TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_melhorias_notif_destinatario ON melhorias_eproc_notificacoes(destinatario_id) WHERE NOT lida;
CREATE INDEX idx_melhorias_notif_melhoria ON melhorias_eproc_notificacoes(melhoria_id);
CREATE INDEX idx_melhorias_notif_criado ON melhorias_eproc_notificacoes(criado_em DESC);
-- ============================================================
-- 2. RLS
-- ============================================================

-- melhorias_eproc
ALTER TABLE melhorias_eproc ENABLE ROW LEVEL SECURITY;
CREATE POLICY "melhorias_select_all"
  ON melhorias_eproc FOR SELECT TO authenticated
  USING (NOT deletado);
CREATE POLICY "melhorias_insert_own"
  ON melhorias_eproc FOR INSERT TO authenticated
  WITH CHECK (criado_por = auth.uid());
CREATE POLICY "melhorias_update_own"
  ON melhorias_eproc FOR UPDATE TO authenticated
  USING (criado_por = auth.uid())
  WITH CHECK (criado_por = auth.uid());
CREATE POLICY "melhorias_update_admin"
  ON melhorias_eproc FOR UPDATE TO authenticated
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));
-- melhorias_eproc_votos
ALTER TABLE melhorias_eproc_votos ENABLE ROW LEVEL SECURITY;
CREATE POLICY "melhorias_votos_select_all"
  ON melhorias_eproc_votos FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "melhorias_votos_insert_own"
  ON melhorias_eproc_votos FOR INSERT TO authenticated
  WITH CHECK (usuario_id = auth.uid());
CREATE POLICY "melhorias_votos_delete_own"
  ON melhorias_eproc_votos FOR DELETE TO authenticated
  USING (usuario_id = auth.uid());
-- melhorias_eproc_comentarios
ALTER TABLE melhorias_eproc_comentarios ENABLE ROW LEVEL SECURITY;
CREATE POLICY "melhorias_coment_select_all"
  ON melhorias_eproc_comentarios FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "melhorias_coment_insert_own"
  ON melhorias_eproc_comentarios FOR INSERT TO authenticated
  WITH CHECK (autor_id = auth.uid());
CREATE POLICY "melhorias_coment_update_own"
  ON melhorias_eproc_comentarios FOR UPDATE TO authenticated
  USING (autor_id = auth.uid());
CREATE POLICY "melhorias_coment_delete_own_or_admin"
  ON melhorias_eproc_comentarios FOR DELETE TO authenticated
  USING (
    autor_id = auth.uid()
    OR EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin')
  );
-- melhorias_eproc_mencoes
ALTER TABLE melhorias_eproc_mencoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "melhorias_mencao_select_all"
  ON melhorias_eproc_mencoes FOR SELECT TO authenticated
  USING (true);
CREATE POLICY "melhorias_mencao_insert_auth"
  ON melhorias_eproc_mencoes FOR INSERT TO authenticated
  WITH CHECK (mencionado_por_id = auth.uid());
-- melhorias_eproc_notificacoes
ALTER TABLE melhorias_eproc_notificacoes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "melhorias_notif_select_own"
  ON melhorias_eproc_notificacoes FOR SELECT TO authenticated
  USING (destinatario_id = auth.uid());
CREATE POLICY "melhorias_notif_update_own"
  ON melhorias_eproc_notificacoes FOR UPDATE TO authenticated
  USING (destinatario_id = auth.uid());
-- ============================================================
-- 3. TRIGGERS
-- ============================================================

CREATE OR REPLACE FUNCTION update_melhorias_eproc_atualizado_em()
RETURNS TRIGGER AS $$
BEGIN
  NEW.atualizado_em = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_melhorias_eproc_atualizado_em
  BEFORE UPDATE ON melhorias_eproc
  FOR EACH ROW EXECUTE FUNCTION update_melhorias_eproc_atualizado_em();
CREATE TRIGGER trigger_melhorias_coment_atualizado_em
  BEFORE UPDATE ON melhorias_eproc_comentarios
  FOR EACH ROW EXECUTE FUNCTION update_melhorias_eproc_atualizado_em();
CREATE OR REPLACE FUNCTION sync_melhorias_votos_count()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE melhorias_eproc SET votos_count = votos_count + 1 WHERE id = NEW.melhoria_id;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE melhorias_eproc SET votos_count = votos_count - 1 WHERE id = OLD.melhoria_id;
    RETURN OLD;
  END IF;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_sync_votos_count
  AFTER INSERT OR DELETE ON melhorias_eproc_votos
  FOR EACH ROW EXECUTE FUNCTION sync_melhorias_votos_count();
-- ============================================================
-- 4. RPCs
-- ============================================================

-- RPC 1: Resumo geral (KPIs)
CREATE OR REPLACE FUNCTION melhorias_eproc_resumo()
RETURNS JSON AS $$
  SELECT json_build_object(
    'total', COUNT(*) FILTER (WHERE NOT deletado),
    'novas_funcionalidades', COUNT(*) FILTER (WHERE NOT deletado AND tipo = 'nova_funcionalidade'),
    'correcoes', COUNT(*) FILTER (WHERE NOT deletado AND tipo = 'correcao_configuracao'),
    'em_analise', COUNT(*) FILTER (WHERE NOT deletado AND status = 'em_analise'),
    'aprovadas', COUNT(*) FILTER (WHERE NOT deletado AND status = 'aprovada'),
    'implementadas', COUNT(*) FILTER (WHERE NOT deletado AND status = 'implementada')
  )
  FROM melhorias_eproc;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
-- RPC 2: Sugestões por data (para gráfico)
CREATE OR REPLACE FUNCTION melhorias_eproc_por_data(p_desde TIMESTAMPTZ DEFAULT now() - interval '30 days')
RETURNS TABLE(data DATE, total BIGINT) AS $$
  SELECT DATE(criado_em), COUNT(*)
  FROM melhorias_eproc
  WHERE NOT deletado AND criado_em >= p_desde
  GROUP BY DATE(criado_em)
  ORDER BY DATE(criado_em);
$$ LANGUAGE sql STABLE SECURITY DEFINER;
-- RPC 3: Sugestões por usuário (para gráfico)
CREATE OR REPLACE FUNCTION melhorias_eproc_por_usuario(p_desde TIMESTAMPTZ DEFAULT now() - interval '30 days', p_limit INT DEFAULT 15)
RETURNS TABLE(user_id UUID, nome TEXT, equipe_nome TEXT, total BIGINT) AS $$
  SELECT me.criado_por, u.nome, e.nome, COUNT(*)
  FROM melhorias_eproc me
  JOIN users u ON u.id = me.criado_por
  LEFT JOIN equipes e ON e.id = me.equipe_id
  WHERE NOT me.deletado AND me.criado_em >= p_desde
  GROUP BY me.criado_por, u.nome, e.nome
  ORDER BY COUNT(*) DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
-- RPC 4: Sugestões por equipe (para gráfico)
CREATE OR REPLACE FUNCTION melhorias_eproc_por_equipe(p_desde TIMESTAMPTZ DEFAULT now() - interval '30 days')
RETURNS TABLE(equipe_id UUID, equipe_nome TEXT, total BIGINT) AS $$
  SELECT me.equipe_id, e.nome, COUNT(*)
  FROM melhorias_eproc me
  LEFT JOIN equipes e ON e.id = me.equipe_id
  WHERE NOT me.deletado AND me.criado_em >= p_desde
  GROUP BY me.equipe_id, e.nome
  ORDER BY COUNT(*) DESC;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
-- RPC 5: Votar/Desvotar (toggle)
CREATE OR REPLACE FUNCTION melhorias_eproc_toggle_voto(p_melhoria_id UUID)
RETURNS JSON AS $$
DECLARE
  v_usuario_id UUID := auth.uid();
  v_existe BOOLEAN;
  v_novo_count INT;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM melhorias_eproc_votos
    WHERE melhoria_id = p_melhoria_id AND usuario_id = v_usuario_id
  ) INTO v_existe;

  IF v_existe THEN
    DELETE FROM melhorias_eproc_votos
    WHERE melhoria_id = p_melhoria_id AND usuario_id = v_usuario_id;
  ELSE
    INSERT INTO melhorias_eproc_votos (melhoria_id, usuario_id)
    VALUES (p_melhoria_id, v_usuario_id);
  END IF;

  SELECT votos_count INTO v_novo_count
  FROM melhorias_eproc WHERE id = p_melhoria_id;

  RETURN json_build_object(
    'votou', NOT v_existe,
    'votos_count', v_novo_count
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- RPC 6: Criar comentário com notificações automáticas
CREATE OR REPLACE FUNCTION melhorias_eproc_criar_comentario(
  p_melhoria_id UUID,
  p_conteudo TEXT,
  p_mencoes UUID[] DEFAULT '{}'
)
RETURNS UUID AS $$
DECLARE
  v_comentario_id UUID;
  v_autor_melhoria UUID;
  v_autor_id UUID := auth.uid();
  v_mencao UUID;
BEGIN
  INSERT INTO melhorias_eproc_comentarios (melhoria_id, autor_id, conteudo)
  VALUES (p_melhoria_id, v_autor_id, p_conteudo)
  RETURNING id INTO v_comentario_id;

  SELECT criado_por INTO v_autor_melhoria
  FROM melhorias_eproc WHERE id = p_melhoria_id;

  -- Notificar autor da sugestão (se não é ele comentando)
  IF v_autor_melhoria IS DISTINCT FROM v_autor_id THEN
    INSERT INTO melhorias_eproc_notificacoes (melhoria_id, comentario_id, destinatario_id, remetente_id, tipo, dados)
    VALUES (p_melhoria_id, v_comentario_id, v_autor_melhoria, v_autor_id, 'comentario',
      jsonb_build_object('preview', left(p_conteudo, 100)));
  END IF;

  -- Processar menções
  FOREACH v_mencao IN ARRAY p_mencoes LOOP
    INSERT INTO melhorias_eproc_mencoes (melhoria_id, comentario_id, usuario_mencionado_id, mencionado_por_id)
    VALUES (p_melhoria_id, v_comentario_id, v_mencao, v_autor_id);

    IF v_mencao IS DISTINCT FROM v_autor_melhoria AND v_mencao IS DISTINCT FROM v_autor_id THEN
      INSERT INTO melhorias_eproc_notificacoes (melhoria_id, comentario_id, destinatario_id, remetente_id, tipo, dados)
      VALUES (p_melhoria_id, v_comentario_id, v_mencao, v_autor_id, 'mencao',
        jsonb_build_object('preview', left(p_conteudo, 100)));
    END IF;
  END LOOP;

  RETURN v_comentario_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
-- RPC 7: Listar comentários
CREATE OR REPLACE FUNCTION melhorias_eproc_listar_comentarios(p_melhoria_id UUID)
RETURNS TABLE(id UUID, autor_id UUID, autor_nome TEXT, conteudo TEXT, criado_em TIMESTAMPTZ) AS $$
  SELECT c.id, c.autor_id, u.nome, c.conteudo, c.criado_em
  FROM melhorias_eproc_comentarios c
  JOIN users u ON u.id = c.autor_id
  WHERE c.melhoria_id = p_melhoria_id
  ORDER BY c.criado_em ASC;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
-- RPC 8: Notificações não lidas
CREATE OR REPLACE FUNCTION melhorias_eproc_notificacoes_nao_lidas()
RETURNS TABLE(id UUID, melhoria_id UUID, tipo TEXT, dados JSONB, remetente_nome TEXT, criado_em TIMESTAMPTZ) AS $$
  SELECT n.id, n.melhoria_id, n.tipo, n.dados, u.nome, n.criado_em
  FROM melhorias_eproc_notificacoes n
  LEFT JOIN users u ON u.id = n.remetente_id
  WHERE n.destinatario_id = auth.uid() AND NOT n.lida
  ORDER BY n.criado_em DESC;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
-- RPC 9: Marcar notificações como lidas
CREATE OR REPLACE FUNCTION melhorias_eproc_marcar_notificacoes_lidas(p_ids UUID[])
RETURNS void AS $$
  UPDATE melhorias_eproc_notificacoes
  SET lida = true, lida_em = now()
  WHERE id = ANY(p_ids) AND destinatario_id = auth.uid();
$$ LANGUAGE sql SECURITY DEFINER;
-- RPC 10: Sugestões mais votadas (ranking)
CREATE OR REPLACE FUNCTION melhorias_eproc_mais_votadas(p_limit INT DEFAULT 10)
RETURNS TABLE(id UUID, titulo TEXT, tipo TEXT, votos_count INT, status TEXT, criador_nome TEXT) AS $$
  SELECT me.id, me.titulo, me.tipo, me.votos_count, me.status, u.nome
  FROM melhorias_eproc me
  JOIN users u ON u.id = me.criado_por
  WHERE NOT me.deletado AND me.status NOT IN ('rejeitada', 'implementada')
  ORDER BY me.votos_count DESC, me.criado_em DESC
  LIMIT p_limit;
$$ LANGUAGE sql STABLE SECURITY DEFINER;
-- ============================================================
-- 5. REALTIME
-- ============================================================

ALTER PUBLICATION supabase_realtime ADD TABLE melhorias_eproc_comentarios;

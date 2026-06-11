-- ============================================================================
-- Visibilidade de Escalações N3 e Chamados Globais por equipe selecionada
-- ============================================================================
-- Contexto: hoje as RLS policies dessas tabelas filtram por users.equipe_id
-- (equipe primária do usuário), o que impede que coordenadores/admins/qualquer
-- usuário vejam o conteúdo ao trocar de equipe via seletor.
--
-- Solução adotada (opção 3 — alinhamento com tickets): relaxar as policies para
-- qualquer usuário autenticado. O frontend (hooks useEscalacoesN3 e
-- useChamadosGlobais) já filtra por equipeId vindo do AuthContext, que reflete
-- a equipe selecionada via EquipeSelectorPage.
--
-- Tabelas afetadas:
--   - escalacoes_n3
--   - escalacao_n3_retornos
--   - escalacoes_n3_vinculos
--   - chamados_globais
--   - tickets_globais
--   - chamados_globais_vinculos
--
-- Operações DELETE em escalacoes_n3 e chamados_globais mantêm a regra
-- "apenas o criador (e admin para globais)" por questão de auditoria.
-- ============================================================================

BEGIN;
-- ---------------------------------------------------------------------------
-- escalacoes_n3
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "escalacoes_n3_select_equipe"  ON public.escalacoes_n3;
DROP POLICY IF EXISTS "escalacoes_n3_update_equipe"  ON public.escalacoes_n3;
CREATE POLICY "escalacoes_n3_select_authenticated"
  ON public.escalacoes_n3
  FOR SELECT
  TO authenticated
  USING (true);
CREATE POLICY "escalacoes_n3_update_authenticated"
  ON public.escalacoes_n3
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
DROP POLICY IF EXISTS "escalacoes_n3_insert_equipe" ON public.escalacoes_n3;
CREATE POLICY "escalacoes_n3_insert_authenticated"
  ON public.escalacoes_n3
  FOR INSERT
  TO authenticated
  WITH CHECK (criado_por = auth.uid());
-- DELETE permanece restrito ao criador.

-- ---------------------------------------------------------------------------
-- escalacao_n3_retornos
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Usuarios veem retornos da equipe"      ON public.escalacao_n3_retornos;
DROP POLICY IF EXISTS "Usuarios atualizam retornos da equipe" ON public.escalacao_n3_retornos;
DROP POLICY IF EXISTS "Usuarios deletam retornos da equipe"   ON public.escalacao_n3_retornos;
CREATE POLICY "escalacao_n3_retornos_select_authenticated"
  ON public.escalacao_n3_retornos
  FOR SELECT
  TO authenticated
  USING (true);
CREATE POLICY "escalacao_n3_retornos_update_authenticated"
  ON public.escalacao_n3_retornos
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
CREATE POLICY "escalacao_n3_retornos_delete_authenticated"
  ON public.escalacao_n3_retornos
  FOR DELETE
  TO authenticated
  USING (true);
DROP POLICY IF EXISTS "Usuarios criam retornos na equipe" ON public.escalacao_n3_retornos;
CREATE POLICY "escalacao_n3_retornos_insert_authenticated"
  ON public.escalacao_n3_retornos
  FOR INSERT
  TO authenticated
  WITH CHECK (true);
-- ---------------------------------------------------------------------------
-- escalacoes_n3_vinculos
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Usuarios veem vinculos da equipe"             ON public.escalacoes_n3_vinculos;
DROP POLICY IF EXISTS "Membros da equipe podem remover vinculos"     ON public.escalacoes_n3_vinculos;
CREATE POLICY "escalacoes_n3_vinculos_select_authenticated"
  ON public.escalacoes_n3_vinculos
  FOR SELECT
  TO authenticated
  USING (true);
CREATE POLICY "escalacoes_n3_vinculos_delete_authenticated"
  ON public.escalacoes_n3_vinculos
  FOR DELETE
  TO authenticated
  USING (true);
DROP POLICY IF EXISTS "Usuarios criam vinculos entre escalacoes da equipe" ON public.escalacoes_n3_vinculos;
CREATE POLICY "escalacoes_n3_vinculos_insert_authenticated"
  ON public.escalacoes_n3_vinculos
  FOR INSERT
  TO authenticated
  WITH CHECK (criado_por = auth.uid());
-- ---------------------------------------------------------------------------
-- chamados_globais
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Usuarios veem globais da equipe"       ON public.chamados_globais;
DROP POLICY IF EXISTS "Usuarios podem atualizar globais"      ON public.chamados_globais;
CREATE POLICY "chamados_globais_select_authenticated"
  ON public.chamados_globais
  FOR SELECT
  TO authenticated
  USING (true);
CREATE POLICY "chamados_globais_update_authenticated"
  ON public.chamados_globais
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
-- DELETE permanece restrito ao criador OU admin.

DROP POLICY IF EXISTS "Usuarios podem criar globais" ON public.chamados_globais;
CREATE POLICY "chamados_globais_insert_authenticated"
  ON public.chamados_globais
  FOR INSERT
  TO authenticated
  WITH CHECK (criado_por = auth.uid());
-- ---------------------------------------------------------------------------
-- tickets_globais
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Usuarios veem tickets_globais da equipe"      ON public.tickets_globais;
DROP POLICY IF EXISTS "Usuarios podem atualizar tickets_globais"     ON public.tickets_globais;
CREATE POLICY "tickets_globais_select_authenticated"
  ON public.tickets_globais
  FOR SELECT
  TO authenticated
  USING (true);
CREATE POLICY "tickets_globais_update_authenticated"
  ON public.tickets_globais
  FOR UPDATE
  TO authenticated
  USING (true)
  WITH CHECK (true);
-- DELETE inalterado (anexado_por OU criador do global).

DROP POLICY IF EXISTS "Usuarios podem anexar tickets" ON public.tickets_globais;
CREATE POLICY "tickets_globais_insert_authenticated"
  ON public.tickets_globais
  FOR INSERT
  TO authenticated
  WITH CHECK (anexado_por = auth.uid());
-- ---------------------------------------------------------------------------
-- chamados_globais_vinculos
-- ---------------------------------------------------------------------------
DROP POLICY IF EXISTS "Usuarios veem vinculos de globais da equipe"        ON public.chamados_globais_vinculos;
DROP POLICY IF EXISTS "Membros da equipe podem remover vinculos de globais" ON public.chamados_globais_vinculos;
CREATE POLICY "chamados_globais_vinculos_select_authenticated"
  ON public.chamados_globais_vinculos
  FOR SELECT
  TO authenticated
  USING (true);
CREATE POLICY "chamados_globais_vinculos_delete_authenticated"
  ON public.chamados_globais_vinculos
  FOR DELETE
  TO authenticated
  USING (true);
DROP POLICY IF EXISTS "Usuarios criam vinculos entre globais da equipe" ON public.chamados_globais_vinculos;
CREATE POLICY "chamados_globais_vinculos_insert_authenticated"
  ON public.chamados_globais_vinculos
  FOR INSERT
  TO authenticated
  WITH CHECK (criado_por = auth.uid());
COMMIT;

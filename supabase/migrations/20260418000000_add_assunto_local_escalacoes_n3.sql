-- =====================================================
-- MIGRATION: Adicionar campos assunto e local_tramitacao
-- Tabela: escalacoes_n3
-- Data: 2026-04-18
-- =====================================================

-- 1. Novo campo: assunto (texto livre, opcional)
ALTER TABLE escalacoes_n3 ADD COLUMN IF NOT EXISTS assunto text;
-- 2. Novo campo: local_tramitacao (setor onde o ticket tramita)
ALTER TABLE escalacoes_n3 ADD COLUMN IF NOT EXISTS local_tramitacao text;
-- 3. Constraint CHECK para valores válidos de local_tramitacao
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'chk_escalacoes_n3_local_tramitacao'
  ) THEN
    ALTER TABLE escalacoes_n3
      ADD CONSTRAINT chk_escalacoes_n3_local_tramitacao
      CHECK (local_tramitacao IS NULL OR local_tramitacao IN ('STI', 'SGS 3', 'SPI'));
  END IF;
END $$;
-- 4. Índices para filtros rápidos
CREATE INDEX IF NOT EXISTS idx_escalacoes_n3_assunto ON escalacoes_n3(assunto) WHERE assunto IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_escalacoes_n3_local_tramitacao ON escalacoes_n3(local_tramitacao) WHERE local_tramitacao IS NOT NULL;
-- 5. Comentários
COMMENT ON COLUMN escalacoes_n3.assunto IS 'Assunto/tema do ticket escalado (texto livre, opcional)';
COMMENT ON COLUMN escalacoes_n3.local_tramitacao IS 'Setor onde o ticket está tramitando: STI, SGS 3 ou SPI';

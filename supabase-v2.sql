-- ═══════════════════════════════════════════════════════════
-- NUNTIO LEGAL OS — v2 Schema
-- Nuevas tablas para multi-rol + registro de contratos
-- NO modifica las tablas de v1 (nuntio_sessions, etc.)
-- Ejecutar en: Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- ─── 1. EMPRESAS ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nuntio_companies (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  created_by TEXT NOT NULL,  -- auth.uid() del owner fundador
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE nuntio_companies ENABLE ROW LEVEL SECURITY;

-- Ver la empresa si eres miembro
CREATE POLICY "Company members view" ON nuntio_companies
  FOR SELECT USING (
    id IN (
      SELECT company_id FROM nuntio_user_roles
      WHERE user_id = auth.uid()::text
    )
  );

-- Solo el creador puede insertar
CREATE POLICY "Owner creates company" ON nuntio_companies
  FOR INSERT WITH CHECK (created_by = auth.uid()::text);

-- Solo el owner puede actualizar
CREATE POLICY "Owner updates company" ON nuntio_companies
  FOR UPDATE USING (created_by = auth.uid()::text);

-- ─── 2. ROLES DE USUARIO ────────────────────────────────────
CREATE TABLE IF NOT EXISTS nuntio_user_roles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID REFERENCES nuntio_companies(id) ON DELETE CASCADE NOT NULL,
  user_id TEXT NOT NULL,      -- auth.uid()
  role TEXT NOT NULL CHECK (role IN ('owner', 'legal', 'investor')),
  email TEXT,                 -- para mostrar en la UI
  invited_by TEXT,            -- auth.uid() del que invitó
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(company_id, user_id)
);

ALTER TABLE nuntio_user_roles ENABLE ROW LEVEL SECURITY;

-- Cualquier miembro ve los roles de su empresa
CREATE POLICY "Members view team" ON nuntio_user_roles
  FOR SELECT USING (
    company_id IN (
      SELECT company_id FROM nuntio_user_roles
      WHERE user_id = auth.uid()::text
    )
  );

-- Solo owner puede gestionar roles (INSERT/UPDATE/DELETE)
CREATE POLICY "Owner manages roles" ON nuntio_user_roles
  FOR ALL USING (
    company_id IN (
      SELECT company_id FROM nuntio_user_roles
      WHERE user_id = auth.uid()::text AND role = 'owner'
    )
  )
  WITH CHECK (
    company_id IN (
      SELECT company_id FROM nuntio_user_roles
      WHERE user_id = auth.uid()::text AND role = 'owner'
    )
  );

-- El propio usuario puede insertar su propio rol (para el setup inicial de owner)
CREATE POLICY "Self insert role" ON nuntio_user_roles
  FOR INSERT WITH CHECK (user_id = auth.uid()::text);

-- ─── 3. CONTRATOS ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS nuntio_contracts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  company_id UUID REFERENCES nuntio_companies(id) ON DELETE CASCADE NOT NULL,
  title TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN (
    'fundadores', 'inversion', 'operaciones', 'empleo', 'ip', 'nda', 'otro'
  )),
  status TEXT DEFAULT 'draft' CHECK (status IN (
    'draft', 'pending_signature', 'active', 'signed', 'expired', 'terminated'
  )),
  parties JSONB DEFAULT '[]',           -- [{name, role, email, signed_at}]
  description TEXT,
  document_content TEXT,                -- cuerpo del contrato (texto)
  storage_path TEXT,                    -- PDF subido a Supabase Storage
  visible_to_investors BOOLEAN DEFAULT false,
  visible_to_legal BOOLEAN DEFAULT true,
  task_ref TEXT,                        -- referencia a task v1 (e.g. 'sha', 'ipa')
  signed_date DATE,
  expiry_date DATE,
  value_eur NUMERIC,                    -- valor económico si aplica
  currency TEXT DEFAULT 'EUR',
  notes TEXT,                           -- notas internas
  created_by TEXT NOT NULL,             -- auth.uid()
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_contracts_company ON nuntio_contracts(company_id);
CREATE INDEX IF NOT EXISTS idx_contracts_type ON nuntio_contracts(company_id, type);
CREATE INDEX IF NOT EXISTS idx_contracts_status ON nuntio_contracts(company_id, status);

ALTER TABLE nuntio_contracts ENABLE ROW LEVEL SECURITY;

-- SELECT: owner ve todo; legal ve visible_to_legal; investor ve visible_to_investors
CREATE POLICY "Contract read by role" ON nuntio_contracts
  FOR SELECT USING (
    company_id IN (
      SELECT company_id FROM nuntio_user_roles
      WHERE user_id = auth.uid()::text
      AND (
        role = 'owner'
        OR (role = 'legal' AND visible_to_legal = true)
        OR (role = 'investor' AND visible_to_investors = true)
      )
    )
  );

-- INSERT/UPDATE/DELETE: solo owner
CREATE POLICY "Owner manages contracts" ON nuntio_contracts
  FOR ALL USING (
    company_id IN (
      SELECT company_id FROM nuntio_user_roles
      WHERE user_id = auth.uid()::text AND role = 'owner'
    )
  )
  WITH CHECK (
    company_id IN (
      SELECT company_id FROM nuntio_user_roles
      WHERE user_id = auth.uid()::text AND role = 'owner'
    )
  );

-- ─── 4. TRIGGER updated_at en contratos ─────────────────────
CREATE OR REPLACE FUNCTION update_contract_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS contracts_updated_at ON nuntio_contracts;
CREATE TRIGGER contracts_updated_at
  BEFORE UPDATE ON nuntio_contracts
  FOR EACH ROW EXECUTE FUNCTION update_contract_updated_at();

-- ─── 5. STORAGE POLICY para nuntio-documents (contratos) ────
-- Misma política que v1 pero también aplica a contratos
-- Ya debería existir el bucket 'nuntio-documents' de v1

-- ─── 6. Índice de relación v1→v2 ────────────────────────────
-- Para migrar datos de v1 (nuntio_sessions.session_id) a v2 (company_id)
-- El owner puede hacer esto manualmente o vía una función de migración
-- Las tablas v1 siguen funcionando independientemente

-- ═══════════════════════════════════════════════════════════
-- ✅ LISTO.
-- Post-instalación:
--   1. El primer usuario que haga login verá el modal de setup de empresa
--   2. El owner puede invitar a legal/investor desde la vista Equipo
--   3. Invitar usuarios: Supabase Dashboard → Authentication → Users → Invite
-- ═══════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════
-- NUNTIO LEGAL OS — Supabase Schema
-- Ejecuta esto en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- 1. Tabla de sesiones/usuarios (sin auth por ahora, basado en session_id)
CREATE TABLE IF NOT EXISTS nuntio_sessions (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT UNIQUE NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- 2. Tabla de tareas completadas
CREATE TABLE IF NOT EXISTS nuntio_completed (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES nuntio_sessions(session_id) ON DELETE CASCADE,
  task_id TEXT NOT NULL,
  completed_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(session_id, task_id)
);

-- 3. Tabla de datos de formularios (cada campo guardado)
CREATE TABLE IF NOT EXISTS nuntio_form_data (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES nuntio_sessions(session_id) ON DELETE CASCADE,
  task_id TEXT NOT NULL,
  field_id TEXT NOT NULL,
  value TEXT,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(session_id, task_id, field_id)
);

-- 4. Tabla de documentos generados
CREATE TABLE IF NOT EXISTS nuntio_documents (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES nuntio_sessions(session_id) ON DELETE CASCADE,
  task_id TEXT NOT NULL,
  document_content TEXT,
  generated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(session_id, task_id)
);

-- 5. Tabla de solicitudes de firma
CREATE TABLE IF NOT EXISTS nuntio_signatures (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES nuntio_sessions(session_id) ON DELETE CASCADE,
  task_id TEXT NOT NULL,
  signer_name TEXT NOT NULL,
  signer_email TEXT NOT NULL,
  sign_token TEXT UNIQUE DEFAULT encode(gen_random_bytes(16), 'hex'),
  status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'signed')),
  sent_at TIMESTAMP WITH TIME ZONE,
  signed_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ═══════════════════════════════════════════════════════════
-- ÍNDICES para velocidad
-- ═══════════════════════════════════════════════════════════

CREATE INDEX IF NOT EXISTS idx_completed_session ON nuntio_completed(session_id);
CREATE INDEX IF NOT EXISTS idx_formdata_session_task ON nuntio_form_data(session_id, task_id);
CREATE INDEX IF NOT EXISTS idx_signatures_token ON nuntio_signatures(sign_token);
CREATE INDEX IF NOT EXISTS idx_signatures_session ON nuntio_signatures(session_id);

-- ═══════════════════════════════════════════════════════════
-- ROW LEVEL SECURITY (importante para producción)
-- ═══════════════════════════════════════════════════════════

ALTER TABLE nuntio_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_completed ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_form_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_signatures ENABLE ROW LEVEL SECURITY;

-- Políticas: cualquiera puede leer/escribir sus propios datos por session_id
-- (En producción, cambiar a auth.uid() cuando añadas autenticación)

CREATE POLICY "Allow all on sessions" ON nuntio_sessions FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on completed" ON nuntio_completed FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on form_data" ON nuntio_form_data FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on documents" ON nuntio_documents FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Allow all on signatures" ON nuntio_signatures FOR ALL USING (true) WITH CHECK (true);

-- ═══════════════════════════════════════════════════════════
-- FUNCIÓN para actualizar updated_at automáticamente
-- ═══════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_sessions_updated_at
  BEFORE UPDATE ON nuntio_sessions
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER update_formdata_updated_at
  BEFORE UPDATE ON nuntio_form_data
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════════════════════════
-- ✅ LISTO. Ahora pega tu SUPABASE_URL y ANON_KEY en el HTML
-- ═══════════════════════════════════════════════════════════

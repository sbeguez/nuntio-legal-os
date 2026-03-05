-- ═══════════════════════════════════════════════════════════
-- NUNTIO LEGAL OS — Supabase Schema
-- Ejecuta esto en Supabase SQL Editor
-- ═══════════════════════════════════════════════════════════

-- 1. Tabla de sesiones/usuarios (session_id = auth.uid() del usuario autenticado)
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
-- ROW LEVEL SECURITY
-- ═══════════════════════════════════════════════════════════

ALTER TABLE nuntio_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_completed ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_form_data ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE nuntio_signatures ENABLE ROW LEVEL SECURITY;

-- Políticas: cada usuario solo accede a sus propios datos (session_id = auth.uid())
-- Requiere autenticación Supabase Auth (email + password)

CREATE POLICY "Own sessions" ON nuntio_sessions
  FOR ALL USING (session_id = auth.uid()::text)
  WITH CHECK (session_id = auth.uid()::text);

CREATE POLICY "Own completed" ON nuntio_completed
  FOR ALL USING (session_id = auth.uid()::text)
  WITH CHECK (session_id = auth.uid()::text);

CREATE POLICY "Own form_data" ON nuntio_form_data
  FOR ALL USING (session_id = auth.uid()::text)
  WITH CHECK (session_id = auth.uid()::text);

CREATE POLICY "Own documents" ON nuntio_documents
  FOR ALL USING (session_id = auth.uid()::text)
  WITH CHECK (session_id = auth.uid()::text);

CREATE POLICY "Own signatures" ON nuntio_signatures
  FOR ALL USING (session_id = auth.uid()::text)
  WITH CHECK (session_id = auth.uid()::text);

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
-- 6. Tabla de archivos del Data Room (documentos subidos)
-- ═══════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS nuntio_files (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  session_id TEXT NOT NULL REFERENCES nuntio_sessions(session_id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  task_id TEXT,                         -- tarea relacionada (nullable)
  category TEXT NOT NULL DEFAULT 'uploaded'
    CHECK (category IN ('signed', 'generated', 'uploaded')),
  storage_path TEXT NOT NULL,           -- ruta en Supabase Storage
  size BIGINT DEFAULT 0,
  mime_type TEXT DEFAULT 'application/octet-stream',
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  UNIQUE(session_id, storage_path)
);

CREATE INDEX IF NOT EXISTS idx_files_session ON nuntio_files(session_id);
CREATE INDEX IF NOT EXISTS idx_files_task ON nuntio_files(session_id, task_id);

ALTER TABLE nuntio_files ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Own files" ON nuntio_files
  FOR ALL USING (session_id = auth.uid()::text)
  WITH CHECK (session_id = auth.uid()::text);

-- ═══════════════════════════════════════════════════════════
-- 7. Supabase Storage — bucket "nuntio-documents"
--    EJECUTAR EN SUPABASE DASHBOARD → Storage
-- ═══════════════════════════════════════════════════════════
-- INSTRUCCIONES MANUALES (no se pueden hacer por SQL):
--   1. Ir a Storage → "New bucket"
--   2. Nombre: nuntio-documents
--   3. Public: NO (privado)
--   4. File size limit: 10MB
--   5. Allowed MIME types: dejar vacío (acepta todos)
--
-- Luego, en Storage → Policies → nuntio-documents, crear:

-- Política INSERT (subir archivos propios):
CREATE POLICY "Users upload own files"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'nuntio-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Política SELECT (ver/descargar archivos propios):
CREATE POLICY "Users view own files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'nuntio-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Política DELETE (eliminar archivos propios):
CREATE POLICY "Users delete own files"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'nuntio-documents'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ═══════════════════════════════════════════════════════════
-- ✅ LISTO.
-- IMPORTANTE post-instalación en Supabase Dashboard:
--   1. Authentication > Settings > desactivar "Enable Signups"
--   2. Authentication > Users > "Invite user" para crear cuentas de acceso
--   3. Storage > New Bucket > nombre: nuntio-documents, Public: NO
--   4. Storage > Policies > aplicar las 3 políticas de arriba
-- ═══════════════════════════════════════════════════════════

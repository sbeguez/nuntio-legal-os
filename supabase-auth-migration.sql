-- ═══════════════════════════════════════════════════════════
-- NUNTIO LEGAL OS — Migración: Activar Auth con RLS
-- Ejecuta esto en Supabase Dashboard > SQL Editor
-- ═══════════════════════════════════════════════════════════

-- 1. Eliminar políticas antiguas (sin auth)
DROP POLICY IF EXISTS "Allow all on sessions"   ON nuntio_sessions;
DROP POLICY IF EXISTS "Allow all on completed"  ON nuntio_completed;
DROP POLICY IF EXISTS "Allow all on form_data"  ON nuntio_form_data;
DROP POLICY IF EXISTS "Allow all on documents"  ON nuntio_documents;
DROP POLICY IF EXISTS "Allow all on signatures" ON nuntio_signatures;

-- 2. Crear políticas nuevas (cada usuario solo ve sus datos)
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

-- ✅ Listo. Ahora en Authentication > Settings desactiva "Enable Signups"
-- y crea usuarios en Authentication > Users > "Invite user"

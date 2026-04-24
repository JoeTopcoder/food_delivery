-- AI Voice Sessions table
-- Stores AI voice assistant interactions per user for analytics + audit

CREATE TABLE IF NOT EXISTS ai_voice_sessions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role            TEXT NOT NULL CHECK (role IN ('customer', 'driver', 'admin')),
  order_id        UUID REFERENCES orders(id) ON DELETE SET NULL,
  user_message    TEXT NOT NULL,
  ai_response     TEXT NOT NULL,
  tokens_used     INTEGER NOT NULL DEFAULT 0,
  language        TEXT NOT NULL DEFAULT 'en',
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for per-user history queries
CREATE INDEX IF NOT EXISTS idx_ai_voice_sessions_user_id
  ON ai_voice_sessions(user_id, created_at DESC);

-- RLS: users can only see their own sessions; admins see all
ALTER TABLE ai_voice_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own AI sessions"
  ON ai_voice_sessions FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Service role full access"
  ON ai_voice_sessions FOR ALL
  USING (true)
  WITH CHECK (true);

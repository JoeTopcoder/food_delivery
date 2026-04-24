-- AI Intent Tracking upgrade
-- Adds intent classification + computed ETA to ai_voice_sessions

ALTER TABLE ai_voice_sessions
  ADD COLUMN IF NOT EXISTS intent TEXT,
  ADD COLUMN IF NOT EXISTS eta_minutes INTEGER;

-- Index for analytics: which intents are most common
CREATE INDEX IF NOT EXISTS idx_ai_voice_sessions_intent
  ON ai_voice_sessions(intent)
  WHERE intent IS NOT NULL;

-- Index for self-improvement queries: find unanswered/fallback sessions
CREATE INDEX IF NOT EXISTS idx_ai_voice_sessions_role_intent
  ON ai_voice_sessions(role, intent, created_at DESC);

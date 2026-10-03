-- Restaurant Pickup Coordinator — give the AI its own account to place Agora
-- voice calls to restaurants through the existing in-app call system.
-- The AI account is the caller_id on the `calls` row; the restaurant owner is
-- the receiver and is rung via send-call-notification; the AI voice bot joins
-- the same Agora channel via agora-ai-agent.

-- 1. The AI's account (idempotent by a fixed internal email). role='user' →
--    lowest privilege; it has no auth credentials and is never logged into.
INSERT INTO users (id, email, name, role)
SELECT gen_random_uuid(), 'ai-pickup@hotbite.internal', 'HotBite Assistant', 'user'
WHERE NOT EXISTS (SELECT 1 FROM users WHERE email = 'ai-pickup@hotbite.internal');

-- 2. Publish its id for the engine/edge function.
INSERT INTO app_config (key, value)
VALUES ('pickup_ai_account_id',
        (SELECT id::text FROM users WHERE email = 'ai-pickup@hotbite.internal'))
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- 3. Link the pickup call to its Agora call + channel + bot.
ALTER TABLE public.restaurant_pickup_calls
  ADD COLUMN IF NOT EXISTS channel_name  text,
  ADD COLUMN IF NOT EXISTS agora_call_id uuid,
  ADD COLUMN IF NOT EXISTS agent_id      text;

NOTIFY pgrst, 'reload schema';

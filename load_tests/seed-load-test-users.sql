-- =============================================================================
-- LOAD TEST USER SEED  —  seed-load-test-users.sql
-- Creates 200 Supabase auth users for Artillery load testing.
--
-- HOW TO RUN:
--   Supabase Dashboard → SQL Editor → paste this file → Run
--
-- ⚠️  NEVER run against production.  These are synthetic test accounts.
--     They are tagged with  is_load_test = true  for easy cleanup.
--
-- Users created:
--   loadtest_001@test.mealhub.dev  …  loadtest_200@test.mealhub.dev
-- Password (all users):
--   LoadTest123!Secure
-- =============================================================================

DO $$
DECLARE
  i         INTEGER;
  v_email   TEXT;
  v_uid     UUID;
  -- Hash the password ONCE and reuse.  bcrypt embeds its own salt inside the
  -- stored string, so verification still works when multiple users share the
  -- same hash.  This turns a ~20-second loop into a ~0.1-second loop.
  v_hashed  TEXT := crypt('LoadTest123!Secure', gen_salt('bf', 10));
BEGIN

  FOR i IN 1..200 LOOP
    v_uid   := gen_random_uuid();
    v_email := 'loadtest_' || lpad(i::text, 3, '0') || '@test.mealhub.dev';

    -- Insert into Supabase auth.users.
    -- The handle_new_auth_user trigger fires per-row and creates the
    -- matching public.users record automatically.
    INSERT INTO auth.users (
      id, instance_id, aud, role,
      email, encrypted_password,
      email_confirmed_at, created_at, updated_at,
      raw_app_meta_data, raw_user_meta_data,
      is_super_admin
    ) VALUES (
      v_uid,
      '00000000-0000-0000-0000-000000000000',
      'authenticated',
      'authenticated',
      v_email,
      v_hashed,
      NOW(), NOW(), NOW(),
      '{"provider":"email","providers":["email"],"is_load_test":true}'::jsonb,
      '{"name":"Load Test User","role":"customer","is_load_test":true}'::jsonb,
      false
    )
    ON CONFLICT (email) DO NOTHING;  -- idempotent: safe to re-run

  END LOOP;

  -- Patch public.users to use the correct role.
  -- The trigger maps 'customer' → 'user' so we do a bulk UPDATE here,
  -- exactly as migration 120 does for the test-customer account.
  UPDATE public.users
  SET
    role       = 'customer',
    address    = 'George Town, Grand Cayman',
    latitude   = 19.2869,
    longitude  = -81.3674,
    updated_at = NOW()
  WHERE email LIKE 'loadtest\_%@test.mealhub.dev' ESCAPE '\';

  RAISE NOTICE '✅  Load test users seeded (up to 200). Re-running is safe (ON CONFLICT DO NOTHING).';
END $$;

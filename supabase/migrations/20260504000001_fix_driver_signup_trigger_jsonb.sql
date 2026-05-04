-- Migration: fix driver signup trigger
-- The handle_new_auth_user trigger was inserting documents_status='pending'
-- (TEXT) into drivers.documents_status which is JSONB. That type-cast
-- failure aborted the entire auth.users insert with "Database error
-- saving new user" — the UI shows this as "Something went wrong".
--
-- Fix: omit documents_status so the column default ('{...pending...}'::jsonb)
-- is used, and make the drivers bootstrap fully tolerant so any future
-- mismatch will not block auth signup.

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _role TEXT;
  _name TEXT;
BEGIN
  _role := COALESCE(NEW.raw_user_meta_data->>'role', 'customer');
  _name := COALESCE(NEW.raw_user_meta_data->>'name', '');

  -- Map legacy 'user' → 'customer' to satisfy the role constraint.
  IF _role = 'user' THEN
    _role := 'customer';
  END IF;

  IF _role NOT IN ('customer', 'driver', 'restaurant', 'admin') THEN
    _role := 'customer';
  END IF;

  BEGIN
    INSERT INTO public.users (id, email, name, role, is_active, created_at, updated_at)
    VALUES (
      NEW.id,
      COALESCE(NEW.email, NEW.id || '@otp.fooddriver.app'),
      _name,
      _role,
      TRUE,
      NOW(),
      NOW()
    )
    ON CONFLICT (id) DO UPDATE
      SET
        email      = EXCLUDED.email,
        name       = CASE WHEN EXCLUDED.name = '' THEN users.name ELSE EXCLUDED.name END,
        role       = EXCLUDED.role,
        updated_at = NOW();
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'handle_new_auth_user: users upsert failed: %', SQLERRM;
  END;

  IF _role = 'driver' THEN
    BEGIN
      -- Omit documents_status so the JSONB column default applies.
      INSERT INTO public.drivers (user_id, is_available, created_at, updated_at)
      VALUES (NEW.id, FALSE, NOW(), NOW())
      ON CONFLICT (user_id) DO NOTHING;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'handle_new_auth_user: drivers bootstrap failed: %', SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

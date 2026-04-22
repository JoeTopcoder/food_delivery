-- Migration 104: Auto-create user profiles via trigger
-- Fixes: RLS prevents profile creation during signup (no session yet).
-- This trigger runs as SECURITY DEFINER (bypasses RLS) and auto-creates
-- the users row immediately when a new auth.users row is inserted.

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
  -- Read role and name from auth metadata (set during signUp)
  _role := COALESCE(NEW.raw_user_meta_data->>'role', 'user');
  _name := COALESCE(NEW.raw_user_meta_data->>'name', '');

  -- Map 'customer' → 'user' to satisfy the CHECK constraint
  IF _role = 'customer' THEN
    _role := 'user';
  END IF;

  -- Only allowed roles
  IF _role NOT IN ('user', 'driver', 'restaurant', 'admin') THEN
    _role := 'user';
  END IF;

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

  -- If the user is a driver, also bootstrap the drivers row
  IF _role = 'driver' THEN
    INSERT INTO public.drivers (user_id, is_available, documents_status, created_at, updated_at)
    VALUES (NEW.id, FALSE, 'pending', NOW(), NOW())
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

-- Drop existing trigger if present, then recreate
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW
  EXECUTE FUNCTION public.handle_new_auth_user();

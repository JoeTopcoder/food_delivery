-- Migration: align handle_new_auth_user trigger with the post-093 role
-- constraint, which allows ('customer','driver','restaurant','admin').
-- The previous trigger inserted role='user', which now violates the
-- constraint and breaks every signup.

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

  -- Map legacy 'user' → 'customer' to satisfy the constraint.
  IF _role = 'user' THEN
    _role := 'customer';
  END IF;

  IF _role NOT IN ('customer', 'driver', 'restaurant', 'admin') THEN
    _role := 'customer';
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

  IF _role = 'driver' THEN
    INSERT INTO public.drivers (user_id, is_available, documents_status, created_at, updated_at)
    VALUES (NEW.id, FALSE, 'pending', NOW(), NOW())
    ON CONFLICT (user_id) DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

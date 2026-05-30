-- Add service_provider to handle_new_auth_user trigger.
-- Previously the trigger's allowed-roles guard did not include service_provider,
-- so every service_provider signup was silently downgraded to 'customer'.
CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _role TEXT;
  _name TEXT;
BEGIN
  _role := COALESCE(NEW.raw_user_meta_data->>'role', 'customer');
  _name := COALESCE(NEW.raw_user_meta_data->>'name', '');

  IF _role = 'user' THEN
    _role := 'customer';
  END IF;

  IF _role NOT IN ('customer', 'driver', 'restaurant', 'admin', 'service_provider') THEN
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

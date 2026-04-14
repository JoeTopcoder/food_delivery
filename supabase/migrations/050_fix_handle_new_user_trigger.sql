-- Fix handle_new_user trigger: handle email conflicts when user switches
-- from email/password auth to Google/Apple social sign-in.
-- The old trigger only handled ON CONFLICT (id) but the public.users table
-- also has a UNIQUE constraint on email, causing sign-in to fail.
--
-- v2: Use DELETE + re-INSERT instead of UPDATE SET id, because updating the
-- primary key fails when other tables have FK references to it.

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, name, role, is_active, created_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'name', ''), 'User'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user'),
    true,
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    email = EXCLUDED.email,
    name = CASE
      WHEN public.users.name = '' OR public.users.name IS NULL
      THEN EXCLUDED.name
      ELSE public.users.name
    END;

  RETURN NEW;
EXCEPTION WHEN unique_violation THEN
  -- Email already exists under a different user id (orphaned row).
  -- This happens when a user was deleted from auth.users but their
  -- public.users row remained, then they sign up again.
  -- Delete the orphan (ON DELETE CASCADE cleans referencing tables),
  -- then re-insert with the new auth id.
  DELETE FROM public.users WHERE email = NEW.email AND id != NEW.id;

  INSERT INTO public.users (id, email, name, role, is_active, created_at)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'name', ''), 'User'),
    COALESCE(NEW.raw_user_meta_data->>'role', 'user'),
    true,
    NOW()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN NEW;
END;
$$;

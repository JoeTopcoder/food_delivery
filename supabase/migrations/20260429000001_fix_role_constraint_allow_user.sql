-- Fix: migration 093 changed the role constraint to allow 'customer' but not 'user',
-- breaking the trigger in migration 104 which inserts role='user'.
-- This migration restores 'user' as a valid role and converts any 'customer' rows back.

DO $$
BEGIN
  -- Drop the growth constraint that excluded 'user'
  IF EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'users_role_growth_check'
  ) THEN
    ALTER TABLE public.users DROP CONSTRAINT users_role_growth_check;
  END IF;

  -- Convert any leftover 'customer' role values back to 'user'
  UPDATE public.users SET role = 'user' WHERE role = 'customer';

  -- Drop the original unnamed check constraint if it exists (role_check auto-named)
  -- Recreate a single definitive constraint allowing 'user'
  ALTER TABLE public.users
    ADD CONSTRAINT users_role_growth_check
    CHECK (role IN ('user', 'driver', 'restaurant', 'admin'));
END $$;

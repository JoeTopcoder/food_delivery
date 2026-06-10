-- Add service_provider + laundry_provider to the users role constraint.
-- Also includes legacy 'user' role so existing rows are not violated.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_growth_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_growth_check
  CHECK (role = ANY (ARRAY[
    'user'::text,
    'customer'::text,
    'driver'::text,
    'restaurant'::text,
    'admin'::text,
    'service_provider'::text,
    'laundry_provider'::text
  ]));

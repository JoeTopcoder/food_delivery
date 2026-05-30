-- Add service_provider to the users role constraint.
-- Previously the constraint only allowed customer/driver/restaurant/admin,
-- causing all service_provider signups to fail with a check constraint violation.
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_growth_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_growth_check
  CHECK (role = ANY (ARRAY[
    'customer'::text,
    'driver'::text,
    'restaurant'::text,
    'admin'::text,
    'service_provider'::text
  ]));

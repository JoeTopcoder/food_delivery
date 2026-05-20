-- Migration: Driver application submit — belt-and-suspenders RLS fix
-- Ensures drivers can set their own driver_status to 'pending_review'
-- and that admin can query pending applications via the join on users.

-- Allow drivers to update their own driver_status (needed for submitApplication).
-- Migration 093 has drivers_self_read_write FOR ALL, but some projects may have
-- narrower policies. This ensures the submit path is never blocked.
DO $$ BEGIN
  CREATE POLICY "drivers_own_submit_application"
    ON public.drivers FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (
      user_id = auth.uid()
      AND driver_status IN ('draft', 'pending_review')
    );
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Grant admin SELECT on the users join used by pendingVerificationDriversProvider.
-- (admin already has admin_select_all_users — this is a no-op safety grant.)
DO $$ BEGIN
  CREATE POLICY "admin_select_all_users_for_driver_join"
    ON public.users FOR SELECT
    USING (EXISTS (
      SELECT 1 FROM public.users u WHERE u.id = auth.uid() AND u.role = 'admin'
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- Ensure driver_consents upsert works: add explicit upsert-safe policies
-- (INSERT + UPDATE are separate in migration 109; this covers any edge case).
DO $$ BEGIN
  CREATE POLICY "driver_consents_own_upsert"
    ON public.driver_consents FOR UPDATE
    USING (driver_id = (
      SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1
    ));
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- ============================================================================
-- Fix linter 0008 (rls_enabled_no_policy): 7 tables had RLS enabled but no
-- policies, so ALL client access was silently denied (service_role/postgres
-- still bypass). Add the correct policy per table. Writes remain
-- service/system-only everywhere (no client INSERT/UPDATE/DELETE policies).
-- ============================================================================

-- 1) admin_mfa_recovery_codes — service-role only (edge function). Keep it fully
--    locked to clients; an explicit deny satisfies the linter without exposing
--    the (hashed) recovery codes to anyone.
CREATE POLICY amrc_no_client_access ON public.admin_mfa_recovery_codes
  FOR ALL TO authenticated, anon
  USING (false) WITH CHECK (false);

-- 2) order_status_events — order timeline. Readable by the parties to the order
--    (customer, assigned driver, owning restaurant) and admins. Restores the
--    order_status_timeline widget, which was returning nothing under RLS.
CREATE POLICY ose_party_read ON public.order_status_events
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      WHERE o.id = order_status_events.order_id
        AND (
          o.user_id = auth.uid()
          OR o.driver_id = auth.uid()
          OR o.restaurant_id IN (
               SELECT r.id FROM public.restaurants r WHERE r.owner_id = auth.uid()
             )
        )
    )
    OR public.is_admin()
  );

-- 3) ratings — public aggregate rating stats per entity (safe to read widely).
CREATE POLICY ratings_public_read ON public.ratings
  FOR SELECT TO authenticated, anon
  USING (true);

-- 4) Internal / ops tables — admin-read only.
CREATE POLICY daily_targets_admin_read ON public.daily_targets
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY scheduled_job_runs_admin_read ON public.scheduled_job_runs
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY target_change_log_admin_read ON public.target_change_log
  FOR SELECT TO authenticated USING (public.is_admin());

CREATE POLICY restaurant_embeddings_admin_read ON public.restaurant_embeddings
  FOR SELECT TO authenticated USING (public.is_admin());

NOTIFY pgrst, 'reload schema';

-- HotBite DineOut — RLS. Config tables are publicly readable (needed for
-- discovery/availability); owners/admins manage their own; reservations and
-- payments are private to the guest, the owning restaurant, and admins. All
-- booking mutations go through SECURITY DEFINER RPCs (service path), so no broad
-- client INSERT/UPDATE policy on reservations is needed.

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'dineout_settings','dineout_tables','dineout_table_combinations','dineout_schedules',
    'dineout_exceptions','dineout_duration_rules','dineout_packages',
    'dineout_reservations','dineout_reservation_tables','dineout_status_history','dineout_payments'
  ] LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
  END LOOP;
END $$;

-- ── config tables: public SELECT + owner/admin manage ──────────────────────
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'dineout_settings','dineout_tables','dineout_table_combinations','dineout_schedules',
    'dineout_exceptions','dineout_duration_rules','dineout_packages'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_read', t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', t||'_manage', t);
    -- settings keys on restaurant_id (its PK); the rest have a restaurant_id col.
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR SELECT TO authenticated USING (true)$p$, t||'_read', t);
    EXECUTE format($p$CREATE POLICY %I ON public.%I FOR ALL TO authenticated
                      USING (public.current_user_owns_restaurant(restaurant_id) OR public.is_admin())
                      WITH CHECK (public.current_user_owns_restaurant(restaurant_id) OR public.is_admin())$p$,
                   t||'_manage', t);
    EXECUTE format('GRANT SELECT, INSERT, UPDATE, DELETE ON public.%I TO authenticated', t);
  END LOOP;
END $$;

-- ── reservations: guest sees own; owner/admin see their restaurant's ───────
DROP POLICY IF EXISTS dineout_res_read ON public.dineout_reservations;
DROP POLICY IF EXISTS dineout_res_owner_update ON public.dineout_reservations;
CREATE POLICY dineout_res_read ON public.dineout_reservations FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.current_user_owns_restaurant(restaurant_id) OR public.is_admin());
-- Owner/admin may update (staff ops also go through RPCs); guests cancel via RPC.
CREATE POLICY dineout_res_owner_update ON public.dineout_reservations FOR UPDATE TO authenticated
  USING (public.current_user_owns_restaurant(restaurant_id) OR public.is_admin())
  WITH CHECK (public.current_user_owns_restaurant(restaurant_id) OR public.is_admin());
GRANT SELECT, UPDATE ON public.dineout_reservations TO authenticated;

-- ── assigned tables / history / payments: read only, scoped ────────────────
DROP POLICY IF EXISTS dineout_res_tables_read ON public.dineout_reservation_tables;
CREATE POLICY dineout_res_tables_read ON public.dineout_reservation_tables FOR SELECT TO authenticated
  USING (public.current_user_owns_restaurant(restaurant_id) OR public.is_admin()
         OR EXISTS (SELECT 1 FROM public.dineout_reservations r WHERE r.id = reservation_id AND r.user_id = auth.uid()));
GRANT SELECT ON public.dineout_reservation_tables TO authenticated;

DROP POLICY IF EXISTS dineout_hist_read ON public.dineout_status_history;
CREATE POLICY dineout_hist_read ON public.dineout_status_history FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.dineout_reservations r WHERE r.id = reservation_id
                 AND (r.user_id = auth.uid() OR public.current_user_owns_restaurant(r.restaurant_id) OR public.is_admin())));
GRANT SELECT ON public.dineout_status_history TO authenticated;

DROP POLICY IF EXISTS dineout_payments_read ON public.dineout_payments;
CREATE POLICY dineout_payments_read ON public.dineout_payments FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.dineout_reservations r WHERE r.id = reservation_id
                 AND (r.user_id = auth.uid() OR public.current_user_owns_restaurant(r.restaurant_id) OR public.is_admin())));
GRANT SELECT ON public.dineout_payments TO authenticated;

NOTIFY pgrst, 'reload schema';

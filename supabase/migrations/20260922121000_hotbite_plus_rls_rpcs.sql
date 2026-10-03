-- HotBite+ — RLS policies + trusted membership-status RPCs.
-- Customers can read public plans/deals and their own memberships/vouchers, but
-- never write status/dates/discounts. All money-moving writes go through
-- SECURITY DEFINER RPCs or admin.

-- ── membership_plans: public read (active), admin write ────────────────────
ALTER TABLE public.membership_plans ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mplans_read ON public.membership_plans;
CREATE POLICY mplans_read ON public.membership_plans FOR SELECT
  USING (is_active = true OR public.is_admin());
DROP POLICY IF EXISTS mplans_admin ON public.membership_plans;
CREATE POLICY mplans_admin ON public.membership_plans FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── customer_memberships: owner reads own; only admin writes directly ──────
ALTER TABLE public.customer_memberships ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS cmem_read ON public.customer_memberships;
CREATE POLICY cmem_read ON public.customer_memberships FOR SELECT
  USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS cmem_admin ON public.customer_memberships;
CREATE POLICY cmem_admin ON public.customer_memberships FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── membership_deals: public sees approved+active+in-window; owner manages
--    own business's deals; admin all ────────────────────────────────────────
ALTER TABLE public.membership_deals ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mdeals_public_read ON public.membership_deals;
CREATE POLICY mdeals_public_read ON public.membership_deals FOR SELECT
  USING (
    (status = 'approved' AND is_active = true
       AND (start_date IS NULL OR start_date <= now())
       AND (end_date IS NULL OR end_date >= now()))
    OR EXISTS (SELECT 1 FROM public.restaurants r
               WHERE r.id = business_id AND r.owner_id = auth.uid())
    OR public.is_admin()
  );
DROP POLICY IF EXISTS mdeals_owner_write ON public.membership_deals;
CREATE POLICY mdeals_owner_write ON public.membership_deals FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.restaurants r
            WHERE r.id = business_id AND r.owner_id = auth.uid())
    OR public.is_admin()
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.restaurants r
            WHERE r.id = business_id AND r.owner_id = auth.uid())
    OR public.is_admin()
  );

-- ── membership_vouchers: owner reads own; admin writes ─────────────────────
ALTER TABLE public.membership_vouchers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS mvouchers_read ON public.membership_vouchers;
CREATE POLICY mvouchers_read ON public.membership_vouchers FOR SELECT
  USING (user_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS mvouchers_admin ON public.membership_vouchers;
CREATE POLICY mvouchers_admin ON public.membership_vouchers FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── order_membership_discounts: owner reads own (via order); admin ─────────
ALTER TABLE public.order_membership_discounts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS omd_read ON public.order_membership_discounts;
CREATE POLICY omd_read ON public.order_membership_discounts FOR SELECT
  USING (
    EXISTS (SELECT 1 FROM public.orders o
            WHERE o.id = order_id AND o.user_id = auth.uid())
    OR public.is_admin()
  );
DROP POLICY IF EXISTS omd_admin ON public.order_membership_discounts;
CREATE POLICY omd_admin ON public.order_membership_discounts FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- ── Status helpers ─────────────────────────────────────────────────────────
-- Auto-expire then report whether the user is a current HotBite+ member.
CREATE OR REPLACE FUNCTION public.is_hotbite_plus_member(p_user_id uuid DEFAULT auth.uid())
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.customer_memberships m
    WHERE m.user_id = p_user_id
      AND m.status = 'active'
      AND (m.start_date IS NULL OR m.start_date <= now())
      AND (m.end_date IS NULL OR m.end_date >= now())
  );
$$;

-- Full active-membership snapshot for the app (plan + expiry + status).
CREATE OR REPLACE FUNCTION public.get_active_membership(p_user_id uuid DEFAULT auth.uid())
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $$
DECLARE r jsonb;
BEGIN
  SELECT jsonb_build_object(
    'membership_id', m.id, 'status', m.status,
    'plan_id', p.id, 'plan_name', p.name,
    'start_date', m.start_date, 'end_date', m.end_date,
    'auto_renew', m.auto_renew,
    'is_active', (m.status='active'
       AND (m.start_date IS NULL OR m.start_date <= now())
       AND (m.end_date IS NULL OR m.end_date >= now()))
  ) INTO r
  FROM public.customer_memberships m
  LEFT JOIN public.membership_plans p ON p.id = m.membership_plan_id
  WHERE m.user_id = p_user_id
  ORDER BY (m.status='active') DESC, m.end_date DESC NULLS LAST
  LIMIT 1;
  RETURN r; -- null when the user has never had a membership
END; $$;

-- Trusted activation. Called only by an admin or the payments edge function
-- (service role) AFTER a payment is confirmed — never self-served by a client.
-- Renewal before expiry EXTENDS the current end_date; an expired/none member
-- starts fresh. Idempotent on payment_reference.
CREATE OR REPLACE FUNCTION public.activate_membership(
  p_user_id uuid, p_plan_id uuid, p_payment_reference text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_plan record; v_existing record; v_start timestamptz; v_end timestamptz; v_id uuid;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_payment_reference IS NOT NULL AND EXISTS (
     SELECT 1 FROM public.customer_memberships WHERE payment_reference = p_payment_reference) THEN
    -- duplicate payment callback — return the already-created membership
    SELECT id INTO v_id FROM public.customer_memberships WHERE payment_reference = p_payment_reference LIMIT 1;
    RETURN jsonb_build_object('membership_id', v_id, 'duplicate', true);
  END IF;

  SELECT * INTO v_plan FROM public.membership_plans WHERE id = p_plan_id AND is_active;
  IF v_plan.id IS NULL THEN RAISE EXCEPTION 'plan not found or inactive'; END IF;

  -- Renewal: extend the still-active membership rather than overlap.
  SELECT * INTO v_existing FROM public.customer_memberships
   WHERE user_id = p_user_id AND status='active'
     AND (end_date IS NULL OR end_date >= now())
   ORDER BY end_date DESC NULLS LAST LIMIT 1;

  IF v_existing.id IS NOT NULL THEN
    v_end := COALESCE(v_existing.end_date, now()) + make_interval(days => v_plan.duration_days);
    UPDATE public.customer_memberships
       SET end_date = v_end, membership_plan_id = p_plan_id,
           price_paid = v_plan.price, payment_reference = COALESCE(p_payment_reference, payment_reference),
           updated_at = now()
     WHERE id = v_existing.id;
    RETURN jsonb_build_object('membership_id', v_existing.id, 'renewed', true, 'end_date', v_end);
  ELSE
    v_start := now();
    v_end := v_start + make_interval(days => v_plan.duration_days);
    INSERT INTO public.customer_memberships
      (user_id, membership_plan_id, status, start_date, end_date, price_paid, payment_reference)
    VALUES (p_user_id, p_plan_id, 'active', v_start, v_end, v_plan.price, p_payment_reference)
    RETURNING id INTO v_id;
    RETURN jsonb_build_object('membership_id', v_id, 'activated', true, 'end_date', v_end);
  END IF;
END; $$;

GRANT EXECUTE ON FUNCTION public.is_hotbite_plus_member(uuid) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.get_active_membership(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.activate_membership(uuid, uuid, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

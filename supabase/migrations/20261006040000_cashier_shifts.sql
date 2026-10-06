-- ============================================================================
-- CASHIER SHIFTS & RECONCILIATION (Phase 3) — sections 6/7/8.
--
-- Money is INTEGER MINOR UNITS (cents). Recording reconciliation moves NO money:
-- it never issues refunds, pays restaurants, or touches driver float — it only
-- records the drawer count vs. expected. Existing settlement/float/payout rules
-- are untouched. Business-day boundaries use the restaurant's IANA timezone.
-- ============================================================================

INSERT INTO public.app_config (key, value) VALUES
  ('shift_open_flag_hours','16')          -- flag shifts open longer than this
ON CONFLICT (key) DO NOTHING;

-- Restaurant IANA timezone (default Jamaica).
ALTER TABLE public.restaurants ADD COLUMN IF NOT EXISTS timezone text NOT NULL DEFAULT 'America/Jamaica';

CREATE OR REPLACE FUNCTION public.restaurant_business_date(p_restaurant uuid, p_at timestamptz DEFAULT now())
  RETURNS date LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT (p_at AT TIME ZONE coalesce((SELECT timezone FROM public.restaurants WHERE id=p_restaurant),'America/Jamaica'))::date;
$$;
GRANT EXECUTE ON FUNCTION public.restaurant_business_date(uuid,timestamptz) TO authenticated, service_role;

-- ── Shifts ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.cashier_shifts (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id      uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  cashier_user_id    uuid NOT NULL REFERENCES public.users(id),
  status             text NOT NULL DEFAULT 'open' CHECK (status IN ('open','submitted','approved')),
  requires_manager_closure boolean NOT NULL DEFAULT false,
  business_date      date NOT NULL,
  timezone           text NOT NULL DEFAULT 'America/Jamaica',
  opened_at          timestamptz NOT NULL DEFAULT now(),
  opening_float_cents    bigint NOT NULL DEFAULT 0,
  closed_at          timestamptz,
  counted_cash_cents bigint,
  expected_cash_cents bigint,
  variance_cents     bigint,
  variance_explanation text,
  submitted_at       timestamptz,
  submitted_by       uuid REFERENCES public.users(id),
  approved_at        timestamptz,
  approved_by        uuid REFERENCES public.users(id),
  return_reason      text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
-- At most ONE unresolved (open/submitted) shift per cashier per restaurant.
CREATE UNIQUE INDEX IF NOT EXISTS uq_shift_open_per_cashier
  ON public.cashier_shifts(restaurant_id, cashier_user_id) WHERE status IN ('open','submitted');
CREATE INDEX IF NOT EXISTS idx_shift_restaurant_date ON public.cashier_shifts(restaurant_id, business_date);
ALTER TABLE public.cashier_shifts ENABLE ROW LEVEL SECURITY;

-- ── Cash movements (source of truth for expected cash) ──────────────────────
CREATE TABLE IF NOT EXISTS public.shift_cash_movements (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id      uuid NOT NULL REFERENCES public.cashier_shifts(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  kind          text NOT NULL CHECK (kind IN ('receipt','deposit','refund','withdrawal','rider_cash_received')),
  amount_cents  bigint NOT NULL CHECK (amount_cents >= 0),
  order_id      uuid REFERENCES public.orders(id),
  note          text,
  created_by    uuid REFERENCES public.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);
-- Prevent duplicate recording of the same order's cash for the same kind.
CREATE UNIQUE INDEX IF NOT EXISTS uq_cashmove_order_kind
  ON public.shift_cash_movements(order_id, kind) WHERE order_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_cashmove_shift ON public.shift_cash_movements(shift_id);
ALTER TABLE public.shift_cash_movements ENABLE ROW LEVEL SECURITY;

-- ── Post-approval corrections (never overwrite approved figures) ─────────────
CREATE TABLE IF NOT EXISTS public.shift_adjustments (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  shift_id      uuid NOT NULL REFERENCES public.cashier_shifts(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  amount_cents  bigint NOT NULL,
  reason        text NOT NULL,
  actor_user_id uuid REFERENCES public.users(id),
  created_at    timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.shift_adjustments ENABLE ROW LEVEL SECURITY;

-- ── RLS: cashier sees own shift; owner/manager see all; no client writes ────
DROP POLICY IF EXISTS shift_select ON public.cashier_shifts;
CREATE POLICY shift_select ON public.cashier_shifts FOR SELECT TO authenticated
  USING (public.can_manage_restaurant_staff(restaurant_id) OR cashier_user_id = auth.uid());
DROP POLICY IF EXISTS cashmove_select ON public.shift_cash_movements;
CREATE POLICY cashmove_select ON public.shift_cash_movements FOR SELECT TO authenticated
  USING (public.can_manage_restaurant_staff(restaurant_id)
         OR EXISTS (SELECT 1 FROM public.cashier_shifts s WHERE s.id=shift_id AND s.cashier_user_id=auth.uid()));
DROP POLICY IF EXISTS adj_select ON public.shift_adjustments;
CREATE POLICY adj_select ON public.shift_adjustments FOR SELECT TO authenticated
  USING (public.can_manage_restaurant_staff(restaurant_id));
REVOKE INSERT, UPDATE, DELETE ON public.cashier_shifts, public.shift_cash_movements, public.shift_adjustments FROM anon, authenticated;

-- Expected cash = opening float + receipts + deposits + rider_cash_received − refunds − withdrawals.
CREATE OR REPLACE FUNCTION public.shift_expected_cash_cents(p_shift uuid)
  RETURNS bigint LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT (SELECT opening_float_cents FROM public.cashier_shifts WHERE id=p_shift)
    + coalesce((SELECT sum(CASE kind
         WHEN 'receipt' THEN amount_cents WHEN 'deposit' THEN amount_cents
         WHEN 'rider_cash_received' THEN amount_cents
         WHEN 'refund' THEN -amount_cents WHEN 'withdrawal' THEN -amount_cents ELSE 0 END)
       FROM public.shift_cash_movements WHERE shift_id=p_shift),0);
$$;
GRANT EXECUTE ON FUNCTION public.shift_expected_cash_cents(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

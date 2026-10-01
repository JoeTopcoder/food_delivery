-- ============================================================================
-- Company-Sponsored Ordering v2: FLAT per-order fees (replaces daily tiers) +
-- a company charges ledger (unpaid/paid/adjusted), payments and auditable
-- cancellation reversals.
--
--   Delivery = JMD 350 (35000 cents), Service = JMD 250 (25000 cents),
--   Total company charge = JMD 600 (60000 cents), fixed per sponsored order.
--   No tiers, no end-of-day repricing.
-- All money in integer cents. All amounts/eligibility validated server-side.
-- ============================================================================

-- ─── Ledger / payments / adjustments ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.company_charges (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id    uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  order_id      uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  charge_date   date NOT NULL,
  delivery_cents int NOT NULL,
  service_cents  int NOT NULL,
  total_cents    int NOT NULL,
  status        text NOT NULL DEFAULT 'unpaid'
                  CHECK (status IN ('unpaid','paid','adjusted','reversed')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (order_id)
);
CREATE INDEX IF NOT EXISTS company_charges_company_date_idx
  ON public.company_charges(company_id, charge_date);

CREATE TABLE IF NOT EXISTS public.company_payments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id   uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  amount_cents int NOT NULL CHECK (amount_cents > 0),
  reference    text,
  note         text,
  recorded_by  uuid REFERENCES public.users(id),
  created_at   timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.company_charge_adjustments (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  order_id    uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  delta_cents int NOT NULL,          -- negative = credit (e.g. cancellation reversal)
  reason      text,
  created_by  uuid REFERENCES public.users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.company_charges            ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_payments           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_charge_adjustments ENABLE ROW LEVEL SECURITY;
CREATE POLICY charges_read ON public.company_charges FOR SELECT TO authenticated
  USING (public.is_company_admin(company_id) OR public.is_admin());
CREATE POLICY payments_read ON public.company_payments FOR SELECT TO authenticated
  USING (public.is_company_admin(company_id) OR public.is_admin());
CREATE POLICY adjustments_read ON public.company_charge_adjustments FOR SELECT TO authenticated
  USING (public.is_company_admin(company_id) OR public.is_admin());

-- ─── Flat-fee confirm (replaces the tier version) ───────────────────────────
CREATE OR REPLACE FUNCTION public.company_confirm_sponsorship(
  p_reservation_id uuid, p_order_id uuid, p_service_cents int DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE u public.company_sponsorship_usage; c public.companies; o public.orders;
        v_delivery int := 35000; v_service int := 25000;  -- flat JMD 350 / 250
BEGIN
  SELECT * INTO u FROM public.company_sponsorship_usage WHERE id=p_reservation_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'Reservation not found'; END IF;
  IF u.status = 'placed' AND u.order_id = p_order_id THEN
    RETURN jsonb_build_object('ok',true,'already',true);
  END IF;
  IF u.status <> 'reserved' THEN RAISE EXCEPTION 'Reservation not active'; END IF;

  SELECT * INTO c FROM public.companies WHERE id=u.company_id;
  SELECT * INTO o FROM public.orders WHERE id=p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;

  UPDATE public.company_sponsorship_usage
     SET status='placed', order_id=p_order_id, expires_at=NULL WHERE id=p_reservation_id;

  UPDATE public.orders SET
     is_company_sponsored = true,
     company_id = u.company_id,
     company_sponsorship_date = u.usage_date,
     company_delivery_cents = v_delivery,
     company_service_cents  = v_service,
     company_address_snapshot = jsonb_build_object('name',c.name,'address',c.delivery_address,'lat',c.latitude,'lon',c.longitude),
     company_distance_km = public.geo_distance_km(
        (SELECT latitude FROM public.restaurants WHERE id=o.restaurant_id),
        (SELECT longitude FROM public.restaurants WHERE id=o.restaurant_id),
        c.latitude, c.longitude),
     company_radius_km = c.radius_km,
     company_charge_status = 'final'   -- flat fees are final immediately
   WHERE id = p_order_id;

  -- Ledger entry (idempotent per order).
  INSERT INTO public.company_charges (company_id, order_id, charge_date, delivery_cents, service_cents, total_cents, status)
  VALUES (u.company_id, p_order_id, u.usage_date, v_delivery, v_service, v_delivery+v_service, 'unpaid')
  ON CONFLICT (order_id) DO NOTHING;

  RETURN jsonb_build_object('ok',true,'delivery_cents',v_delivery,'service_cents',v_service,'total_cents',v_delivery+v_service);
END; $$;
REVOKE ALL ON FUNCTION public.company_confirm_sponsorship(uuid,uuid,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_confirm_sponsorship(uuid,uuid,int) TO service_role;

-- ─── Cancellation reversal (auditable; never deletes history) ────────────────
CREATE OR REPLACE FUNCTION public.company_charge_on_cancel()
  RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE ch public.company_charges;
BEGIN
  IF NEW.status = 'cancelled' AND coalesce(OLD.status,'') <> 'cancelled'
     AND NEW.is_company_sponsored THEN
    SELECT * INTO ch FROM public.company_charges WHERE order_id = NEW.id;
    IF ch.id IS NOT NULL AND ch.status NOT IN ('adjusted','reversed') THEN
      INSERT INTO public.company_charge_adjustments (company_id, order_id, delta_cents, reason)
      VALUES (ch.company_id, NEW.id, -ch.total_cents, 'order_cancelled');
      UPDATE public.company_charges SET status='adjusted' WHERE id = ch.id;
    END IF;
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_company_charge_on_cancel ON public.orders;
CREATE TRIGGER trg_company_charge_on_cancel
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.company_charge_on_cancel();

-- ─── Account summary (immediate; no repricing) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.company_account_summary(p_company_id uuid, p_date date DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE d date := p_date;
        v_orders int; v_cancelled int; v_delivery int; v_service int;
        v_adjust int; v_charges_total int; v_paid int; v_outstanding int;
BEGIN
  IF NOT public.is_company_admin(p_company_id) AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized'; END IF;

  -- Day scope (orders section) — defaults to today's Jamaica date for the cards.
  SELECT count(*) FILTER (WHERE o.status <> 'cancelled'),
         count(*) FILTER (WHERE o.status = 'cancelled')
    INTO v_orders, v_cancelled
  FROM public.orders o
  WHERE o.company_id = p_company_id AND o.is_company_sponsored
    AND o.company_sponsorship_date = coalesce(d, public.jamaica_today());

  -- Ledger totals (all-time outstanding).
  SELECT coalesce(sum(delivery_cents),0), coalesce(sum(service_cents),0), coalesce(sum(total_cents),0)
    INTO v_delivery, v_service, v_charges_total
  FROM public.company_charges WHERE company_id = p_company_id;
  SELECT coalesce(sum(delta_cents),0) INTO v_adjust
  FROM public.company_charge_adjustments WHERE company_id = p_company_id;
  SELECT coalesce(sum(amount_cents),0) INTO v_paid
  FROM public.company_payments WHERE company_id = p_company_id;
  v_outstanding := v_charges_total + v_adjust - v_paid;

  RETURN jsonb_build_object(
    'date', coalesce(d, public.jamaica_today()),
    'orders_today', v_orders, 'cancelled_today', v_cancelled,
    'delivery_cents', v_delivery, 'service_cents', v_service,
    'charges_total_cents', v_charges_total, 'adjustments_cents', v_adjust,
    'paid_cents', v_paid, 'outstanding_cents', v_outstanding);
END; $$;
REVOKE ALL ON FUNCTION public.company_account_summary(uuid,date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_account_summary(uuid,date) TO authenticated;

-- ─── HotBite admin records a company payment ────────────────────────────────
CREATE OR REPLACE FUNCTION public.company_record_payment(
  p_company_id uuid, p_amount_cents int, p_reference text DEFAULT NULL, p_note text DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only HotBite admins can record payments'; END IF;
  IF p_amount_cents IS NULL OR p_amount_cents <= 0 THEN RAISE EXCEPTION 'Invalid amount'; END IF;
  INSERT INTO public.company_payments (company_id, amount_cents, reference, note, recorded_by)
  VALUES (p_company_id, p_amount_cents, p_reference, p_note, auth.uid()) RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok',true,'payment_id',v_id);
END; $$;
REVOKE ALL ON FUNCTION public.company_record_payment(uuid,int,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_record_payment(uuid,int,text,text) TO authenticated;

NOTIFY pgrst, 'reload schema';

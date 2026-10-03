-- ============================================================================
-- HotBite AI Staff — Stage 3: trusted daily metrics layer
-- ============================================================================
-- A single SECURITY DEFINER function computes one day's metrics for the 24 AI
-- staff roles, over America/Jamaica business-day boundaries, from the REAL
-- schema. It is deliberately read-only and reuses the project's existing
-- financial primitives rather than inventing a second definition of revenue:
--
--   * public.admin_order_economics(from, to, is_grocery)  ← THE source of truth
--       for GMV (subtotal), restaurant commission, delivery fee, service fee
--       and rider payout. It already: windows on orders.ordered_at, EXCLUDES
--       status='cancelled', splits vertical by restaurants.store_type, and
--       returns integer cents. We only SUM its rows — we never re-derive these.
--   * get_financial_statistics()'s rule for "delivered revenue" (SUM
--       total_amount WHERE status='delivered') is reused verbatim for the
--       delivered-revenue figure.
--   * driver_pay_percent / monthly_ops_cost stay sourced from app_config.
--
-- Anti-double-counting:
--   * Every order contributes at most one row (admin_order_economics joins
--     restaurants 1:1; all other reads are single-table on orders).
--   * Cancellations are counted from orders.cancelled_at once and are already
--     excluded from economics — never subtracted twice.
--   * Refunds come from the refunds table (one row each) and are reported
--     separately; they are NOT also netted out of order revenue here.
--   * We read per-order timestamp columns (delivered_at, cancelled_at, …), NOT
--     order_status_events, so repeated status transitions can't inflate counts.
--   * Payment capture is read once per order (orders.payment_status), not by
--     summing payment attempts, so split/multi payments don't double-count.
--
-- Honesty:
--   * Metrics whose source is not recorded in the schema return the string
--     'data_unavailable' — never a fabricated 0.
--   * is_mock_data rows are excluded wherever that flag exists.
--
-- Reproducibility: the whole result is a pure function of p_date (fixed TZ
-- window), so any historical date recomputes identically.
--
-- Access: admins (public.is_admin()) or the backend service role only.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ai_staff_daily_metrics(
  p_date date DEFAULT ((now() AT TIME ZONE 'America/Jamaica')::date)
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  v_from   timestamptz;
  v_to     timestamptz;
  v_dpct   numeric;
  f        record;  -- food economics (cents)
  g        record;  -- grocery economics (cents)
  o        record;  -- order lifecycle counts
  del      record;  -- delivered-basis finance
  disp     record;  -- dispatch
  ride     record;  -- riders
  rest     record;  -- restaurants (food)
  sup      record;  -- supermarkets (grocery)
  pay      record;  -- payments
  ref      record;  -- refunds
  mem      record;  -- membership
  promo    record;  -- promotions
  iss      record;  -- customer issues
  rel      record;  -- reliability
BEGIN
  -- ── access gate ──────────────────────────────────────────────────────────
  IF NOT (
       public.is_admin()
       OR COALESCE(auth.role(), '') = 'service_role'
       OR COALESCE(current_setting('request.jwt.claims', true)::jsonb ->> 'role', '') = 'service_role'
     ) THEN
    RAISE EXCEPTION 'Forbidden: admin or service role required';
  END IF;

  -- ── America/Jamaica business day  [v_from, v_to)  (Jamaica is UTC-5, no DST)
  v_from := (p_date::timestamp AT TIME ZONE 'America/Jamaica');
  v_to   := ((p_date + 1)::timestamp AT TIME ZONE 'America/Jamaica');

  v_dpct := COALESCE(
    (SELECT NULLIF(value,'')::numeric FROM app_config WHERE key='driver_pay_percent'),
    0.80);

  -- ── canonical economics (SUM the source-of-truth primitive) ──────────────
  SELECT count(*)::bigint AS n,
         COALESCE(sum(gmv),0)::bigint          AS gmv,
         COALESCE(sum(commission),0)::bigint   AS commission,
         COALESCE(sum(delivery_fee),0)::bigint AS delivery_fee,
         COALESCE(sum(service_fee),0)::bigint  AS service_fee,
         COALESCE(sum(rider_payout),0)::bigint AS rider_payout
    INTO f FROM public.admin_order_economics(v_from, v_to, false);

  SELECT count(*)::bigint AS n,
         COALESCE(sum(gmv),0)::bigint          AS gmv,
         COALESCE(sum(commission),0)::bigint   AS commission,
         COALESCE(sum(delivery_fee),0)::bigint AS delivery_fee,
         COALESCE(sum(service_fee),0)::bigint  AS service_fee,
         COALESCE(sum(rider_payout),0)::bigint AS rider_payout
    INTO g FROM public.admin_order_economics(v_from, v_to, true);

  -- ── order lifecycle (each metric on ONE per-order timestamp) ─────────────
  SELECT
    count(*) FILTER (WHERE o2.ordered_at >= v_from AND o2.ordered_at < v_to)                              AS placed,
    count(*) FILTER (WHERE o2.status='delivered' AND o2.delivered_at >= v_from AND o2.delivered_at < v_to) AS delivered,
    count(*) FILTER (WHERE o2.status='cancelled' AND o2.cancelled_at >= v_from AND o2.cancelled_at < v_to) AS cancelled,
    count(*) FILTER (WHERE o2.ordered_at >= v_from AND o2.ordered_at < v_to AND o2.is_pickup)             AS pickup,
    count(*) FILTER (WHERE o2.ordered_at >= v_from AND o2.ordered_at < v_to AND o2.is_scheduled)          AS scheduled,
    avg(EXTRACT(EPOCH FROM (o2.delivered_at - o2.ordered_at))/60.0)
       FILTER (WHERE o2.status='delivered' AND o2.delivered_at >= v_from AND o2.delivered_at < v_to)      AS avg_fulfil_min
    INTO o FROM public.orders o2;

  -- ── delivered-basis finance (reuses get_financial_statistics' rule) ──────
  SELECT
    COALESCE(sum(total_amount),0)                                   AS delivered_revenue,
    COALESCE(sum(member_savings),0)                                 AS member_savings,
    COALESCE(sum(COALESCE(stripe_fee_amount, round((subtotal*0.029+0.30)::numeric,2))),0) AS stripe_fees,
    COALESCE(sum(driver_tip),0) + COALESCE(sum(post_delivery_tip),0) AS tips
    INTO del FROM public.orders
    WHERE status='delivered' AND delivered_at >= v_from AND delivered_at < v_to;

  -- ── dispatch ─────────────────────────────────────────────────────────────
  SELECT
    count(*) FILTER (WHERE ordered_at >= v_from AND ordered_at < v_to AND driver_id IS NOT NULL)     AS with_driver,
    count(*) FILTER (WHERE ordered_at >= v_from AND ordered_at < v_to AND driver_id IS NULL
                          AND status NOT IN ('cancelled','delivered','draft'))                        AS unassigned_active
    INTO disp FROM public.orders;

  -- ── riders ───────────────────────────────────────────────────────────────
  SELECT
    count(DISTINCT driver_id) FILTER (WHERE status='delivered' AND delivered_at >= v_from AND delivered_at < v_to AND driver_id IS NOT NULL) AS active,
    avg(driver_rating) FILTER (WHERE status='delivered' AND delivered_at >= v_from AND delivered_at < v_to AND driver_rating IS NOT NULL)     AS avg_rating
    INTO ride FROM public.orders;

  -- ── restaurants (food) ───────────────────────────────────────────────────
  SELECT
    count(DISTINCT o2.restaurant_id) FILTER (WHERE o2.ordered_at >= v_from AND o2.ordered_at < v_to AND r.store_type <> 'grocery') AS active,
    avg(EXTRACT(EPOCH FROM (o2.ready_at - o2.preparing_started_at))/60.0)
       FILTER (WHERE o2.ready_at IS NOT NULL AND o2.preparing_started_at IS NOT NULL
               AND o2.ordered_at >= v_from AND o2.ordered_at < v_to AND r.store_type <> 'grocery')     AS avg_prep_min
    INTO rest FROM public.orders o2 JOIN public.restaurants r ON r.id=o2.restaurant_id;

  -- ── supermarkets (grocery) ───────────────────────────────────────────────
  SELECT
    count(DISTINCT o2.restaurant_id) FILTER (WHERE o2.ordered_at >= v_from AND o2.ordered_at < v_to AND r.store_type='grocery') AS active
    INTO sup FROM public.orders o2 JOIN public.restaurants r ON r.id=o2.restaurant_id;

  -- ── payments (read once per order; no split double-count) ────────────────
  SELECT
    count(*) FILTER (WHERE ordered_at >= v_from AND ordered_at < v_to AND payment_status='completed') AS captured,
    count(*) FILTER (WHERE ordered_at >= v_from AND ordered_at < v_to AND payment_status='pending')   AS pending,
    count(*) FILTER (WHERE ordered_at >= v_from AND ordered_at < v_to AND payment_status='failed')    AS failed
    INTO pay FROM public.orders;

  -- ── refunds (own table, one row each) ────────────────────────────────────
  SELECT
    count(*) FILTER (WHERE created_at >= v_from AND created_at < v_to)                                 AS n,
    COALESCE(sum(amount) FILTER (WHERE created_at >= v_from AND created_at < v_to),0)                  AS amount,
    count(*) FILTER (WHERE created_at >= v_from AND created_at < v_to AND status='completed')          AS completed
    INTO ref FROM public.refunds;

  -- ── membership (price_paid = the recorded membership revenue) ────────────
  SELECT
    count(*) FILTER (WHERE created_at >= v_from AND created_at < v_to)                                 AS new_members,
    COALESCE(sum(price_paid) FILTER (WHERE created_at >= v_from AND created_at < v_to),0)              AS revenue,
    count(*) FILTER (WHERE status='active' AND start_date < v_to AND (end_date IS NULL OR end_date >= v_from)) AS active_members,
    count(*) FILTER (WHERE end_date >= v_from AND end_date < v_to)                                     AS expiring,
    count(*) FILTER (WHERE status IN ('cancelled','canceled') AND updated_at >= v_from AND updated_at < v_to) AS cancelled
    INTO mem FROM public.customer_memberships;

  -- ── promotions (per-day from orders, not the cumulative usage_count) ─────
  SELECT
    count(*) FILTER (WHERE ordered_at >= v_from AND ordered_at < v_to AND promo_code IS NOT NULL AND promo_code<>'') AS redemptions,
    COALESCE(sum(COALESCE(discount_amount, discount, 0)) FILTER (WHERE ordered_at >= v_from AND ordered_at < v_to AND promo_code IS NOT NULL AND promo_code<>''),0) AS discount_total
    INTO promo FROM public.orders;

  -- ── customer issues ──────────────────────────────────────────────────────
  SELECT
    (SELECT count(*) FROM public.support_requests WHERE created_at >= v_from AND created_at < v_to)    AS support,
    (SELECT count(*) FROM public.disputes WHERE created_at >= v_from AND created_at < v_to AND COALESCE(is_mock_data,false)=false) AS disputes,
    (SELECT count(*) FROM public.orders WHERE status='delivered' AND delivered_at >= v_from AND delivered_at < v_to AND user_rating IS NOT NULL AND user_rating <= 2) AS low_ratings
    INTO iss;

  -- ── system reliability ───────────────────────────────────────────────────
  SELECT
    (SELECT count(*) FROM public.ai_agent_runs WHERE created_at >= v_from AND created_at < v_to AND status IN ('error','failed')) AS failed_agent_runs,
    (SELECT count(*) FROM public.orders WHERE ordered_at >= v_from AND ordered_at < v_to AND payment_status='failed')             AS failed_payments
    INTO rel;

  -- ── assemble (money in JMD dollars; economics cents → /100) ──────────────
  RETURN jsonb_build_object(
    'meta', jsonb_build_object(
       'report_date', p_date,
       'timezone', 'America/Jamaica',
       'window_start', v_from,
       'window_end', v_to,
       'generated_at', now(),
       'driver_pay_percent', v_dpct,
       'notes', 'Amounts in JMD. GMV/commission/fees/rider_payout reuse admin_order_economics (non-cancelled, ordered_at). delivered_revenue reuses get_financial_statistics rule (delivered only).'
    ),
    'orders', jsonb_build_object(
       'placed', o.placed, 'delivered', o.delivered, 'cancelled', o.cancelled,
       'pickup', o.pickup, 'scheduled', o.scheduled,
       'cancellation_rate_pct', CASE WHEN o.placed>0 THEN round((o.cancelled::numeric/o.placed)*100,2) ELSE 0 END,
       'avg_fulfilment_minutes', CASE WHEN o.avg_fulfil_min IS NULL THEN to_jsonb('data_unavailable'::text) ELSE to_jsonb(round(o.avg_fulfil_min::numeric,1)) END
    ),
    'finance', jsonb_build_object(
       'gmv', round((f.gmv+g.gmv)/100.0,2),
       'gmv_food', round(f.gmv/100.0,2),
       'gmv_grocery', round(g.gmv/100.0,2),
       'restaurant_commission', round((f.commission+g.commission)/100.0,2),
       'delivery_fee_revenue', round((f.delivery_fee+g.delivery_fee)/100.0,2),
       'service_fee_revenue', round((f.service_fee+g.service_fee)/100.0,2),
       'rider_payout', round((f.rider_payout+g.rider_payout)/100.0,2),
       'contribution', round(((f.commission+g.commission)+(f.delivery_fee+g.delivery_fee)-(f.rider_payout+g.rider_payout))/100.0,2),
       'delivered_revenue', round(del.delivered_revenue::numeric,2),
       'member_savings_cost', round(del.member_savings::numeric,2),
       'stripe_fees', round(del.stripe_fees::numeric,2),
       'tips_passthrough', round(del.tips::numeric,2)
    ),
    'dispatch', jsonb_build_object(
       'orders_with_rider', disp.with_driver,
       'orders_unassigned_active', disp.unassigned_active,
       'avg_assignment_minutes', 'data_unavailable'  -- no assignment timestamp recorded
    ),
    'delivery', jsonb_build_object(
       'delivered', o.delivered,
       'delivery_fee_revenue', round((f.delivery_fee+g.delivery_fee)/100.0,2),
       'avg_fulfilment_minutes', CASE WHEN o.avg_fulfil_min IS NULL THEN to_jsonb('data_unavailable'::text) ELSE to_jsonb(round(o.avg_fulfil_min::numeric,1)) END
    ),
    'riders', jsonb_build_object(
       'active_riders', ride.active,
       'deliveries', o.delivered,
       'deliveries_per_rider', CASE WHEN ride.active>0 THEN round(o.delivered::numeric/ride.active,2) ELSE 0 END,
       'avg_rating', CASE WHEN ride.avg_rating IS NULL THEN to_jsonb('data_unavailable'::text) ELSE to_jsonb(round(ride.avg_rating::numeric,2)) END,
       'rider_payout', round((f.rider_payout+g.rider_payout)/100.0,2)
    ),
    'restaurants', jsonb_build_object(
       'active', rest.active, 'orders', f.n, 'gmv', round(f.gmv/100.0,2),
       'commission', round(f.commission/100.0,2),
       'avg_prep_minutes', CASE WHEN rest.avg_prep_min IS NULL THEN to_jsonb('data_unavailable'::text) ELSE to_jsonb(round(rest.avg_prep_min::numeric,1)) END
    ),
    'supermarkets', jsonb_build_object(
       'active', sup.active, 'orders', g.n, 'gmv', round(g.gmv/100.0,2),
       'commission', round(g.commission/100.0,2),
       'picking_accuracy', 'data_unavailable',      -- not recorded
       'substitution_rate', 'data_unavailable'      -- not recorded
    ),
    'payments', jsonb_build_object(
       'captured', pay.captured, 'pending', pay.pending, 'failed', pay.failed
    ),
    'refunds', jsonb_build_object(
       'count', ref.n, 'amount', round(ref.amount::numeric,2), 'completed', ref.completed
    ),
    'membership', jsonb_build_object(
       'new_members', mem.new_members,
       'membership_revenue', round(mem.revenue::numeric,2),
       'active_members', mem.active_members,
       'expiring_today', mem.expiring,
       'cancelled', mem.cancelled
    ),
    'promotions', jsonb_build_object(
       'redemptions', promo.redemptions,
       'discount_cost', round(promo.discount_total::numeric,2)
    ),
    'customer_issues', jsonb_build_object(
       'support_requests', iss.support,
       'disputes', iss.disputes,
       'low_ratings', iss.low_ratings
    ),
    'reliability', jsonb_build_object(
       'failed_agent_runs', rel.failed_agent_runs,
       'failed_payments', rel.failed_payments
    )
  );
END;
$fn$;

REVOKE ALL ON FUNCTION public.ai_staff_daily_metrics(date) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ai_staff_daily_metrics(date) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

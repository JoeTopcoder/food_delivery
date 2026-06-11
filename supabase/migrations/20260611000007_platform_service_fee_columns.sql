-- ═══════════════════════════════════════════════════════════════════════════
-- Platform service fee columns + updated financial reporting RPC
-- Formula: platform_service_fee = (subtotal × 2.9%) + $0.30 + $1.00
--          stripe_fee_amount     = (subtotal × 2.9%) + $0.30
-- New columns are nullable → backward compatible; existing rows keep NULL.
-- ═══════════════════════════════════════════════════════════════════════════

-- ── 1. Orders table ──────────────────────────────────────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS stripe_fee_amount      DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS platform_service_fee   DOUBLE PRECISION;

-- ── 2. Ride requests table ───────────────────────────────────────────────────
ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS stripe_fee_amount      DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS platform_service_fee   DOUBLE PRECISION;

-- ── 3. Car service bookings table ────────────────────────────────────────────
ALTER TABLE public.car_service_bookings
  ADD COLUMN IF NOT EXISTS stripe_fee_amount      DOUBLE PRECISION,
  ADD COLUMN IF NOT EXISTS platform_service_fee   DOUBLE PRECISION;

-- ── 4. Update get_financial_statistics RPC ───────────────────────────────────
-- Adds: gross_revenue, stripe_fees_collected, platform_service_fees_collected,
--       net_revenue to the existing JSON response.
-- For rows that pre-date this migration (fee columns NULL), fees are computed
-- on-the-fly from subtotal so historical data is included correctly.
CREATE OR REPLACE FUNCTION public.get_financial_statistics()
RETURNS JSON
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT json_build_object(
    'total_sales',            COALESCE(SUM(total_amount), 0),
    'total_commission',       COALESCE(SUM(commission_amount), 0),
    'total_delivery_fees',    COALESCE(SUM(delivery_fee), 0),
    'total_driver_tips',      COALESCE(SUM(driver_tip), 0),
    'total_restaurant_payout',COALESCE(SUM(total_amount - commission_amount - delivery_fee), 0),
    'total_driver_payout',    COALESCE(SUM(delivery_fee + driver_tip), 0),
    'order_count',            COUNT(*),
    'monthly_sales',          COALESCE(SUM(CASE
                                WHEN ordered_at >= date_trunc('month', NOW())
                                THEN total_amount ELSE 0 END), 0),
    'monthly_commission',     COALESCE(SUM(CASE
                                WHEN ordered_at >= date_trunc('month', NOW())
                                THEN commission_amount ELSE 0 END), 0),

    -- ── New revenue reporting fields ─────────────────────────────────────────
    'gross_revenue',          COALESCE(SUM(total_amount), 0),

    -- Stripe processing portion: (subtotal × 2.9%) + $0.30
    -- Uses stored value when available; falls back to formula for old rows.
    'stripe_fees_collected',  COALESCE(SUM(
                                CASE
                                  WHEN stripe_fee_amount IS NOT NULL
                                  THEN stripe_fee_amount
                                  ELSE ROUND(((subtotal * 0.029) + 0.30)::numeric, 2)
                                END
                              ), 0),

    -- Full customer-facing fee: (subtotal × 2.9%) + $0.30 + $1.00
    'platform_service_fees_collected', COALESCE(SUM(
                                CASE
                                  WHEN platform_service_fee IS NOT NULL
                                  THEN platform_service_fee
                                  ELSE ROUND(((subtotal * 0.029) + 0.30 + 1.00)::numeric, 2)
                                END
                              ), 0),

    -- Net revenue = gross revenue minus Stripe's cut
    'net_revenue',            COALESCE(
                                SUM(total_amount) - SUM(
                                  CASE
                                    WHEN stripe_fee_amount IS NOT NULL
                                    THEN stripe_fee_amount
                                    ELSE ROUND(((subtotal * 0.029) + 0.30)::numeric, 2)
                                  END
                                ), 0)
  )
  FROM public.orders
  WHERE status = 'delivered';
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Scale optimizations for 7M+ users
-- • pg_trgm GIN indexes for fast ILIKE search on users.email / users.name
-- • get_active_orders_summary() — DB-side aggregate for AI admin context
-- • get_financial_statistics()  — DB-side aggregate replaces full table scan
-- ═══════════════════════════════════════════════════════════════════════════

-- Enable pg_trgm extension (no-op if already enabled)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- GIN trigram indexes for user search (supports '%query%' ILIKE instantly)
CREATE INDEX IF NOT EXISTS idx_users_email_trgm
  ON public.users USING gin (email gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_users_name_trgm
  ON public.users USING gin (name gin_trgm_ops);

-- GIN trigram indexes for restaurant search
CREATE INDEX IF NOT EXISTS idx_restaurants_name_trgm
  ON public.restaurants USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS idx_restaurants_cuisine_trgm
  ON public.restaurants USING gin (cuisine_type gin_trgm_ops);

-- ── get_active_orders_summary ────────────────────────────────────────────────
-- Returns per-status counts of all active (non-delivered/cancelled) orders.
-- Used by the AI voice assistant admin context — avoids full table scan.
CREATE OR REPLACE FUNCTION public.get_active_orders_summary()
RETURNS TABLE(status TEXT, count BIGINT)
LANGUAGE SQL
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT status::TEXT, COUNT(*) AS count
  FROM public.orders
  WHERE status NOT IN ('delivered', 'cancelled')
  GROUP BY status;
$$;

-- ── get_financial_statistics ─────────────────────────────────────────────────
-- Single-pass aggregate for the admin financial dashboard.
-- Replaces fetching every delivered order row into Flutter memory.
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
                                THEN commission_amount ELSE 0 END), 0)
  )
  FROM public.orders
  WHERE status = 'delivered';
$$;

-- Revoke direct public access; only service_role / app can call
REVOKE ALL ON FUNCTION public.get_active_orders_summary() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_financial_statistics()   FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_orders_summary() TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.get_financial_statistics()  TO service_role, authenticated;

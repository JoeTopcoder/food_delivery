-- Customer Priority Delivery — an optional paid upgrade that prioritises an
-- order's handling. The fee is a HotBite DELIVERY charge, kept financially
-- separate from delivery_fee, restaurant payout and driver float. Enforced
-- server-side in the place-order edge function (like peak_fee). This migration
-- only adds the config + storage columns.

-- ── Admin-configurable settings (reuses app_config) ───────────────────────
INSERT INTO public.app_config (key, value) VALUES
  ('priority_delivery_enabled', 'false'),
  ('priority_delivery_fee', '300')
ON CONFLICT (key) DO NOTHING;

-- ── Order columns (safe defaults; existing orders read as Standard) ───────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_priority boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS priority_fee numeric NOT NULL DEFAULT 0,
  -- Tracks whether HotBite actually delivered the priority handling that was
  -- paid for. Drives refund eligibility; separate from the order status.
  ADD COLUMN IF NOT EXISTS priority_service_status text NOT NULL DEFAULT 'none'
    CHECK (priority_service_status IN
      ('none','requested','fulfilled','not_fulfilled','cancelled','under_review')),
  ADD COLUMN IF NOT EXISTS priority_selected_at timestamptz;

-- Guard against an inconsistent state: a fee without the flag, or vice-versa.
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname='orders_priority_consistent') THEN
    ALTER TABLE public.orders ADD CONSTRAINT orders_priority_consistent
      CHECK ((is_priority = true AND priority_fee >= 0)
          OR (is_priority = false AND priority_fee = 0));
  END IF;
END $$;

-- Admin priority-revenue / volume view (real data, no mock analytics).
CREATE OR REPLACE VIEW public.priority_delivery_stats AS
  SELECT
    date_trunc('day', o.created_at)      AS day,
    count(*) FILTER (WHERE o.is_priority)                          AS priority_orders,
    count(*)                                                       AS total_orders,
    COALESCE(sum(o.priority_fee) FILTER (WHERE o.is_priority),0)   AS priority_revenue,
    COALESCE(sum(o.delivery_fee),0)                                AS delivery_revenue,
    count(*) FILTER (WHERE o.is_priority AND o.status='cancelled') AS priority_cancellations
  FROM public.orders o
  GROUP BY 1;

NOTIFY pgrst, 'reload schema';

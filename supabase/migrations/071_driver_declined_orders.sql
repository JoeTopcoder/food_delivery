-- Driver declined orders tracking
-- When a driver declines an order, record it so it's hidden from them for 5 minutes.
-- If no other driver accepts within 5 minutes, the order reappears for the declining driver.

CREATE TABLE IF NOT EXISTS public.driver_declined_orders (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  driver_id uuid NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  order_id uuid NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  declined_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(driver_id, order_id)
);

-- Index for fast lookups by driver + recency
CREATE INDEX idx_declined_orders_driver_time
  ON public.driver_declined_orders(driver_id, declined_at DESC);

-- RLS
ALTER TABLE public.driver_declined_orders ENABLE ROW LEVEL SECURITY;

-- Drivers can insert their own declines
CREATE POLICY "drivers_insert_own_declines"
  ON public.driver_declined_orders FOR INSERT
  WITH CHECK (
    driver_id IN (
      SELECT id FROM public.drivers WHERE user_id = auth.uid()
    )
  );

-- Drivers can read their own declines
CREATE POLICY "drivers_select_own_declines"
  ON public.driver_declined_orders FOR SELECT
  USING (
    driver_id IN (
      SELECT id FROM public.drivers WHERE user_id = auth.uid()
    )
  );

-- Admin can see all
CREATE POLICY "admin_all_declines"
  ON public.driver_declined_orders FOR ALL
  USING (public.is_admin());

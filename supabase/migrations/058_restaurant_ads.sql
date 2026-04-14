-- ============================================================
-- Migration 058: Restaurant Ads / Promotions
-- Admin can create ads per restaurant; customers see them as
-- featured popups. Orders from ads get +5% commission boost.
-- ============================================================

-- 1. Create restaurant_ads table
CREATE TABLE IF NOT EXISTS public.restaurant_ads (
    id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
    title       TEXT NOT NULL,               -- e.g. "Buy 1, get 1 at Mediterranean Grill"
    description TEXT,                        -- e.g. "Gyro Sandwich Combo · At select locations"
    image_url   TEXT,                        -- optional hero image
    is_active   BOOLEAN NOT NULL DEFAULT true,
    starts_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
    ends_at     TIMESTAMPTZ,                 -- NULL = runs indefinitely
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 2. Add from_ad flag to orders so we know commission should be boosted
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS from_ad BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS ad_id UUID REFERENCES public.restaurant_ads(id);

-- 3. Index for fast active-ads lookup
CREATE INDEX IF NOT EXISTS idx_restaurant_ads_active
  ON public.restaurant_ads (is_active, starts_at, ends_at)
  WHERE is_active = true;

CREATE INDEX IF NOT EXISTS idx_restaurant_ads_restaurant
  ON public.restaurant_ads (restaurant_id);

-- 4. RLS policies
ALTER TABLE public.restaurant_ads ENABLE ROW LEVEL SECURITY;

-- Everyone can read active ads
CREATE POLICY "Anyone can read active ads"
  ON public.restaurant_ads FOR SELECT
  USING (true);

-- Only admins can insert/update/delete
CREATE POLICY "Admins can manage ads"
  ON public.restaurant_ads FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE users.id = auth.uid()
        AND users.role = 'admin'
    )
  );

-- 5. Updated_at trigger
CREATE OR REPLACE FUNCTION public.update_restaurant_ads_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_restaurant_ads_updated_at ON public.restaurant_ads;
CREATE TRIGGER trg_restaurant_ads_updated_at
    BEFORE UPDATE ON public.restaurant_ads
    FOR EACH ROW EXECUTE FUNCTION public.update_restaurant_ads_updated_at();

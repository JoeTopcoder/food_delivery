-- ====================================================================
-- 081: HIGH-PERFORMANCE DRIVER INTELLIGENCE SYSTEM
-- Smart scoring, hybrid pay, stacking, performance tiers, surge zones
-- ====================================================================

-- ── 1. driver_stats — rolling performance & tier tracking ───────────
CREATE TABLE IF NOT EXISTS public.driver_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL UNIQUE REFERENCES public.drivers(id) ON DELETE CASCADE,
  -- Rolling performance metrics
  acceptance_rate DOUBLE PRECISION DEFAULT 0,
  completion_rate DOUBLE PRECISION DEFAULT 0,
  on_time_rate DOUBLE PRECISION DEFAULT 0,
  avg_delivery_minutes DOUBLE PRECISION DEFAULT 0,
  avg_customer_rating DOUBLE PRECISION DEFAULT 0,
  avg_tip_percent DOUBLE PRECISION DEFAULT 0,
  total_tips DOUBLE PRECISION DEFAULT 0,
  total_distance_km DOUBLE PRECISION DEFAULT 0,
  total_active_minutes DOUBLE PRECISION DEFAULT 0,
  orders_today INTEGER DEFAULT 0,
  orders_this_week INTEGER DEFAULT 0,
  orders_accepted INTEGER DEFAULT 0,
  orders_declined INTEGER DEFAULT 0,
  -- Tier system
  driver_score DOUBLE PRECISION DEFAULT 50,
  tier TEXT NOT NULL DEFAULT 'bronze' CHECK (tier IN ('bronze','silver','gold','elite')),
  tier_updated_at TIMESTAMPTZ,
  -- Earnings floor tracking
  hourly_earnings_current DOUBLE PRECISION DEFAULT 0,
  active_session_start TIMESTAMPTZ,
  session_earnings DOUBLE PRECISION DEFAULT 0,
  session_active_minutes DOUBLE PRECISION DEFAULT 0,
  floor_topup_total DOUBLE PRECISION DEFAULT 0,
  -- Incentive multiplier
  bonus_multiplier DOUBLE PRECISION DEFAULT 1.0,
  priority_dispatch BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_driver_stats_driver ON public.driver_stats(driver_id);
CREATE INDEX idx_driver_stats_tier ON public.driver_stats(tier);
CREATE INDEX idx_driver_stats_score ON public.driver_stats(driver_score DESC);

-- ── 2. zones — demand/surge zones ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.zones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  latitude DOUBLE PRECISION NOT NULL,
  longitude DOUBLE PRECISION NOT NULL,
  radius_km DOUBLE PRECISION NOT NULL DEFAULT 3.0,
  -- Demand metrics
  active_orders INTEGER DEFAULT 0,
  available_drivers INTEGER DEFAULT 0,
  demand_level TEXT DEFAULT 'normal' CHECK (demand_level IN ('low','normal','moderate','high','critical')),
  surge_multiplier DOUBLE PRECISION DEFAULT 1.0,
  -- Metadata
  is_active BOOLEAN DEFAULT TRUE,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_zones_active ON public.zones(is_active);
CREATE INDEX idx_zones_surge ON public.zones(surge_multiplier);

-- ── 3. driver_earnings — per-delivery detailed breakdown ───────────
CREATE TABLE IF NOT EXISTS public.driver_earnings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  -- Hybrid pay breakdown
  distance_pay DOUBLE PRECISION DEFAULT 0,
  time_pay DOUBLE PRECISION DEFAULT 0,
  wait_pay DOUBLE PRECISION DEFAULT 0,
  base_pay DOUBLE PRECISION DEFAULT 0,
  boost_pay DOUBLE PRECISION DEFAULT 0,
  surge_pay DOUBLE PRECISION DEFAULT 0,
  tip DOUBLE PRECISION DEFAULT 0,
  floor_topup DOUBLE PRECISION DEFAULT 0,
  total_payout DOUBLE PRECISION DEFAULT 0,
  -- Metrics
  distance_km DOUBLE PRECISION DEFAULT 0,
  duration_minutes DOUBLE PRECISION DEFAULT 0,
  earnings_per_km DOUBLE PRECISION DEFAULT 0,
  earnings_per_hour DOUBLE PRECISION DEFAULT 0,
  -- Stacking
  is_stacked BOOLEAN DEFAULT FALSE,
  stack_group_id UUID,
  stack_position INTEGER DEFAULT 1,
  -- Timestamps
  earned_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_driver_earnings_driver ON public.driver_earnings(driver_id);
CREATE INDEX idx_driver_earnings_order ON public.driver_earnings(order_id);
CREATE INDEX idx_driver_earnings_date ON public.driver_earnings(earned_at);
CREATE INDEX idx_driver_earnings_stack ON public.driver_earnings(stack_group_id) WHERE stack_group_id IS NOT NULL;

-- ── 4. restaurant_prep_stats — track wait times per restaurant ─────
CREATE TABLE IF NOT EXISTS public.restaurant_prep_stats (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL UNIQUE REFERENCES public.restaurants(id) ON DELETE CASCADE,
  avg_prep_minutes DOUBLE PRECISION DEFAULT 15,
  median_prep_minutes DOUBLE PRECISION DEFAULT 12,
  p90_prep_minutes DOUBLE PRECISION DEFAULT 25,
  total_orders_tracked INTEGER DEFAULT 0,
  slow_order_count INTEGER DEFAULT 0,
  is_slow_flag BOOLEAN DEFAULT FALSE,
  auto_cancel_minutes INTEGER DEFAULT 30,
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_rest_prep_stats_restaurant ON public.restaurant_prep_stats(restaurant_id);

-- ── 5. order_scores — cached per-order scoring results ─────────────
CREATE TABLE IF NOT EXISTS public.order_scores (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  -- Score output
  score INTEGER NOT NULL DEFAULT 50 CHECK (score >= 0 AND score <= 100),
  label TEXT NOT NULL DEFAULT 'Good',
  -- Calculated metrics
  earnings_per_km DOUBLE PRECISION DEFAULT 0,
  earnings_per_hour DOUBLE PRECISION DEFAULT 0,
  estimated_payout DOUBLE PRECISION DEFAULT 0,
  estimated_minutes DOUBLE PRECISION DEFAULT 0,
  distance_km DOUBLE PRECISION DEFAULT 0,
  -- Input factors
  base_pay DOUBLE PRECISION DEFAULT 0,
  estimated_tip DOUBLE PRECISION DEFAULT 0,
  surge_multiplier DOUBLE PRECISION DEFAULT 1.0,
  restaurant_prep_minutes DOUBLE PRECISION DEFAULT 15,
  traffic_factor DOUBLE PRECISION DEFAULT 1.0,
  -- Decision recommendation
  recommendation TEXT DEFAULT 'neutral' CHECK (recommendation IN ('strong_accept','accept','neutral','reject')),
  reject_reason TEXT,
  alternative_zone TEXT,
  -- Timestamps
  scored_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_scores_order ON public.order_scores(order_id);
CREATE INDEX idx_order_scores_score ON public.order_scores(score DESC);

-- ── 6. order_stacks — batched multi-delivery groups ────────────────
CREATE TABLE IF NOT EXISTS public.order_stacks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
  order_ids UUID[] NOT NULL DEFAULT '{}',
  -- Route optimization
  total_distance_km DOUBLE PRECISION DEFAULT 0,
  total_payout DOUBLE PRECISION DEFAULT 0,
  estimated_minutes DOUBLE PRECISION DEFAULT 0,
  payout_increase_pct DOUBLE PRECISION DEFAULT 0,
  max_delay_minutes DOUBLE PRECISION DEFAULT 0,
  -- Status
  status TEXT DEFAULT 'proposed' CHECK (status IN ('proposed','accepted','in_progress','completed','expired')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ
);

CREATE INDEX idx_order_stacks_driver ON public.order_stacks(driver_id);
CREATE INDEX idx_order_stacks_status ON public.order_stacks(status);

-- ── 7. Add new columns to drivers table ────────────────────────────
DO $$ BEGIN
  ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS tier TEXT DEFAULT 'bronze';
  ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS driver_score DOUBLE PRECISION DEFAULT 50;
  ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS acceptance_rate DOUBLE PRECISION DEFAULT 0;
  ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS on_time_rate DOUBLE PRECISION DEFAULT 0;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ── 8. Add driver_pay columns to orders ────────────────────────────
DO $$ BEGIN
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS driver_base_pay DOUBLE PRECISION DEFAULT 0;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS driver_distance_pay DOUBLE PRECISION DEFAULT 0;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS driver_time_pay DOUBLE PRECISION DEFAULT 0;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS driver_wait_pay DOUBLE PRECISION DEFAULT 0;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS driver_boost_pay DOUBLE PRECISION DEFAULT 0;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS driver_total_pay DOUBLE PRECISION DEFAULT 0;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS driver_surge_multiplier DOUBLE PRECISION DEFAULT 1.0;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS pickup_wait_minutes DOUBLE PRECISION;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS distance_km DOUBLE PRECISION;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS picked_up_at TIMESTAMPTZ;
  ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS stack_group_id UUID;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ── 9. Seed default zones (Cayman Islands) ─────────────────────────
INSERT INTO public.zones (name, latitude, longitude, radius_km, active_orders, available_drivers, demand_level, surge_multiplier) VALUES
  ('George Town Central', 19.2869, -81.3812, 3.0, 0, 0, 'normal', 1.0),
  ('Seven Mile Beach',    19.3508, -81.3913, 2.5, 0, 0, 'normal', 1.0),
  ('West Bay',            19.3720, -81.4095, 3.0, 0, 0, 'normal', 1.0),
  ('Bodden Town',         19.2812, -81.2558, 4.0, 0, 0, 'normal', 1.0),
  ('East End',            19.3025, -81.1038, 5.0, 0, 0, 'low', 1.0),
  ('North Side',          19.3512, -81.2053, 4.0, 0, 0, 'low', 1.0),
  ('Camana Bay',          19.3304, -81.3869, 2.0, 0, 0, 'normal', 1.0),
  ('Airport Area',        19.2928, -81.3576, 2.5, 0, 0, 'normal', 1.0)
ON CONFLICT DO NOTHING;

-- ── 10. Seed app_config for hybrid driver pay rates ────────────────
INSERT INTO public.app_config (key, value, value_type, description) VALUES
  ('driver_rate_per_km',        '1.20',  'number', 'Driver pay per km driven'),
  ('driver_rate_per_minute',    '0.15',  'number', 'Driver pay per minute of delivery'),
  ('driver_wait_pay_per_minute','0.10',  'number', 'Wait pay per minute at restaurant'),
  ('driver_base_pay_minimum',   '3.00',  'number', 'Minimum base pay per delivery'),
  ('driver_earnings_floor',     '20.00', 'number', 'Minimum hourly earnings guarantee'),
  ('driver_boost_amount',       '0.00',  'number', 'Current global boost amount'),
  ('driver_max_stack_orders',   '3',     'number', 'Maximum orders in a stack'),
  ('driver_stack_distance_km',  '2.0',   'number', 'Max additional distance for stacking'),
  ('driver_stack_min_increase', '0.30',  'number', 'Min payout increase % to stack (0.30 = 30%)'),
  ('driver_stack_max_delay',    '10',    'number', 'Max minutes delay per customer from stacking'),
  ('driver_tier_silver_score',  '60',    'number', 'Score threshold for Silver tier'),
  ('driver_tier_gold_score',    '75',    'number', 'Score threshold for Gold tier'),
  ('driver_tier_elite_score',   '90',    'number', 'Score threshold for Elite tier'),
  ('platform_commission_cap',   '0.85',  'number', 'Max % of delivery fee that goes to driver'),
  ('platform_service_fee_pct',  '0.10',  'number', 'Service fee charged to customer (10%)'),
  ('restaurant_commission_pct', '0.15',  'number', 'Commission on restaurant orders (15%)')
ON CONFLICT (key) DO NOTHING;

-- ── 11. RLS policies ───────────────────────────────────────────────
ALTER TABLE public.driver_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.zones ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_earnings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.restaurant_prep_stats ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_scores ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_stacks ENABLE ROW LEVEL SECURITY;

-- driver_stats: driver can read their own, service role can write
CREATE POLICY "Drivers read own stats" ON public.driver_stats
  FOR SELECT USING (
    driver_id IN (SELECT id FROM public.drivers WHERE user_id = auth.uid())
  );

CREATE POLICY "Service role manages driver_stats" ON public.driver_stats
  FOR ALL USING (auth.role() = 'service_role');

-- zones: everyone can read
CREATE POLICY "Anyone can read zones" ON public.zones
  FOR SELECT USING (true);

CREATE POLICY "Service role manages zones" ON public.zones
  FOR ALL USING (auth.role() = 'service_role');

-- driver_earnings: driver reads own
CREATE POLICY "Drivers read own earnings" ON public.driver_earnings
  FOR SELECT USING (
    driver_id IN (SELECT id FROM public.drivers WHERE user_id = auth.uid())
  );

CREATE POLICY "Service role manages driver_earnings" ON public.driver_earnings
  FOR ALL USING (auth.role() = 'service_role');

-- restaurant_prep_stats: anyone can read
CREATE POLICY "Anyone can read prep stats" ON public.restaurant_prep_stats
  FOR SELECT USING (true);

CREATE POLICY "Service role manages prep stats" ON public.restaurant_prep_stats
  FOR ALL USING (auth.role() = 'service_role');

-- order_scores: driver can read
CREATE POLICY "Drivers read order scores" ON public.order_scores
  FOR SELECT USING (true);

CREATE POLICY "Service role manages order_scores" ON public.order_scores
  FOR ALL USING (auth.role() = 'service_role');

-- order_stacks: driver reads own
CREATE POLICY "Drivers read own stacks" ON public.order_stacks
  FOR SELECT USING (
    driver_id IN (SELECT id FROM public.drivers WHERE user_id = auth.uid())
  );

CREATE POLICY "Service role manages order_stacks" ON public.order_stacks
  FOR ALL USING (auth.role() = 'service_role');

-- ── 12. Function: calculate_driver_score ───────────────────────────
CREATE OR REPLACE FUNCTION public.calculate_driver_score(p_driver_id UUID)
RETURNS TABLE(score DOUBLE PRECISION, tier TEXT) AS $$
DECLARE
  v_acceptance DOUBLE PRECISION;
  v_completion DOUBLE PRECISION;
  v_ontime DOUBLE PRECISION;
  v_rating DOUBLE PRECISION;
  v_score DOUBLE PRECISION;
  v_tier TEXT;
  v_silver DOUBLE PRECISION;
  v_gold DOUBLE PRECISION;
  v_elite DOUBLE PRECISION;
BEGIN
  SELECT ds.acceptance_rate, ds.completion_rate, ds.on_time_rate, ds.avg_customer_rating
  INTO v_acceptance, v_completion, v_ontime, v_rating
  FROM public.driver_stats ds WHERE ds.driver_id = p_driver_id;

  IF NOT FOUND THEN
    RETURN QUERY SELECT 50.0::DOUBLE PRECISION, 'bronze'::TEXT;
    RETURN;
  END IF;

  -- Weighted score: completion 30%, on_time 25%, rating 25%, acceptance 20%
  v_score := (COALESCE(v_completion, 0) * 0.30 +
              COALESCE(v_ontime, 0) * 0.25 +
              COALESCE(v_rating, 0) / 5.0 * 100 * 0.25 +
              COALESCE(v_acceptance, 0) * 0.20);
  v_score := GREATEST(0, LEAST(100, v_score));

  -- Get tier thresholds from config
  SELECT COALESCE((SELECT c.value::DOUBLE PRECISION FROM public.app_config c WHERE c.key = 'driver_tier_silver_score'), 60) INTO v_silver;
  SELECT COALESCE((SELECT c.value::DOUBLE PRECISION FROM public.app_config c WHERE c.key = 'driver_tier_gold_score'), 75) INTO v_gold;
  SELECT COALESCE((SELECT c.value::DOUBLE PRECISION FROM public.app_config c WHERE c.key = 'driver_tier_elite_score'), 90) INTO v_elite;

  IF v_score >= v_elite THEN v_tier := 'elite';
  ELSIF v_score >= v_gold THEN v_tier := 'gold';
  ELSIF v_score >= v_silver THEN v_tier := 'silver';
  ELSE v_tier := 'bronze';
  END IF;

  -- Update driver
  UPDATE public.drivers SET driver_score = v_score, tier = v_tier WHERE id = p_driver_id;
  UPDATE public.driver_stats SET driver_score = v_score, tier = v_tier, tier_updated_at = NOW(), updated_at = NOW() WHERE driver_stats.driver_id = p_driver_id;

  RETURN QUERY SELECT v_score, v_tier;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

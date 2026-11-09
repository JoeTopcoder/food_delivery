-- Configurable driver pay by delivery distance. Admins define distance ranges,
-- each paying either a FLAT amount (JMD) or a PERCENT of the order's delivery
-- fee. One row is the DEFAULT (is_default), used when a delivery's distance
-- falls outside every range. Seeded with a single default = 80% so driver pay
-- is unchanged until an admin adds ranges.
BEGIN;

CREATE TABLE IF NOT EXISTS driver_pay_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  label text,
  min_km numeric,                       -- inclusive; NULL on the default row
  max_km numeric,                       -- inclusive; NULL on the default row
  pay_type text NOT NULL CHECK (pay_type IN ('flat','percent')),
  -- flat  -> JMD paid to the driver (e.g. 600)
  -- percent -> percentage 0..100 of the delivery fee (e.g. 80)
  amount numeric NOT NULL CHECK (amount >= 0),
  is_default boolean NOT NULL DEFAULT false,
  is_active boolean NOT NULL DEFAULT true,
  sort_order int NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_driver_pay_tiers_range
  ON driver_pay_tiers (is_active, min_km, max_km);

-- Exactly one active default row. Seed it from the current driver_pay_percent.
INSERT INTO driver_pay_tiers (label, pay_type, amount, is_default, sort_order)
SELECT 'Default (out of range)', 'percent',
       round(COALESCE((SELECT value::numeric FROM app_config WHERE key='driver_pay_percent'), 0.80) * 100, 2),
       true, 1000
WHERE NOT EXISTS (SELECT 1 FROM driver_pay_tiers WHERE is_default);

-- ── Resolver: the driver's base pay for a delivery of p_distance_km whose order
-- charged p_delivery_fee. Matches the first active range tier containing the
-- distance; otherwise the active default; otherwise the global config percent.
CREATE OR REPLACE FUNCTION resolve_driver_pay(
  p_distance_km numeric,
  p_delivery_fee numeric
) RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  t driver_pay_tiers;
  fee numeric := COALESCE(p_delivery_fee, 0);
  pay numeric;
BEGIN
  SELECT * INTO t FROM driver_pay_tiers
   WHERE is_active AND NOT is_default
     AND p_distance_km IS NOT NULL
     AND min_km IS NOT NULL AND max_km IS NOT NULL
     AND p_distance_km >= min_km AND p_distance_km <= max_km
   ORDER BY sort_order, min_km
   LIMIT 1;

  IF NOT FOUND THEN
    SELECT * INTO t FROM driver_pay_tiers
     WHERE is_active AND is_default
     ORDER BY sort_order LIMIT 1;
  END IF;

  IF NOT FOUND THEN
    RETURN round((fee * COALESCE(
      (SELECT value::numeric FROM app_config WHERE key='driver_pay_percent'), 0.80))::numeric, 2);
  END IF;

  IF t.pay_type = 'flat' THEN
    pay := t.amount;
  ELSE
    pay := fee * t.amount / 100.0;
  END IF;
  RETURN round(COALESCE(pay, 0)::numeric, 2);
END;
$$;

GRANT EXECUTE ON FUNCTION resolve_driver_pay(numeric, numeric) TO authenticated, service_role, anon;

-- ── RLS: anyone signed in can read the tiers (admin UI + previews); only admins
-- can change them.
ALTER TABLE driver_pay_tiers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS driver_pay_tiers_read ON driver_pay_tiers;
CREATE POLICY driver_pay_tiers_read ON driver_pay_tiers
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS driver_pay_tiers_write ON driver_pay_tiers;
CREATE POLICY driver_pay_tiers_write ON driver_pay_tiers
  FOR ALL TO authenticated USING (is_admin()) WITH CHECK (is_admin());

COMMIT;

NOTIFY pgrst, 'reload schema';

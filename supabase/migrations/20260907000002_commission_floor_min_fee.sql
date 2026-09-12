-- Migration: commission floor and a liveable delivery minimum
--
-- COMMISSION FLOOR 12%
-- Commission is the platform's actual profit engine — delivery is close to
-- margin-neutral because the driver takes a fixed share of whatever is
-- collected. Modelling the current pricing showed margin falling out of the
-- 10-25% band at roughly 9% commission on a typical basket, so 12% is the
-- floor with a little headroom. Enforced as a CHECK so nobody can discount a
-- restaurant into unprofitability during a negotiation.
--
-- MINIMUM DELIVERY FEE 3.00 -> 4.50
-- The driver receives 80% of the delivery fee. At a $3.00 floor that is $2.40,
-- which does not sustain a long trip once fuel is counted — the clamp, not the
-- rate, is what starves drivers on distance. $4.50 pays $3.60. Deliberately
-- modest: it raises customer cost, so it is a starting point to tune with real
-- driver retention data rather than a final answer.
--
-- Driver share stays at 80%: it barely moves platform margin (17.3% -> 15.0%
-- across the whole 80-100% range) and cutting it is the fastest way to lose
-- drivers.

-- Lift anything already below the floor before the constraint is added.
UPDATE public.restaurants
SET    commission_rate = 0.12
WHERE  commission_rate IS NOT NULL AND commission_rate < 0.12;

ALTER TABLE public.restaurants
  DROP CONSTRAINT IF EXISTS restaurants_commission_floor;

ALTER TABLE public.restaurants
  ADD CONSTRAINT restaurants_commission_floor
  CHECK (commission_rate IS NULL OR commission_rate >= 0.12);

COMMENT ON CONSTRAINT restaurants_commission_floor ON public.restaurants IS
  'Below ~12% a typical order falls out of the 10-25% target margin band. '
  'Commission is the profit engine; delivery is near margin-neutral.';

UPDATE public.app_config SET value = '4.5', updated_at = now()
WHERE key = 'min_delivery_fee';

NOTIFY pgrst, 'reload schema';

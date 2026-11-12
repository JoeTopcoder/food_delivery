-- Loyalty "punch card": every 6 successful orders a customer places earns them
-- a 50% discount coupon for their next order. The order success page shows a
-- 6-dot progress bar; the 6th dot fills and the reward is auto-issued.
--
-- Reward is a user_coupon (user-scoped, single-use, redeemed by code through the
-- existing validate-promo edge function — same path as the other coupons).
BEGIN;

-- ── Config (admin-tunable) ───────────────────────────────────────────────────
INSERT INTO app_config (key, value, category, updated_at) VALUES
  ('loyalty_streak_enabled',  'true', 'general', now()),
  ('loyalty_streak_size',     '6',    'general', now()),
  ('loyalty_streak_discount', '50',   'general', now())
ON CONFLICT (key) DO NOTHING;

-- ── Progress table ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.order_loyalty_streaks (
  user_id        uuid PRIMARY KEY REFERENCES public.users(id) ON DELETE CASCADE,
  order_count    integer NOT NULL DEFAULT 0,   -- lifetime counted orders
  rewards_issued integer NOT NULL DEFAULT 0,   -- how many 6-cycles already rewarded
  updated_at     timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.order_loyalty_streaks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS loyalty_streak_select_own ON public.order_loyalty_streaks;
CREATE POLICY loyalty_streak_select_own ON public.order_loyalty_streaks
  FOR SELECT USING (user_id = auth.uid() OR is_admin());
-- No INSERT/UPDATE/DELETE policies: only the SECURITY DEFINER trigger writes.

-- ── Tick on each successful order ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.order_loyalty_tick()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_enabled  boolean;
  v_size     integer;
  v_discount integer;
  v_count    integer;
  v_issued   integer;
  v_new_rwd  integer;
  v_code     text;
BEGIN
  -- Only real, single-restaurant customer orders count. Draft carts, orders
  -- with no user, and multi-restaurant group children are excluded so the
  -- streak can't be inflated.
  IF NEW.status = 'draft' OR NEW.user_id IS NULL OR NEW.order_group_id IS NOT NULL THEN
    RETURN NEW;
  END IF;

  v_enabled := COALESCE((SELECT value FROM app_config WHERE key='loyalty_streak_enabled'),'true') = 'true';
  IF NOT v_enabled THEN
    RETURN NEW;
  END IF;

  v_size     := COALESCE((SELECT value::int FROM app_config WHERE key='loyalty_streak_size'), 6);
  v_discount := COALESCE((SELECT value::int FROM app_config WHERE key='loyalty_streak_discount'), 50);
  IF v_size < 1 THEN v_size := 6; END IF;

  INSERT INTO public.order_loyalty_streaks (user_id, order_count)
  VALUES (NEW.user_id, 1)
  ON CONFLICT (user_id) DO UPDATE
    SET order_count = public.order_loyalty_streaks.order_count + 1,
        updated_at  = now()
  RETURNING order_count, rewards_issued INTO v_count, v_issued;

  v_new_rwd := v_count / v_size;  -- integer division: completed cycles

  IF v_new_rwd > v_issued THEN
    -- Issue one 50% coupon per newly completed cycle (normally exactly one).
    WHILE v_issued < v_new_rwd LOOP
      v_code := 'LOYAL' || v_discount || upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
      INSERT INTO public.user_coupons
        (user_id, code, discount_percent, discount_amount, min_order, reason, is_used, expires_at, created_at)
      VALUES
        (NEW.user_id, v_code, v_discount, 0, 0,
         '🎉 Loyalty reward — ' || v_discount || '% off your next order!',
         false, now() + interval '30 days', now());
      v_issued := v_issued + 1;
    END LOOP;

    UPDATE public.order_loyalty_streaks
       SET rewards_issued = v_new_rwd, updated_at = now()
     WHERE user_id = NEW.user_id;
  END IF;

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Never block the order on a loyalty error.
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_order_loyalty_tick ON public.orders;
CREATE TRIGGER trg_order_loyalty_tick
  AFTER INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.order_loyalty_tick();

-- ── Progress + reward read for the app ───────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_loyalty_streak(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_uid      uuid;
  v_size     integer;
  v_discount integer;
  v_enabled  boolean;
  v_count    integer;
  v_filled   integer;
  v_code     text;
BEGIN
  v_uid := COALESCE(auth.uid(), p_user_id);  -- pin to caller
  v_enabled := COALESCE((SELECT value FROM app_config WHERE key='loyalty_streak_enabled'),'true') = 'true';
  v_size     := COALESCE((SELECT value::int FROM app_config WHERE key='loyalty_streak_size'), 6);
  v_discount := COALESCE((SELECT value::int FROM app_config WHERE key='loyalty_streak_discount'), 50);
  IF v_size < 1 THEN v_size := 6; END IF;

  v_count := COALESCE((SELECT order_count FROM order_loyalty_streaks WHERE user_id = v_uid), 0);

  -- Dots filled for the CURRENT cycle: 1..size, and exactly `size` on the order
  -- that just completed a cycle (so the bar shows "full" with the reward).
  v_filled := CASE WHEN v_count = 0 THEN 0 ELSE ((v_count - 1) % v_size) + 1 END;

  -- Newest unused, unexpired loyalty reward (if any) for this user.
  SELECT code INTO v_code
  FROM user_coupons
  WHERE user_id = v_uid AND is_used = false AND expires_at > now()
    AND reason ILIKE '%Loyalty reward%'
  ORDER BY created_at DESC
  LIMIT 1;

  RETURN jsonb_build_object(
    'enabled',      v_enabled,
    'size',         v_size,
    'discount',     v_discount,
    'order_count',  v_count,
    'filled',       v_filled,
    'reward_ready', v_code IS NOT NULL,
    'reward_code',  v_code
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_loyalty_streak(uuid) TO authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';

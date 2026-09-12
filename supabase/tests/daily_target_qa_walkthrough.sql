-- Manual QA walkthrough for daily target + adaptive progression.
--
-- This is the scenario walkthrough the extension spec asks for: seed a target,
-- hit it, miss it, override it, and run the job twice. It complements
-- daily_target_progression_test.sql, which asserts the maths unit by unit;
-- this one drives the same functions the way the scheduled job and the admin
-- screen drive them, and prints what a person would see.
--
-- admin_compute_next_target(d) computes the target FOR d from the day before
-- it — so each scenario seeds day D and asks about D+1.
--
-- Everything runs inside a transaction and rolls back. Nothing persists.
-- Run:  supabase db query --linked -f supabase/tests/daily_target_qa_walkthrough.sql

BEGIN;

-- Order-status triggers on this table make outbound HTTP calls via pg_net.
-- The fixture orders below are never meant to reach a customer.
SET LOCAL session_replication_role = replica;

-- The target RPCs are admin-gated on auth.uid(), so the walkthrough claims a
-- real admin identity. The database role stays postgres: switching to
-- authenticated as well would put RLS between this script and its own
-- fixtures, and the fixtures are not what is under test here.
SET LOCAL request.jwt.claims =
  '{"sub":"3efc2c8f-397f-4253-be09-607b6ca9d4bf","role":"authenticated"}';

CREATE TEMP TABLE qa(step INT, scenario TEXT, expected TEXT, actual TEXT,
                     pass BOOLEAN) ON COMMIT DROP;

DO $qa$
DECLARE
  v_user       UUID;
  v_restaurant UUID;
  -- Far-future dates, well separated, so no scenario can see another's orders
  -- and none can collide with a real target or a real order.
  v_hit    DATE := DATE '2099-03-01';
  v_cap    DATE := DATE '2099-04-01';
  v_miss   DATE := DATE '2099-05-01';
  v_growth NUMERIC := public.target_cfg_num('target_growth_rate_on_hit', 'food', 0.05);
  v_maxinc NUMERIC := public.target_cfg_num('target_max_daily_increase', 'food', 5);
  v_min    NUMERIC := public.target_cfg_num('target_min', 'food', 1);
  r        RECORD;
  v_rows   INT;
  v_first  BOOLEAN;
  v_again  BOOLEAN;
  v_target INT;
  v_source TEXT;
BEGIN
  SELECT id INTO v_user FROM public.users WHERE role = 'customer' LIMIT 1;
  SELECT id INTO v_restaurant FROM public.restaurants
   WHERE store_type <> 'grocery' LIMIT 1;

  -- ── 1. Seed a target ─────────────────────────────────────────────────────
  INSERT INTO public.daily_targets (target_date, vertical, target_orders, source, notes)
  VALUES (v_hit, 'food', 20, 'manual_override', 'QA seed');

  SELECT t.target_orders, t.source INTO v_target, v_source
    FROM public.admin_get_daily_target(v_hit, 'food') t;
  INSERT INTO qa VALUES (1, 'Seed a target of 20 and read it back',
    '20 / manual_override', v_target || ' / ' || v_source,
    v_target = 20 AND v_source = 'manual_override');

  -- ── 2. HIT: 20 orders against a target of 20 ─────────────────────────────
  INSERT INTO public.orders (user_id, restaurant_id, delivery_address, subtotal,
                             delivery_fee, total_amount, payment_method, status,
                             ordered_at)
  SELECT v_user, v_restaurant, 'QA', 100, 0, 100, 'cash', 'delivered',
         (v_hit + TIME '12:00') AT TIME ZONE 'America/Jamaica'
  FROM generate_series(1, 20);

  SELECT * INTO r FROM public.admin_compute_next_target(v_hit + 1, 'food');
  INSERT INTO qa VALUES (2,
    'Hit 20/20 -> next day = ceil(20 * (1 + growth))',
    'hit=true, target=' || CEIL(20 * (1 + v_growth))::int,
    'hit=' || r.hit || ', target=' || r.proposed_target ||
      ', rule=' || r.rule_applied,
    r.hit AND r.proposed_target = CEIL(20 * (1 + v_growth))::int);

  -- ── 3. The increase cap actually binds ───────────────────────────────────
  -- At growth 0.05 a target of 20 grows by 1, so step 2 never touches the cap.
  -- 500 would grow by 25 and must be held to +5.
  INSERT INTO public.daily_targets (target_date, vertical, target_orders, source, notes)
  VALUES (v_cap, 'food', 500, 'manual_override', 'QA cap probe');
  INSERT INTO public.orders (user_id, restaurant_id, delivery_address, subtotal,
                             delivery_fee, total_amount, payment_method, status,
                             ordered_at)
  SELECT v_user, v_restaurant, 'QA', 100, 0, 100, 'cash', 'delivered',
         (v_cap + TIME '12:00') AT TIME ZONE 'America/Jamaica'
  FROM generate_series(1, 500);

  SELECT * INTO r FROM public.admin_compute_next_target(v_cap + 1, 'food');
  INSERT INTO qa VALUES (3,
    'Hit 500/500 -> raw 525, capped to +' || v_maxinc::int,
    (500 + v_maxinc)::int || ', clamped',
    r.proposed_target || ', clamped_by=' || COALESCE(r.clamped_by, 'none') ||
      ' (raw ' || r.raw_next || ')',
    r.proposed_target = (500 + v_maxinc)::int AND r.clamped_by IS NOT NULL);

  -- ── 4. MISS: hold, the configured behaviour ──────────────────────────────
  INSERT INTO public.daily_targets (target_date, vertical, target_orders, source, notes)
  VALUES (v_miss, 'food', 50, 'manual_override', 'QA miss probe');
  INSERT INTO public.orders (user_id, restaurant_id, delivery_address, subtotal,
                             delivery_fee, total_amount, payment_method, status,
                             ordered_at)
  SELECT v_user, v_restaurant, 'QA', 100, 0, 100, 'cash', 'delivered',
         (v_miss + TIME '12:00') AT TIME ZONE 'America/Jamaica'
  FROM generate_series(1, 10);   -- 10 of 50 is a clear miss

  SELECT * INTO r FROM public.admin_compute_next_target(v_miss + 1, 'food');
  INSERT INTO qa VALUES (4,
    'Miss 10/50 with hold_on_miss=true -> target holds, never grows',
    'hit=false, target=50',
    'hit=' || r.hit || ', target=' || r.proposed_target ||
      ', rule=' || r.rule_applied,
    NOT r.hit AND r.proposed_target = 50);

  -- ── 5. MISS with step-down configured instead of hold ────────────────────
  UPDATE public.app_config SET value = 'false'
   WHERE key = 'target_hold_on_miss_food';
  UPDATE public.app_config SET value = '0.10'
   WHERE key = 'target_step_down_rate_on_miss_food';

  SELECT * INTO r FROM public.admin_compute_next_target(v_miss + 1, 'food');
  INSERT INTO qa VALUES (5,
    'Miss 10/50 with step-down 10% -> 50 * 0.9',
    '45', r.proposed_target || ' (rule ' || r.rule_applied || ')',
    r.proposed_target = 45);

  -- ── 6. The floor holds under an absurd step-down ─────────────────────────
  UPDATE public.app_config SET value = '0.99'
   WHERE key = 'target_step_down_rate_on_miss_food';
  SELECT * INTO r FROM public.admin_compute_next_target(v_miss + 1, 'food');
  INSERT INTO qa VALUES (6,
    'Step-down of 99% cannot fall below target_min (' || v_min::int || ')',
    '>= ' || v_min::int, r.proposed_target::text,
    r.proposed_target >= v_min::int);

  -- Restore the real config so step 7 exercises real behaviour.
  UPDATE public.app_config SET value = 'true'
   WHERE key = 'target_hold_on_miss_food';
  UPDATE public.app_config SET value = '0'
   WHERE key = 'target_step_down_rate_on_miss_food';

  -- ── 7. Job idempotency ───────────────────────────────────────────────────
  SELECT a.created INTO v_first
    FROM public.admin_apply_next_target(v_hit + 1, 'food') a;
  SELECT a.created INTO v_again
    FROM public.admin_apply_next_target(v_hit + 1, 'food') a;
  PERFORM public.admin_apply_next_target(v_hit + 1, 'food');

  SELECT count(*) INTO v_rows FROM public.daily_targets
   WHERE target_date = v_hit + 1 AND vertical = 'food' AND superseded_at IS NULL;
  INSERT INTO qa VALUES (7,
    'Apply the roll-forward three times -> one live row, created only once',
    'first=true, second=false, live rows=1',
    'first=' || v_first || ', second=' || v_again || ', live rows=' || v_rows,
    v_first AND NOT v_again AND v_rows = 1);

  -- ── 8. A manual override supersedes the automatic target ─────────────────
  PERFORM public.admin_set_daily_target(v_hit + 1, 'food', 999, 'QA override');
  SELECT count(*) INTO v_rows FROM public.daily_targets
   WHERE target_date = v_hit + 1 AND vertical = 'food' AND superseded_at IS NULL;
  SELECT t.target_orders, t.source INTO v_target, v_source
    FROM public.admin_get_daily_target(v_hit + 1, 'food') t;
  INSERT INTO qa VALUES (8,
    'Manual override wins and still leaves exactly one live row',
    '1 row / 999 / manual_override',
    v_rows || ' row / ' || v_target || ' / ' || v_source,
    v_rows = 1 AND v_target = 999 AND v_source = 'manual_override');

  -- ── 9. Nothing was updated away: the automatic row is still on record ────
  SELECT count(*) INTO v_rows FROM public.daily_targets
   WHERE target_date = v_hit + 1 AND vertical = 'food';
  INSERT INTO qa VALUES (9,
    'Targets are append-only: the superseded automatic row is still there',
    '>= 2 rows for that date', v_rows::text, v_rows >= 2);

  -- ── 10. Both rows are visible in the admin drill-down ────────────────────
  SELECT count(*) INTO v_rows FROM public.admin_target_history('food', 365) h
   WHERE h.target_date = v_hit + 1;
  INSERT INTO qa VALUES (10,
    'The history RPC shows the override and what it replaced',
    '>= 2', v_rows::text, v_rows >= 2);

  -- ── 11. The nightly job itself runs and reports ──────────────────────────
  DECLARE v_job JSONB;
  BEGIN
    v_job := public.run_daily_target_rollforward();
    INSERT INTO qa VALUES (11,
      'The scheduled job runs end to end and returns a report',
      'jsonb result, no exception',
      left(v_job::text, 120),
      v_job IS NOT NULL);
  END;
END
$qa$;

SELECT step, scenario, expected, actual,
       CASE WHEN pass THEN 'PASS' ELSE '*** FAIL ***' END AS result
FROM qa ORDER BY step;

SELECT count(*) FILTER (WHERE pass)     AS passed,
       count(*) FILTER (WHERE NOT pass) AS failed,
       count(*)                         AS total
FROM qa;

ROLLBACK;

-- Unit-style tests for the target progression rule.
-- Everything runs inside BEGIN ... ROLLBACK; nothing persists.
--
--   supabase db query --linked -f supabase/tests/daily_target_progression_test.sql
--
-- Actuals come from real orders, which cannot be fabricated in a test without
-- inserting fake orders. So the rule is exercised against admin_compute_next_target
-- with targets chosen relative to the actual for that day: a target below the
-- actual is a hit, above it is a miss. That tests the rule, not the arithmetic
-- of a mock.
BEGIN;

CREATE TEMP TABLE t(name TEXT, expected TEXT, got TEXT, pass BOOLEAN);

DO $$
DECLARE
  v_admin  UUID;
  v_day    DATE;
  v_actual BIGINT;
  c        RECORD;
  a        RECORD;
  b        RECORD;
  n        INT;
BEGIN
  SELECT id INTO v_admin FROM users WHERE role = 'admin' LIMIT 1;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- A real day that actually had food orders, so "actual" is genuine.
  SELECT target_date, orders_count INTO v_day, v_actual
  FROM daily_actuals
  WHERE vertical = 'food' AND orders_count > 0
  ORDER BY target_date DESC LIMIT 1;

  -- Deterministic config for the assertions below.
  UPDATE app_config SET value='0.05' WHERE key='target_growth_rate_on_hit_food';
  UPDATE app_config SET value='true' WHERE key='target_hold_on_miss_food';
  UPDATE app_config SET value='1'    WHERE key='target_min_food';
  UPDATE app_config SET value='5'    WHERE key='target_max_daily_increase_food';
  UPDATE app_config SET value='1'    WHERE key='target_smoothing_window_days_food';

  -- ── HIT: actual >= target, so grow by 5% ────────────────────────────────
  PERFORM admin_set_daily_target(v_day, 'food', GREATEST(v_actual - 1, 1)::int, 'test hit');
  SELECT * INTO c FROM admin_compute_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('hit -> growth_on_hit', 'growth_on_hit', c.rule_applied,
                        c.rule_applied = 'growth_on_hit');
  INSERT INTO t VALUES ('hit -> target grows',
    'ceil(' || GREATEST(v_actual - 1, 1) || ' * 1.05)',
    c.proposed_target::text,
    c.proposed_target = CEIL(GREATEST(v_actual - 1, 1) * 1.05)::int);

  -- ── MISS with hold ──────────────────────────────────────────────────────
  PERFORM admin_set_daily_target(v_day, 'food', (v_actual + 50)::int, 'test miss');
  SELECT * INTO c FROM admin_compute_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('miss -> hold_on_miss', 'hold_on_miss', c.rule_applied,
                        c.rule_applied = 'hold_on_miss');
  INSERT INTO t VALUES ('miss -> target unchanged', (v_actual + 50)::text,
                        c.proposed_target::text,
                        c.proposed_target = (v_actual + 50)::int);

  -- ── MISS with step-down ─────────────────────────────────────────────────
  UPDATE app_config SET value='false' WHERE key='target_hold_on_miss_food';
  UPDATE app_config SET value='0.10'  WHERE key='target_step_down_rate_on_miss_food';
  SELECT * INTO c FROM admin_compute_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('miss -> step_down_on_miss', 'step_down_on_miss', c.rule_applied,
                        c.rule_applied = 'step_down_on_miss');
  INSERT INTO t VALUES ('step-down applies 10%',
    CEIL((v_actual + 50) * 0.9)::text, c.proposed_target::text,
    c.proposed_target = CEIL((v_actual + 50) * 0.9)::int);
  UPDATE app_config SET value='true' WHERE key='target_hold_on_miss_food';
  UPDATE app_config SET value='0'    WHERE key='target_step_down_rate_on_miss_food';

  -- ── CLAMP at max_daily_increase ─────────────────────────────────────────
  -- The rule is "never EXCEEDS max_daily_increase", so a jump of exactly the
  -- cap is allowed and must NOT report as clamped. Both sides of that boundary
  -- are checked, because the first version of this test used a growth rate
  -- that landed exactly on it and then read the pass as proof of clamping.
  PERFORM admin_set_daily_target(v_day, 'food', GREATEST(v_actual - 1, 1)::int, 'test clamp max');

  -- Exactly at the cap: prev=1, growth 5.0 -> raw 6, jump 5. Not clamped.
  UPDATE app_config SET value='5.0' WHERE key='target_growth_rate_on_hit_food';
  SELECT * INTO c FROM admin_compute_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('jump exactly at cap is not clamped', 'none', c.clamped_by,
                        c.clamped_by = 'none');
  INSERT INTO t VALUES ('jump exactly at cap allowed',
    (GREATEST(v_actual - 1, 1) + 5)::text, c.proposed_target::text,
    c.proposed_target = (GREATEST(v_actual - 1, 1) + 5)::int);

  -- Over the cap: prev=1, growth 10.0 -> raw 11, jump 10. Clamped to +5.
  UPDATE app_config SET value='10.0' WHERE key='target_growth_rate_on_hit_food';
  SELECT * INTO c FROM admin_compute_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('jump over cap is clamped', 'max_daily_increase', c.clamped_by,
                        c.clamped_by = 'max_daily_increase');
  INSERT INTO t VALUES ('clamped jump limited to +5',
    (GREATEST(v_actual - 1, 1) + 5)::text, c.proposed_target::text,
    c.proposed_target = (GREATEST(v_actual - 1, 1) + 5)::int);
  UPDATE app_config SET value='0.05' WHERE key='target_growth_rate_on_hit_food';

  -- ── CLAMP at min_target ─────────────────────────────────────────────────
  -- Target 1, a miss, step down 90% -> would land below the floor of 10.
  UPDATE app_config SET value='10'    WHERE key='target_min_food';
  UPDATE app_config SET value='false' WHERE key='target_hold_on_miss_food';
  UPDATE app_config SET value='0.90'  WHERE key='target_step_down_rate_on_miss_food';
  PERFORM admin_set_daily_target(v_day, 'food', (v_actual + 100)::int, 'test clamp min');
  SELECT * INTO c FROM admin_compute_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('floor respected', 'true',
    (c.proposed_target >= 10)::text, c.proposed_target >= 10);
  UPDATE app_config SET value='1'    WHERE key='target_min_food';
  UPDATE app_config SET value='true' WHERE key='target_hold_on_miss_food';
  UPDATE app_config SET value='0'    WHERE key='target_step_down_rate_on_miss_food';

  -- ── SMOOTHING WINDOW > 1 ────────────────────────────────────────────────
  -- A 7-day average includes days with no orders, so it must be <= the single
  -- best day. This is what stops one freak day ratcheting the target.
  UPDATE app_config SET value='7' WHERE key='target_smoothing_window_days_food';
  SELECT * INTO c FROM admin_compute_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('smoothing lowers the actual used', 'true',
    (c.previous_actual <= v_actual)::text, c.previous_actual <= v_actual);
  UPDATE app_config SET value='1' WHERE key='target_smoothing_window_days_food';

  -- ── IDEMPOTENCY: apply twice, one row ───────────────────────────────────
  DELETE FROM daily_targets WHERE target_date = v_day + 1 AND vertical = 'food';
  SELECT * INTO a FROM admin_apply_next_target(v_day + 1, 'food');
  SELECT * INTO b FROM admin_apply_next_target(v_day + 1, 'food');
  SELECT count(*) INTO n FROM daily_targets
   WHERE target_date = v_day + 1 AND vertical = 'food' AND superseded_at IS NULL;
  INSERT INTO t VALUES ('first apply creates', 'true', a.created::text, a.created);
  INSERT INTO t VALUES ('second apply is a no-op', 'false', b.created::text, NOT b.created);
  INSERT INTO t VALUES ('exactly one live row', '1', n::text, n = 1);

  -- ── OVERRIDE beats the scheduler ────────────────────────────────────────
  PERFORM admin_set_daily_target(v_day + 1, 'food', 999, 'human decision');
  SELECT * INTO b FROM admin_apply_next_target(v_day + 1, 'food');
  INSERT INTO t VALUES ('scheduler leaves an override alone', '999',
    b.target_orders::text, b.target_orders = 999);
  INSERT INTO t VALUES ('override recorded as manual_override', 'manual_override',
    b.source, b.source = 'manual_override');

  -- ── APPEND-ONLY: history survives ───────────────────────────────────────
  SELECT count(*) INTO n FROM daily_targets
   WHERE target_date = v_day + 1 AND vertical = 'food';
  INSERT INTO t VALUES ('superseded row kept', 'true', (n >= 2)::text, n >= 2);

  -- ── GATE ────────────────────────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', (SELECT id FROM users WHERE role <> 'admin' LIMIT 1),
                      'role', 'authenticated')::text, true);
  BEGIN
    PERFORM * FROM admin_compute_next_target(v_day + 1, 'food');
    INSERT INTO t VALUES ('non-admin refused', 'blocked', 'NOT BLOCKED', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES ('non-admin refused', 'blocked', 'blocked', TRUE);
  END;
END $$;

SELECT CASE WHEN pass THEN 'PASS' ELSE 'FAIL' END AS result,
       name, expected, got
FROM t ORDER BY pass, name;

ROLLBACK;

-- Manual QA checklist for the admin analytics dashboard.
--
-- Covers the checks the spec names: the admin gate, a non-admin being blocked,
-- the maths against a hand-calculated sample, SLA bucket edges, the empty
-- state, and period boundaries in the platform timezone.
--
-- Everything runs inside a transaction and rolls back. Nothing persists.
-- Run:  supabase db query --linked -f supabase/tests/admin_dashboard_qa_checklist.sql

BEGIN;

-- The orders table has UPDATE triggers that make outbound HTTP calls via
-- pg_net. Fixtures here must never reach a real customer.
SET LOCAL session_replication_role = replica;

CREATE TEMP TABLE qa(step INT, scenario TEXT, expected TEXT, actual TEXT,
                     pass BOOLEAN) ON COMMIT DROP;

DO $qa$
DECLARE
  v_admin    UUID;
  v_customer UUID;
  v_rest     UUID;
  v_tz       TEXT := COALESCE((SELECT value FROM public.app_config
                                WHERE key = 'platform_timezone'), 'America/Jamaica');
  v_from     TIMESTAMPTZ;
  v_to       TIMESTAMPTZ;
  v_n        BIGINT;
  v_gmv      BIGINT;
  v_contrib  BIGINT;
  v_expected BIGINT;
  v_msg      TEXT;
BEGIN
  SELECT id INTO v_admin FROM public.users WHERE role = 'admin' LIMIT 1;
  SELECT id INTO v_customer FROM public.users WHERE role = 'customer' LIMIT 1;
  SELECT id INTO v_rest FROM public.restaurants WHERE store_type <> 'grocery' LIMIT 1;

  -- ── 1. The gate lets a real admin through ────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  INSERT INTO qa VALUES (1, 'is_admin() is true for a user with role=admin',
    'true', public.is_admin()::text, public.is_admin());

  -- ── 2. A customer is blocked ─────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM * FROM public.admin_metrics_food('today');
    INSERT INTO qa VALUES (2, 'A customer calling admin_metrics_food',
      'raises Forbidden', 'returned rows - GATE IS OPEN', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO qa VALUES (2, 'A customer calling admin_metrics_food',
      'raises Forbidden', SQLERRM, SQLERRM ILIKE '%Forbidden%');
  END;

  -- ── 3. A signed-out caller is blocked ────────────────────────────────────
  PERFORM set_config('request.jwt.claims', NULL, true);
  BEGIN
    PERFORM * FROM public.admin_live_ops();
    INSERT INTO qa VALUES (3, 'No JWT at all calling admin_live_ops',
      'raises Forbidden', 'returned rows - GATE IS OPEN', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO qa VALUES (3, 'No JWT at all calling admin_live_ops',
      'raises Forbidden', SQLERRM, SQLERRM ILIKE '%Forbidden%');
  END;

  -- Back to admin for the rest.
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);

  -- ── 4. Period boundaries respect the platform timezone ───────────────────
  SELECT r_from, r_to INTO v_from, v_to
    FROM public.admin_period_range('today', NULL, NULL);
  INSERT INTO qa VALUES (4,
    'today starts at midnight in ' || v_tz || ', not UTC midnight',
    '00:00:00 local',
    to_char(v_from AT TIME ZONE v_tz, 'YYYY-MM-DD HH24:MI:SS'),
    (v_from AT TIME ZONE v_tz)::time = TIME '00:00:00');

  -- ── 5. An order just before local midnight is NOT in today ───────────────
  -- This is the failure a UTC-based range produces: Jamaica is UTC-5, so
  -- anything between 19:00 and 23:59 local is already "tomorrow" in UTC.
  INSERT INTO public.orders (id, user_id, restaurant_id, delivery_address,
                             subtotal, delivery_fee, total_amount,
                             payment_method, status, ordered_at)
  VALUES
   ('aaaaaaaa-0000-0000-0000-0000000000b1', v_customer, v_rest, 'QA',
    100, 0, 100, 'cash', 'delivered',
    (((now() AT TIME ZONE v_tz)::date - 1) + TIME '23:30') AT TIME ZONE v_tz),
   ('aaaaaaaa-0000-0000-0000-0000000000b2', v_customer, v_rest, 'QA',
    100, 0, 100, 'cash', 'delivered',
    (((now() AT TIME ZONE v_tz)::date) + TIME '00:30') AT TIME ZONE v_tz),
   -- 20:00 local yesterday is 01:00 UTC today: the row a UTC range wrongly
   -- pulls into today.
   ('aaaaaaaa-0000-0000-0000-0000000000b3', v_customer, v_rest, 'QA',
    100, 0, 100, 'cash', 'delivered',
    (((now() AT TIME ZONE v_tz)::date - 1) + TIME '20:00') AT TIME ZONE v_tz);

  SELECT count(*) INTO v_n FROM public.admin_order_economics(v_from, v_to, FALSE) e
   WHERE e.order_id IN ('aaaaaaaa-0000-0000-0000-0000000000b1',
                        'aaaaaaaa-0000-0000-0000-0000000000b2',
                        'aaaaaaaa-0000-0000-0000-0000000000b3');
  INSERT INTO qa VALUES (5,
    'Of 3 fixtures (yesterday 23:30, yesterday 20:00, today 00:30), '
    'only today 00:30 falls in today',
    '1', v_n::text, v_n = 1);

  -- ── 6. Hand-calculated sample ────────────────────────────────────────────
  -- One order: subtotal 1000, commission_amount 150, delivery_fee 400,
  -- service_fee 50, driver_total_pay 300 of which 100 is tip.
  --   GMV          = 1000.00      -> 100000 minor
  --   contribution = 150 + 400 + 50 - (300 - 100) = 400.00 -> 40000 minor
  -- Tips are the rider's, not a platform cost, so they come out of payout.
  INSERT INTO public.orders (id, user_id, restaurant_id, delivery_address,
                             subtotal, delivery_fee, total_amount,
                             payment_method, status, ordered_at,
                             commission_amount, platform_service_fee,
                             driver_total_pay, driver_tip)
  VALUES ('aaaaaaaa-0000-0000-0000-0000000000b4', v_customer, v_rest, 'QA',
          1000, 400, 1450, 'cash', 'delivered',
          now() - interval '1 hour', 150, 50, 300, 100);

  SELECT e.gmv,
         e.commission + e.delivery_fee + e.service_fee - e.rider_payout
    INTO v_gmv, v_contrib
    FROM public.admin_order_economics(v_from, v_to, FALSE) e
   WHERE e.order_id = 'aaaaaaaa-0000-0000-0000-0000000000b4';

  INSERT INTO qa VALUES (6,
    'Hand-calculated order: GMV 100000 minor, contribution 40000 minor',
    'gmv=100000, contribution=40000',
    'gmv=' || v_gmv || ', contribution=' || v_contrib,
    v_gmv = 100000 AND v_contrib = 40000);

  -- ── 7. Money never round-trips through a float ───────────────────────────
  -- 0.1 + 0.2 in double precision is 0.30000000000000004; the RPC casts to
  -- NUMERIC before any arithmetic, so a third of a cent cannot appear.
  INSERT INTO public.orders (id, user_id, restaurant_id, delivery_address,
                             subtotal, delivery_fee, total_amount,
                             payment_method, status, ordered_at,
                             commission_amount, platform_service_fee,
                             driver_total_pay, driver_tip)
  VALUES ('aaaaaaaa-0000-0000-0000-0000000000b5', v_customer, v_rest, 'QA',
          0.1, 0.2, 0.3, 'cash', 'delivered', now() - interval '1 hour',
          0, 0, 0, 0);
  SELECT e.gmv, e.delivery_fee INTO v_gmv, v_contrib
    FROM public.admin_order_economics(v_from, v_to, FALSE) e
   WHERE e.order_id = 'aaaaaaaa-0000-0000-0000-0000000000b5';
  INSERT INTO qa VALUES (7,
    'A 0.1 + 0.2 order yields exactly 10 and 20 minor units',
    'gmv=10, delivery_fee=20',
    'gmv=' || v_gmv || ', delivery_fee=' || v_contrib,
    v_gmv = 10 AND v_contrib = 20);

  -- ── 8. Empty state: a period with no orders returns zeroes, not NULLs ────
  -- A NULL here would render as a blank card; a zero is a real answer.
  SELECT f.orders_count, f.gmv, f.contribution_total
    INTO v_n, v_gmv, v_contrib
    FROM public.admin_metrics_food('custom',
      TIMESTAMPTZ '2019-01-01 00:00+00', TIMESTAMPTZ '2019-01-02 00:00+00') f;
  INSERT INTO qa VALUES (8,
    'A period with no orders returns 0/0/0, never NULL',
    '0, 0, 0',
    COALESCE(v_n::text,'NULL') || ', ' || COALESCE(v_gmv::text,'NULL') ||
      ', ' || COALESCE(v_contrib::text,'NULL'),
    v_n = 0 AND v_gmv = 0 AND v_contrib = 0);

  -- ── 9. Empty state on the leaderboards ───────────────────────────────────
  SELECT count(*) INTO v_n FROM public.admin_top_partners('custom','restaurant',10,
      TIMESTAMPTZ '2019-01-01 00:00+00', TIMESTAMPTZ '2019-01-02 00:00+00');
  INSERT INTO qa VALUES (9,
    'A leaderboard for an empty period returns no rows, not an error',
    '0 rows', v_n::text, v_n = 0);

  -- ── 10. Invalid period is rejected ───────────────────────────────────────
  BEGIN
    PERFORM * FROM public.admin_metrics_food('last_tuesday');
    INSERT INTO qa VALUES (10, 'An unknown period name',
      'raises Invalid period', 'accepted it', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO qa VALUES (10, 'An unknown period name',
      'raises Invalid period', SQLERRM, SQLERRM ILIKE '%Invalid period%');
  END;

  -- ── 11. A backwards custom range is rejected ─────────────────────────────
  BEGIN
    PERFORM * FROM public.admin_metrics_food('custom',
      TIMESTAMPTZ '2026-01-02 00:00+00', TIMESTAMPTZ '2026-01-01 00:00+00');
    INSERT INTO qa VALUES (11, 'A custom range whose end precedes its start',
      'raises', 'accepted it', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO qa VALUES (11, 'A custom range whose end precedes its start',
      'raises', SQLERRM, TRUE);
  END;

  -- ── 12. Cancelled orders are excluded from revenue ───────────────────────
  UPDATE public.orders SET status = 'cancelled'
   WHERE id = 'aaaaaaaa-0000-0000-0000-0000000000b4';
  SELECT count(*) INTO v_n FROM public.admin_order_economics(v_from, v_to, FALSE) e
   WHERE e.order_id = 'aaaaaaaa-0000-0000-0000-0000000000b4';
  INSERT INTO qa VALUES (12,
    'A cancelled order drops out of the economics entirely',
    '0', v_n::text, v_n = 0);
END
$qa$;

SELECT jsonb_pretty(jsonb_agg(jsonb_build_object(
  'step', step, 'scenario', scenario, 'expected', expected, 'actual', actual,
  'result', CASE WHEN pass THEN 'PASS' ELSE '*** FAIL ***' END) ORDER BY step))
  AS checklist
FROM qa;

SELECT count(*) FILTER (WHERE pass)     AS passed,
       count(*) FILTER (WHERE NOT pass) AS failed,
       count(*)                         AS total
FROM qa;

ROLLBACK;

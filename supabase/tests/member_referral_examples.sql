-- ============================================================================
-- HotBite Member Referral Rewards — repeatable engine test (BEGIN/ROLLBACK).
-- Run:  supabase db query --linked -f supabase/tests/member_referral_examples.sql
-- Every check RAISEs on failure, so a clean run (final row ok=t) means all pass.
-- Nothing persists (ROLLBACK at the end). This is the durable test artifact for
-- the SQL-based reward engine (repo has no edge-function test harness).
-- ============================================================================
BEGIN;
SELECT set_config('app.ai_exec','0',true);

DO $$
DECLARE
  rid uuid; planid uuid;
  joel uuid; mary uuid; david uuid; buyer uuid;
  oid uuid; res jsonb; i int; v int; v_bal numeric;
  FUTURE timestamptz := now() - interval '400 hours'; -- attribution predates orders

  FUNCTION_mkuser text;
BEGIN
  SELECT id INTO rid FROM restaurants LIMIT 1;
  SELECT id INTO planid FROM membership_plans LIMIT 1;

  -- Make fresh isolated users so counts are deterministic.
  INSERT INTO users(id, email, name, role) VALUES
    (gen_random_uuid(), 't_joel_'||gen_random_uuid()||'@t.co',  'Joel Test',  'customer') RETURNING id INTO joel;
  INSERT INTO users(id, email, name, role) VALUES
    (gen_random_uuid(), 't_mary_'||gen_random_uuid()||'@t.co',  'Mary Test',  'customer') RETURNING id INTO mary;
  INSERT INTO users(id, email, name, role) VALUES
    (gen_random_uuid(), 't_david_'||gen_random_uuid()||'@t.co', 'David Test', 'customer') RETURNING id INTO david;

  -- Chain: mary -> joel (mary referred by joel), david -> mary.
  INSERT INTO referral_attributions(purchaser_id, referrer_id, effective_from) VALUES (mary, joel, FUTURE);
  INSERT INTO referral_attributions(purchaser_id, referrer_id, effective_from) VALUES (david, mary, FUTURE);

  -- All three are active members (so their own orders qualify + they can unlock).
  INSERT INTO customer_memberships(user_id, membership_plan_id, status, start_date, end_date, price_paid)
    SELECT u, planid, 'active', now()-interval '30 days', now()+interval '30 days', 1000
    FROM unnest(ARRAY[joel,mary,david]) u;

  -- ── EXAMPLE 2 core: David (active member) places 1 qualifying order.
  -- Mary (direct) earns 1500 ; Joel (second tier) earns 250 ; nobody at tier 3.
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount,
                     delivery_address, payment_method, status, payment_status, delivered_at, created_at)
    VALUES (david, rid, 2000, 300, 2300, 'a', 'card', 'delivered', 'completed',
            now()-interval '100 hours', now()-interval '101 hours')
    RETURNING id INTO oid;
  res := referral_award_for_order(oid);

  SELECT reward_cents INTO v FROM referral_rewards WHERE source_order_id=oid AND earner_id=mary AND tier=1;
  IF v <> 1500 THEN RAISE EXCEPTION 'FAIL: Mary direct expected 1500 got %', v; END IF;
  SELECT reward_cents INTO v FROM referral_rewards WHERE source_order_id=oid AND earner_id=joel AND tier=2;
  IF v <> 250 THEN RAISE EXCEPTION 'FAIL: Joel second-tier expected 250 got %', v; END IF;
  IF EXISTS (SELECT 1 FROM referral_rewards WHERE source_order_id=oid AND tier > 2) THEN
    RAISE EXCEPTION 'FAIL: tier-3 reward created';
  END IF;

  -- Idempotency: re-award must not add rows.
  PERFORM referral_award_for_order(oid);
  SELECT count(*) INTO v FROM referral_rewards WHERE source_order_id=oid;
  IF v <> 2 THEN RAISE EXCEPTION 'FAIL: idempotency, expected 2 reward rows got %', v; END IF;

  -- ── Redemption unlock: Mary must complete 3 personal qualifying orders.
  -- With < 3, her 1500 stays pending.
  PERFORM referral_unlock_rewards(mary);
  SELECT status INTO FUNCTION_mkuser FROM referral_rewards WHERE source_order_id=oid AND earner_id=mary AND tier=1;
  IF FUNCTION_mkuser <> 'pending' THEN RAISE EXCEPTION 'FAIL: Mary reward should be pending before 3 orders, is %', FUNCTION_mkuser; END IF;

  -- Give Mary 3 personal qualifying orders this month, then unlock.
  FOR i IN 1..3 LOOP
    INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount,
                       delivery_address, payment_method, status, payment_status, delivered_at, created_at)
      VALUES (mary, rid, 1000, 200, 1200, 'a', 'card', 'delivered', 'completed',
              now()-interval '2 days', now()-interval '2 days');
  END LOOP;
  IF referral_personal_qualifying_count(mary, hotbite_month_key(now())) <> 3 THEN
    RAISE EXCEPTION 'FAIL: Mary personal count should be 3';
  END IF;
  PERFORM referral_unlock_rewards(mary);
  SELECT status INTO FUNCTION_mkuser FROM referral_rewards WHERE source_order_id=oid AND earner_id=mary AND tier=1;
  IF FUNCTION_mkuser <> 'credited' THEN RAISE EXCEPTION 'FAIL: Mary reward should be credited, is %', FUNCTION_mkuser; END IF;
  SELECT balance INTO v_bal FROM wallets WHERE user_id=mary;
  IF v_bal < 15 THEN RAISE EXCEPTION 'FAIL: Mary wallet should be >=15, is %', v_bal; END IF;

  -- ── Monthly cap: force Mary near cap, next award is capped.
  UPDATE referral_cap_usage SET earned_cents = 999900  -- $9,999 used of $10,000
    WHERE earner_id = mary AND earning_month = hotbite_month_key(now()-interval '100 hours');
  -- David places another qualifying order → Mary would earn 1500 but only 100 remains.
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount,
                     delivery_address, payment_method, status, payment_status, delivered_at, created_at)
    VALUES (david, rid, 2000, 300, 2300, 'a', 'card', 'delivered', 'completed',
            now()-interval '100 hours', now()-interval '101 hours')
    RETURNING id INTO oid;
  PERFORM referral_award_for_order(oid);
  SELECT reward_cents INTO v FROM referral_rewards WHERE source_order_id=oid AND earner_id=mary AND tier=1;
  IF v <> 100 THEN RAISE EXCEPTION 'FAIL: cap should limit Mary reward to 100, got %', v; END IF;

  -- ── Refund reversal: full refund of David's FIRST order reverses + claws back.
  SELECT id INTO oid FROM orders WHERE user_id=david ORDER BY created_at LIMIT 1;
  INSERT INTO refunds(order_id, user_id, amount, reason, status, processed_at)
    VALUES (oid, david, 2300, 'full', 'processed', now());
  PERFORM referral_reverse_order(oid, 'full_refund');
  IF EXISTS (SELECT 1 FROM referral_rewards WHERE source_order_id=oid AND status <> 'reversed') THEN
    RAISE EXCEPTION 'FAIL: rewards for refunded order should all be reversed';
  END IF;

  -- ── Non-member purchaser earns nobody. buyer(not member) referred by joel.
  INSERT INTO users(id, email, name, role) VALUES
    (gen_random_uuid(), 't_buyer_'||gen_random_uuid()||'@t.co', 'Buyer Test', 'customer') RETURNING id INTO buyer;
  INSERT INTO referral_attributions(purchaser_id, referrer_id, effective_from) VALUES (buyer, joel, FUTURE);
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount,
                     delivery_address, payment_method, status, payment_status, delivered_at, created_at)
    VALUES (buyer, rid, 2000, 300, 2300, 'a', 'card', 'delivered', 'completed',
            now()-interval '100 hours', now()-interval '101 hours')
    RETURNING id INTO oid;
  res := referral_award_for_order(oid);
  IF (res->>'reason') <> 'purchaser_not_member' THEN
    RAISE EXCEPTION 'FAIL: non-member order should not earn, got %', res;
  END IF;

  RAISE NOTICE 'ALL MEMBER-REFERRAL ENGINE CHECKS PASSED';
END $$;

SELECT true AS ok;
ROLLBACK;

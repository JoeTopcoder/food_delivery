-- Restaurant Pickup Coordinator — repeatable engine test (BEGIN/ROLLBACK).
-- Run: supabase db query --linked -f supabase/tests/pickup_coordinator.sql
-- Each check RAISEs on failure; a clean run (final ok=t) means all passed.
BEGIN;
SELECT set_config('app.ai_exec','0',true);
CREATE TEMP TABLE _r(step text, result text) ON COMMIT DROP;
DO $$
DECLARE
  rid uuid; A uuid; B uuid; C uuid; D uuid; E uuid; F uuid; cA uuid; cD uuid; cF uuid; res jsonb; st text;
BEGIN
  SELECT id INTO rid FROM restaurants LIMIT 1;

  -- helper inline: create a confirmed cash order N minutes ago
  -- A: 20 min ago (due), B: 14 min ago (not yet)
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount, delivery_address,
                     payment_method, status, payment_status, confirmed_at, created_at)
    VALUES ((SELECT id FROM users LIMIT 1), rid, 1000,200,1200,'a','cash','confirmed','pending',
            now()-interval '20 min', now()-interval '20 min') RETURNING id INTO A;
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount, delivery_address,
                     payment_method, status, payment_status, confirmed_at, created_at)
    VALUES ((SELECT id FROM users LIMIT 1), rid, 1000,200,1200,'a','cash','confirmed','pending',
            now()-interval '14 min', now()-interval '14 min') RETURNING id INTO B;

  -- 1 & 2: 15-minute boundary
  IF NOT pickup_conditions_met(A) THEN RAISE EXCEPTION 'FAIL: A (20m) should be due'; END IF;
  IF pickup_conditions_met(B) THEN RAISE EXCEPTION 'FAIL: B (14m) should NOT be due'; END IF;

  -- scan enqueues A but not B
  res := pickup_scan_and_enqueue();
  IF NOT EXISTS (SELECT 1 FROM restaurant_pickup_calls WHERE order_id=A AND status='queued') THEN
    RAISE EXCEPTION 'FAIL: A not enqueued'; END IF;
  IF EXISTS (SELECT 1 FROM restaurant_pickup_calls WHERE order_id=B) THEN
    RAISE EXCEPTION 'FAIL: B should not be enqueued'; END IF;

  -- idempotent scan: still one call for A
  PERFORM pickup_scan_and_enqueue();
  IF (SELECT count(*) FROM restaurant_pickup_calls WHERE order_id=A) <> 1 THEN
    RAISE EXCEPTION 'FAIL: duplicate call enqueued for A'; END IF;

  -- 3: status update while queued/dialing → begin_dial cancels
  UPDATE orders SET status='preparing' WHERE id=A;  -- restaurant acted first
  SELECT id INTO cA FROM restaurant_pickup_calls WHERE order_id=A;
  res := pickup_begin_dial(cA);
  IF (res->>'ok')::boolean THEN RAISE EXCEPTION 'FAIL: begin_dial should refuse after status change'; END IF;
  IF (SELECT status FROM restaurant_pickup_calls WHERE id=cA) <> 'cancelled' THEN
    RAISE EXCEPTION 'FAIL: call for A should be cancelled'; END IF;

  -- Ready-now confirmation on a fresh due order C
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount, delivery_address,
                     payment_method, status, payment_status, confirmed_at, created_at)
    VALUES ((SELECT id FROM users LIMIT 1), rid, 1000,200,1200,'a','cash','confirmed','pending',
            now()-interval '20 min', now()-interval '20 min') RETURNING id INTO C;
  INSERT INTO restaurant_pickup_calls(order_id, restaurant_id, status) VALUES (C, rid, 'dialing') RETURNING id INTO cD;
  res := pickup_record_call_outcome(cD, p_ready_now := true);
  IF (SELECT status FROM orders WHERE id=C) <> 'ready' THEN RAISE EXCEPTION 'FAIL: C should be ready now'; END IF;

  -- idempotency: recording outcome again is a no-op
  res := pickup_record_call_outcome(cD, p_ready_now := true);
  IF NOT (res->>'idempotent')::boolean THEN RAISE EXCEPTION 'FAIL: outcome not idempotent'; END IF;

  -- Future time WITH authorization → schedule + auto-run marks Ready
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount, delivery_address,
                     payment_method, status, payment_status, confirmed_at, created_at)
    VALUES ((SELECT id FROM users LIMIT 1), rid, 1000,200,1200,'a','cash','confirmed','pending',
            now()-interval '20 min', now()-interval '20 min') RETURNING id INTO D;
  INSERT INTO restaurant_pickup_calls(order_id, restaurant_id, status) VALUES (D, rid, 'dialing') RETURNING id INTO cF;
  res := pickup_record_call_outcome(cF, p_prep_underway := true,
           p_confirmed_ready_at := now()+interval '5 min', p_auto_authorized := true);
  IF (SELECT status FROM orders WHERE id=D) <> 'preparing' THEN RAISE EXCEPTION 'FAIL: D should be preparing'; END IF;
  IF NOT EXISTS (SELECT 1 FROM restaurant_ready_jobs WHERE order_id=D AND status='scheduled') THEN
    RAISE EXCEPTION 'FAIL: D auto-ready job not scheduled'; END IF;
  -- fast-forward the job and run it
  UPDATE restaurant_ready_jobs SET run_at = now()-interval '1 min' WHERE order_id=D AND status='scheduled';
  res := pickup_run_ready_jobs();
  IF (SELECT status FROM orders WHERE id=D) <> 'ready' THEN RAISE EXCEPTION 'FAIL: D should be auto-marked ready'; END IF;
  IF (SELECT status FROM restaurant_ready_jobs WHERE order_id=D) <> 'done' THEN
    RAISE EXCEPTION 'FAIL: D job should be done'; END IF;

  -- Future time WITHOUT authorization → expected only, no job, no auto-ready
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount, delivery_address,
                     payment_method, status, payment_status, confirmed_at, created_at)
    VALUES ((SELECT id FROM users LIMIT 1), rid, 1000,200,1200,'a','cash','confirmed','pending',
            now()-interval '20 min', now()-interval '20 min') RETURNING id INTO E;
  INSERT INTO restaurant_pickup_calls(order_id, restaurant_id, status) VALUES (E, rid, 'dialing') RETURNING id INTO cA;
  res := pickup_record_call_outcome(cA, p_prep_underway := true,
           p_confirmed_ready_at := now()+interval '5 min', p_auto_authorized := false);
  IF (SELECT expected_ready_at FROM orders WHERE id=E) IS NULL THEN RAISE EXCEPTION 'FAIL: E expected_ready_at not stored'; END IF;
  IF EXISTS (SELECT 1 FROM restaurant_ready_jobs WHERE order_id=E) THEN RAISE EXCEPTION 'FAIL: E must NOT have an auto-ready job'; END IF;

  -- Later delay cancels a scheduled job (order F)
  INSERT INTO orders(user_id, restaurant_id, subtotal, delivery_fee, total_amount, delivery_address,
                     payment_method, status, payment_status, confirmed_at, created_at)
    VALUES ((SELECT id FROM users LIMIT 1), rid, 1000,200,1200,'a','cash','confirmed','pending',
            now()-interval '20 min', now()-interval '20 min') RETURNING id INTO F;
  INSERT INTO restaurant_pickup_calls(order_id, restaurant_id, status) VALUES (F, rid, 'dialing') RETURNING id INTO cF;
  PERFORM pickup_record_call_outcome(cF, p_prep_underway := true,
           p_confirmed_ready_at := now()+interval '5 min', p_auto_authorized := true);
  -- simulate a later delay report on the same order
  PERFORM _pickup_cancel_jobs(F, 'later_delay');
  IF EXISTS (SELECT 1 FROM restaurant_ready_jobs WHERE order_id=F AND status='scheduled') THEN
    RAISE EXCEPTION 'FAIL: F job should be cancelled after delay'; END IF;

  RAISE NOTICE 'ALL PICKUP COORDINATOR CHECKS PASSED';
END $$;
SELECT true AS ok;
ROLLBACK;

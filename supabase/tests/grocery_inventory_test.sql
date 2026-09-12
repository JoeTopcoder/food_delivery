-- Tests for the grocery inventory system. Transactional; rolls back.
-- Run: supabase db query --linked -f supabase/tests/grocery_inventory_test.sql
BEGIN;
SET LOCAL session_replication_role = replica;  -- orders triggers make HTTP calls

CREATE TEMP TABLE t(step INT, scenario TEXT, expected TEXT, actual TEXT, pass BOOLEAN)
  ON COMMIT DROP;

DO $t$
DECLARE
  v_admin  UUID;
  v_owner  UUID;
  v_store  UUID;
  v_pid    UUID;
  v_order  UUID := 'aaaaaaaa-0000-0000-0000-00000000e001';
  v_cust   UUID;
  n        INTEGER;
  v_moves  INTEGER;
BEGIN
  SELECT id INTO v_admin FROM public.users WHERE role='admin' LIMIT 1;
  -- pick a real grocery product and derive its store + owner, so all exist
  SELECT id, restaurant_id INTO v_pid, v_store FROM public.menus
   WHERE product_type='grocery' LIMIT 1;
  SELECT owner_id INTO v_owner FROM public.restaurants WHERE id=v_store;
  -- a customer who does NOT own this store (the store owner may also be a
  -- 'customer' role, which would wrongly pass the ownership check).
  SELECT id INTO v_cust FROM public.users
   WHERE role='customer' AND id IS DISTINCT FROM v_owner LIMIT 1;

  -- seed a real order row so order_id FK is satisfiable
  INSERT INTO public.orders (id, user_id, restaurant_id, delivery_address,
                             subtotal, delivery_fee, total_amount, payment_method,
                             status, ordered_at)
  VALUES (v_order, v_cust, v_store, 'QA', 100,0,100,'cash','pending', now());

  -- act as admin for the owner/admin RPCs
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role','authenticated')::text, true);

  -- 1. restock sets quantity + flips in_stock + writes a movement
  n := public.adjust_inventory(v_pid, 50, 'restock', 'initial');
  INSERT INTO t VALUES (1,'Restock +50 sets qty=50, in_stock=true','50 / true',
    n||' / '||(SELECT in_stock FROM public.menus WHERE id=v_pid),
    n=50 AND (SELECT in_stock FROM public.menus WHERE id=v_pid));

  -- 2. a sale consumes stock
  PERFORM public.consume_inventory_for_order(
    jsonb_build_array(jsonb_build_object('product_id',v_pid,'quantity',20)), v_order);
  INSERT INTO t VALUES (2,'Sale of 20 -> qty 30','30',
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)::text,
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)=30);

  -- 3. overselling is rejected (atomic) — try to sell 100 of 30
  BEGIN
    PERFORM public.consume_inventory_for_order(
      jsonb_build_array(jsonb_build_object('product_id',v_pid,'quantity',100)),
      v_order);
    INSERT INTO t VALUES (3,'Oversell 100 of 30 -> rejected','raises','it succeeded',FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (3,'Oversell 100 of 30 -> rejected','raises',SQLERRM,
      SQLERRM ILIKE '%Insufficient stock%');
  END;
  -- and quantity is unchanged after the rejected oversell
  INSERT INTO t VALUES (4,'Stock unchanged after rejected oversell','30',
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)::text,
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)=30);

  -- 5. restore on cancel puts the 20 back, once
  PERFORM public.restore_inventory_for_order(v_order);
  INSERT INTO t VALUES (5,'Restore cancelled order -> qty back to 50','50',
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)::text,
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)=50);
  -- 6. restore is idempotent (second call is a no-op)
  PERFORM public.restore_inventory_for_order(v_order);
  INSERT INTO t VALUES (6,'Restore again is idempotent (still 50)','50',
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)::text,
    (SELECT stock_quantity FROM public.menus WHERE id=v_pid)=50);

  -- 7. stocktake sets an absolute count and records the delta
  n := public.set_inventory(v_pid, 12, 'monthly count');
  INSERT INTO t VALUES (7,'Stocktake to 12','12',n::text,n=12);

  -- 8. a customer (non-owner, non-admin) cannot adjust
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_cust, 'role','authenticated')::text, true);
  BEGIN
    PERFORM public.adjust_inventory(v_pid, 5, 'restock', 'hack');
    INSERT INTO t VALUES (8,'Customer adjusting stock','forbidden','it worked',FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (8,'Customer adjusting stock','forbidden',SQLERRM,
      SQLERRM ILIKE '%Forbidden%');
  END;

  -- 9. a customer cannot consume stock directly (grief protection)
  BEGIN
    PERFORM public.consume_inventory_for_order(
      jsonb_build_array(jsonb_build_object('product_id',v_pid,'quantity',1)), v_order);
    INSERT INTO t VALUES (9,'Customer consuming stock directly','forbidden','it worked',FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (9,'Customer consuming stock directly','forbidden',SQLERRM,
      SQLERRM ILIKE '%Forbidden%');
  END;

  -- 10. movement ledger recorded each real change (restock, sale, restore, stocktake = 4)
  SELECT count(*) INTO v_moves FROM public.inventory_movements WHERE product_id=v_pid;
  INSERT INTO t VALUES (10,'Ledger has a row per change (>=4)','>=4',v_moves::text,v_moves>=4);

  -- 11. untracked product is ignored by a sale (no error, no change)
  DECLARE v_untracked UUID;
  BEGIN
    SELECT id INTO v_untracked FROM public.menus
     WHERE restaurant_id=v_store AND product_type='grocery' AND id<>v_pid
       AND track_inventory=false LIMIT 1;
    IF v_untracked IS NOT NULL THEN
      PERFORM set_config('request.jwt.claims',
        json_build_object('sub', v_admin, 'role','authenticated')::text, true);
      PERFORM public.consume_inventory_for_order(
        jsonb_build_array(jsonb_build_object('product_id',v_untracked,'quantity',5)), v_order);
      INSERT INTO t VALUES (11,'Sale of an untracked product is a no-op','no movement',
        (SELECT count(*)::text FROM public.inventory_movements WHERE product_id=v_untracked),
        (SELECT count(*) FROM public.inventory_movements WHERE product_id=v_untracked)=0);
    END IF;
  END;
END
$t$;

SELECT jsonb_pretty(jsonb_agg(jsonb_build_object('step',step,'scenario',scenario,
  'expected',expected,'actual',actual,
  'result',CASE WHEN pass THEN 'PASS' ELSE '*** FAIL ***' END) ORDER BY step)) AS results
FROM t;
SELECT count(*) FILTER (WHERE pass) AS passed,
       count(*) FILTER (WHERE NOT pass) AS failed, count(*) AS total FROM t;
ROLLBACK;

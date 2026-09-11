BEGIN;
SET LOCAL session_replication_role = replica;  -- orders triggers make HTTP calls
CREATE TEMP TABLE t(step INT, scenario TEXT, expected TEXT, actual TEXT, pass BOOLEAN) ON COMMIT DROP;

DO $t$
DECLARE
  v_admin UUID; v_store UUID; v_owner UUID; v_cust UUID;
  v_p1 UUID; v_p2 UUID; v_p3 UUID;
  v_order UUID := 'aaaaaaaa-0000-0000-0000-0000000f1234';
  v_oi1 UUID; v_oi3 UUID;
  r JSONB;
BEGIN
  SELECT id INTO v_admin FROM public.users WHERE role='admin' LIMIT 1;
  -- a store with >= 3 grocery products
  SELECT restaurant_id INTO v_store FROM public.menus WHERE product_type='grocery'
   GROUP BY restaurant_id HAVING count(*) >= 3 LIMIT 1;
  SELECT owner_id INTO v_owner FROM public.restaurants WHERE id=v_store;
  SELECT id INTO v_cust FROM public.users WHERE role='customer' AND id IS DISTINCT FROM v_owner LIMIT 1;
  SELECT id INTO v_p1 FROM public.menus WHERE restaurant_id=v_store AND product_type='grocery' ORDER BY id LIMIT 1;
  SELECT id INTO v_p2 FROM public.menus WHERE restaurant_id=v_store AND product_type='grocery' AND id<>v_p1 ORDER BY id LIMIT 1;
  SELECT id INTO v_p3 FROM public.menus WHERE restaurant_id=v_store AND product_type='grocery' AND id NOT IN (v_p1,v_p2) ORDER BY id LIMIT 1;

  -- give p1 a known barcode; p2 a barcode but keep it OFF the order; p3 no barcode
  UPDATE public.menus SET barcode='BC-AAA' WHERE id=v_p1;
  UPDATE public.menus SET barcode='BC-BBB' WHERE id=v_p2;
  UPDATE public.menus SET barcode=NULL     WHERE id=v_p3;

  INSERT INTO public.orders (id,user_id,restaurant_id,delivery_address,subtotal,delivery_fee,total_amount,payment_method,status,ordered_at)
  VALUES (v_order,v_cust,v_store,'QA',100,0,100,'cash','preparing',now());
  INSERT INTO public.order_items (id,order_id,menu_item_id,item_name,quantity,price,subtotal)
  VALUES (gen_random_uuid(),v_order,v_p1,'P1',3,10,30) RETURNING id INTO v_oi1;
  INSERT INTO public.order_items (id,order_id,menu_item_id,item_name,quantity,price,subtotal)
  VALUES (gen_random_uuid(),v_order,v_p3,'P3',1,5,5) RETURNING id INTO v_oi3;

  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_admin,'role','authenticated')::text, true);

  -- 1. first scan of BC-AAA -> picked 1/3, not done, not all
  r := public.pick_scan(v_order,'BC-AAA');
  INSERT INTO t VALUES (1,'Scan BC-AAA #1 -> picked 1/3','picked/1/false/false',
    (r->>'status')||'/'||(r->>'picked_quantity')||'/'||(r->>'line_done')||'/'||(r->>'all_picked'),
    r->>'status'='picked' AND r->>'picked_quantity'='1' AND r->>'line_done'='false' AND r->>'all_picked'='false');

  -- 2. scan twice more -> 3/3 line done, but p3 still unpicked so all=false
  PERFORM public.pick_scan(v_order,'BC-AAA');
  r := public.pick_scan(v_order,'BC-AAA');
  INSERT INTO t VALUES (2,'Scan BC-AAA to 3/3 -> line done, all=false','picked/3/true/false',
    (r->>'status')||'/'||(r->>'picked_quantity')||'/'||(r->>'line_done')||'/'||(r->>'all_picked'),
    r->>'status'='picked' AND r->>'picked_quantity'='3' AND r->>'line_done'='true' AND r->>'all_picked'='false');

  -- 3. one more scan of a completed line -> already_complete
  r := public.pick_scan(v_order,'BC-AAA');
  INSERT INTO t VALUES (3,'Scan completed line -> already_complete','already_complete',
    r->>'status', r->>'status'='already_complete');

  -- 4. unknown code
  r := public.pick_scan(v_order,'BC-NOPE');
  INSERT INTO t VALUES (4,'Unknown code -> unknown_code','unknown_code',
    r->>'status', r->>'status'='unknown_code');

  -- 5. code for a store product not on the order -> not_in_order
  r := public.pick_scan(v_order,'BC-BBB');
  INSERT INTO t VALUES (5,'Store product not on order -> not_in_order','not_in_order',
    r->>'status', r->>'status'='not_in_order');

  -- 6. scan-to-assign: p3 has no barcode; assign BC-NEW then scan it
  PERFORM public.assign_barcode(v_p3,'BC-NEW');
  r := public.pick_scan(v_order,'BC-NEW');
  INSERT INTO t VALUES (6,'Assign BC-NEW to p3 then scan -> picked 1/1 done','picked/1/true',
    (r->>'status')||'/'||(r->>'picked_quantity')||'/'||(r->>'line_done'),
    r->>'status'='picked' AND r->>'picked_quantity'='1' AND r->>'line_done'='true');

  -- 7. now everything is picked
  INSERT INTO t VALUES (7,'After p3 picked -> all_picked true','true',
    r->>'all_picked', r->>'all_picked'='true');

  -- 8. manual reset of line1 to 0 -> all_picked false
  r := public.pick_set_item(v_oi1, 0);
  INSERT INTO t VALUES (8,'pick_set_item(line1,0) -> 0/3, all=false','0/false',
    (r->>'picked_quantity')||'/'||(r->>'all_picked'),
    r->>'picked_quantity'='0' AND r->>'all_picked'='false');

  -- 9. manual over-set is clamped to quantity
  r := public.pick_set_item(v_oi1, 99);
  INSERT INTO t VALUES (9,'pick_set_item(line1,99) clamps to 3','3/true',
    (r->>'picked_quantity')||'/'||(r->>'line_done'),
    r->>'picked_quantity'='3' AND r->>'line_done'='true');

  -- 10. assign duplicate barcode within store is rejected
  BEGIN
    PERFORM public.assign_barcode(v_p2,'BC-AAA');  -- BC-AAA already on p1
    INSERT INTO t VALUES (10,'Duplicate barcode rejected','raises','it worked',FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (10,'Duplicate barcode rejected','raises',SQLERRM,
      SQLERRM ILIKE '%already linked%');
  END;

  -- 11. a non-owner customer cannot scan-pick
  PERFORM set_config('request.jwt.claims', json_build_object('sub',v_cust,'role','authenticated')::text, true);
  BEGIN
    PERFORM public.pick_scan(v_order,'BC-AAA');
    INSERT INTO t VALUES (11,'Customer scanning -> forbidden','forbidden','it worked',FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (11,'Customer scanning -> forbidden','forbidden',SQLERRM,
      SQLERRM ILIKE '%Forbidden%');
  END;
END $t$;

SELECT jsonb_pretty(jsonb_agg(jsonb_build_object('step',step,'scenario',scenario,
  'expected',expected,'actual',actual,
  'result',CASE WHEN pass THEN 'PASS' ELSE '*** FAIL ***' END) ORDER BY step)) AS results FROM t;
SELECT count(*) FILTER (WHERE pass) AS passed, count(*) FILTER (WHERE NOT pass) AS failed, count(*) AS total FROM t;
ROLLBACK;

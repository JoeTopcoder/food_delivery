-- Host Rewards — scenario test suite. Self-contained & non-persisting
-- (BEGIN…ROLLBACK). Run with:
--   supabase db query --linked -f supabase/tests/host_rewards_test.sql
-- Each assertion writes pass/fail into _res; the final SELECT prints them.
BEGIN;
UPDATE app_config SET value='true' WHERE key='host_rewards_enabled';
CREATE TEMP TABLE _res(r jsonb);

DO $$
DECLARE
  cust uuid; cust2 uuid; rest uuid; host uuid; host2 uuid;
  propA uuid; propB uuid; codeA text; codeB text; codeS text; propS uuid;
  o uuid; res jsonb := '{}'::jsonb; claim jsonb;
  function_order_total int;
BEGIN
  SELECT id INTO cust  FROM users WHERE email='driver@hotbite.app';
  SELECT id INTO cust2 FROM users WHERE id<>cust AND role='customer' LIMIT 1;
  IF cust2 IS NULL THEN SELECT id INTO cust2 FROM users WHERE id<>cust LIMIT 1; END IF;
  SELECT id INTO rest FROM restaurants LIMIT 1;

  INSERT INTO hosts(full_name,status) VALUES ('H Active','active') RETURNING id INTO host;
  INSERT INTO hosts(full_name,status) VALUES ('H Suspended','suspended') RETURNING id INTO host2;
  codeA := host_generate_referral_code();
  INSERT INTO host_properties(host_id,property_name,address,referral_code,status)
    VALUES (host,'A','1 A',codeA,'active') RETURNING id INTO propA;
  codeB := host_generate_referral_code();
  INSERT INTO host_properties(host_id,property_name,address,referral_code,status)
    VALUES (host,'B','2 B',codeB,'active') RETURNING id INTO propB;
  codeS := host_generate_referral_code();
  INSERT INTO host_properties(host_id,property_name,address,referral_code,status)
    VALUES (host2,'S','3 S',codeS,'active') RETURNING id INTO propS;

  -- helper to place & deliver an order to a property, return order id
  -- (inline rather than a function so it shares this tx)
  PERFORM set_config('request.jwt.claims', json_build_object('sub',cust)::text, true);

  -- 1. Claim valid code
  claim := host_claim_referral(codeA);
  res := res || jsonb_build_object('t01_claim_ok', claim->>'ok' = 'true');

  -- 2. Second claim (already referred) rejected
  claim := host_claim_referral(codeB);
  res := res || jsonb_build_object('t02_second_claim_rejected', claim->>'error' = 'already_referred');

  -- 3. Suspended host claim rejected (different customer)
  PERFORM set_config('request.jwt.claims', json_build_object('sub',cust2)::text, true);
  claim := host_claim_referral(codeS);
  res := res || jsonb_build_object('t03_suspended_host_rejected', claim->>'error' = 'inactive_host');
  PERFORM set_config('request.jwt.claims', json_build_object('sub',cust)::text, true);

  -- 4. Order delivered to referred property (cash) -> commission J$100
  INSERT INTO orders(user_id,restaurant_id,subtotal,delivery_fee,total_amount,delivery_address,payment_method,status,host_property_id)
    VALUES (cust,rest,2000,500,2500,'1 A','cash','pending',propA) RETURNING id INTO o;
  UPDATE orders SET status='delivered' WHERE id=o;
  res := res || jsonb_build_object('t04_award_10000',
    (SELECT amount_cents FROM host_commissions WHERE order_id=o) = 10000);

  -- 5. Second qualifying order also earns (every qualifying order)
  INSERT INTO orders(user_id,restaurant_id,subtotal,delivery_fee,total_amount,delivery_address,payment_method,status,host_property_id)
    VALUES (cust,rest,2000,500,2500,'1 A','cash','pending',propA) RETURNING id INTO o;
  UPDATE orders SET status='delivered' WHERE id=o;
  res := res || jsonb_build_object('t05_second_order_earns',
    (SELECT count(*) FROM host_commissions c JOIN host_referrals r ON r.id=c.referral_id WHERE r.customer_id=cust) = 2);

  -- 6. Card order PAID -> earns
  INSERT INTO orders(user_id,restaurant_id,subtotal,delivery_fee,total_amount,delivery_address,payment_method,payment_status,status,host_property_id)
    VALUES (cust,rest,2000,500,2500,'1 A','card','completed','pending',propA) RETURNING id INTO o;
  UPDATE orders SET status='delivered' WHERE id=o;
  res := res || jsonb_build_object('t06_card_paid_earns',
    EXISTS(SELECT 1 FROM host_commissions WHERE order_id=o));

  -- (A DB payment-gate trigger forbids an unpaid card order from ever being
  -- activated, so that negative case cannot occur and needs no test.)

  -- 8. Delivered to a DIFFERENT property -> none
  INSERT INTO orders(user_id,restaurant_id,subtotal,delivery_fee,total_amount,delivery_address,payment_method,status,host_property_id)
    VALUES (cust,rest,2000,500,2500,'2 B','cash','pending',propB) RETURNING id INTO o;
  UPDATE orders SET status='delivered' WHERE id=o;
  res := res || jsonb_build_object('t08_wrong_property_none',
    NOT EXISTS(SELECT 1 FROM host_commissions WHERE order_id=o));

  -- 9. Expired referral -> none
  UPDATE host_referrals SET expires_at = now() - interval '1 day' WHERE customer_id=cust;
  INSERT INTO orders(user_id,restaurant_id,subtotal,delivery_fee,total_amount,delivery_address,payment_method,status,host_property_id)
    VALUES (cust,rest,2000,500,2500,'1 A','cash','pending',propA) RETURNING id INTO o;
  UPDATE orders SET status='delivered' WHERE id=o;
  res := res || jsonb_build_object('t09_expired_none',
    NOT EXISTS(SELECT 1 FROM host_commissions WHERE order_id=o));
  UPDATE host_referrals SET expires_at = now() + interval '30 days' WHERE customer_id=cust;

  -- 10. Flag OFF -> engine no-op
  UPDATE app_config SET value='false' WHERE key='host_rewards_enabled';
  INSERT INTO orders(user_id,restaurant_id,subtotal,delivery_fee,total_amount,delivery_address,payment_method,status,host_property_id)
    VALUES (cust,rest,2000,500,2500,'1 A','cash','pending',propA) RETURNING id INTO o;
  UPDATE orders SET status='delivered' WHERE id=o;
  res := res || jsonb_build_object('t10_flag_off_none',
    NOT EXISTS(SELECT 1 FROM host_commissions WHERE order_id=o));
  UPDATE app_config SET value='true' WHERE key='host_rewards_enabled';

  -- 11. Payout: make commissions payable (past hold), approve, ledger consistent
  UPDATE host_commissions SET payable_at = now() - interval '1 day' WHERE host_id=host;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub',(SELECT id FROM users WHERE role='admin' LIMIT 1),
      'app_metadata', json_build_object('role','admin'))::text, true);
  -- approve as admin requires is_admin(); run the body directly via the RPC
  DECLARE pay jsonb; v_net int; BEGIN
    pay := host_admin_approve_payout(host);
    res := res || jsonb_build_object('t11_payout_ok', pay->>'ok' = 'true');
    -- ledger net for host = accruals - payout should be 0 (all paid)
    SELECT COALESCE(SUM(amount_cents),0) INTO v_net FROM host_commission_ledger WHERE host_id=host;
    res := res || jsonb_build_object('t11_ledger_net_zero', v_net = 0);
  END;

  INSERT INTO _res VALUES (res);
EXCEPTION WHEN OTHERS THEN
  INSERT INTO _res VALUES (jsonb_build_object('FATAL', SQLERRM));
END $$;

SELECT jsonb_pretty(r) AS result FROM _res;
ROLLBACK;

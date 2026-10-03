-- HotBite Member Referral Rewards — 8 : fix referral_unlock_rewards.
-- The original used a TEMP TABLE (ON COMMIT DROP) for unlock months, which
-- errored ("relation already exists") when the function ran twice in one
-- transaction. Replaced with an inline CTE — no temp table, fully re-entrant.
CREATE OR REPLACE FUNCTION public.referral_unlock_rewards(p_earner uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  pol referral_reward_policies%ROWTYPE;
  v_required int; r record; v_credited int := 0; v_count int := 0; v_txn uuid;
BEGIN
  pol := public.referral_policy_current();
  v_required := COALESCE(pol.personal_orders_required, 3);

  IF NOT public.is_hotbite_plus_member(p_earner) THEN
    RETURN jsonb_build_object('ok',false,'reason','earner_not_member');
  END IF;

  FOR r IN
    WITH unlock_months AS (
      SELECT public.hotbite_month_key(COALESCE(o.delivered_at,o.created_at)) AS m
      FROM orders o
      WHERE o.user_id = p_earner AND o.status='delivered'
      GROUP BY 1
      HAVING count(*) FILTER (WHERE public.referral_order_qualifies(o.id)) >= v_required
    )
    SELECT rr.* FROM referral_rewards rr
    WHERE rr.earner_id = p_earner
      AND rr.status = 'pending'
      AND rr.settle_at <= now()
      AND rr.expires_at > now()
      AND rr.reward_cents > 0
      AND EXISTS (SELECT 1 FROM unlock_months um WHERE um.m >= rr.earning_month)
    ORDER BY rr.created_at
    FOR UPDATE
  LOOP
    INSERT INTO wallets(user_id, balance, cashback_balance)
      VALUES (p_earner, 0, 0) ON CONFLICT (user_id) DO NOTHING;
    UPDATE wallets SET balance = COALESCE(balance,0) + (r.reward_cents/100.0), updated_at = now()
      WHERE user_id = p_earner;
    INSERT INTO wallet_transactions(user_id, amount, type, payment_method, status, order_id, description)
      VALUES (p_earner, (r.reward_cents/100.0), 'cashback', 'wallet', 'completed', r.source_order_id,
              'Referral reward (tier '||r.tier||')')
      RETURNING id INTO v_txn;
    UPDATE referral_rewards
       SET status='credited', credited_at=now(), wallet_txn_id=v_txn
     WHERE id = r.id;
    v_credited := v_credited + r.reward_cents;
    v_count := v_count + 1;
  END LOOP;

  RETURN jsonb_build_object('ok',true,'credited_count',v_count,'credited_cents',v_credited);
END;
$$;

GRANT EXECUTE ON FUNCTION public.referral_unlock_rewards(uuid) TO service_role, authenticated;
NOTIFY pgrst, 'reload schema';

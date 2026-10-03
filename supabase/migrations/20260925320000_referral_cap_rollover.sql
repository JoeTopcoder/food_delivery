-- Cap rollover: if a member doesn't use their whole monthly referral cap, 50%
-- of the UNUSED base allowance rolls into next month's cap. Non-compounding and
-- bounded: rollover is measured against the BASE cap only, so the effective cap
-- can reach at most base + 50%*base (e.g. $22,000 → up to $33,000), never runs away.

INSERT INTO app_config(key, value)
SELECT 'referral_cap_rollover_pct', '50'
WHERE NOT EXISTS (SELECT 1 FROM app_config WHERE key='referral_cap_rollover_pct');

-- Effective cap for an earner in a given Jamaica month = base monthly cap +
-- rollover% of the unused base allowance from the previous month.
CREATE OR REPLACE FUNCTION public.referral_effective_cap(p_earner uuid, p_month date)
RETURNS integer
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE v_base int; v_pct numeric; v_prev_earned int; v_unused int;
BEGIN
  v_base := (public.referral_policy_current()).monthly_cap_cents;
  SELECT COALESCE(NULLIF(value,'')::numeric,50) INTO v_pct FROM app_config WHERE key='referral_cap_rollover_pct';
  SELECT COALESCE(earned_cents,0) INTO v_prev_earned FROM referral_cap_usage
   WHERE earner_id = p_earner AND earning_month = (p_month - interval '1 month')::date;
  v_prev_earned := COALESCE(v_prev_earned, 0);
  v_unused := GREATEST(0, v_base - v_prev_earned);
  RETURN v_base + floor(v_unused * v_pct/100.0)::int;
END;
$$;
GRANT EXECUTE ON FUNCTION public.referral_effective_cap(uuid,date) TO authenticated, service_role;

-- Re-grant with the effective (rollover-aware) cap.
CREATE OR REPLACE FUNCTION public._referral_grant(
  p_earner uuid, p_purchaser uuid, p_order uuid, p_tier smallint,
  p_amount int, p_month date, p_settle timestamptz, p_expires timestamptz,
  p_policy uuid, p_order_value int)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_used int; v_cap int; v_remaining int; v_grant int; v_reason text;
BEGIN
  IF p_earner IS NULL OR p_earner = p_purchaser THEN RETURN 0; END IF;
  IF EXISTS (SELECT 1 FROM referral_rewards
             WHERE source_order_id = p_order AND earner_id = p_earner AND tier = p_tier) THEN
    RETURN 0;
  END IF;

  -- Effective cap includes 50% of last month's unused allowance (rollover).
  v_cap := public.referral_effective_cap(p_earner, p_month);

  INSERT INTO referral_cap_usage(earner_id, earning_month, earned_cents)
  VALUES (p_earner, p_month, 0)
  ON CONFLICT (earner_id, earning_month) DO NOTHING;

  SELECT earned_cents INTO v_used FROM referral_cap_usage
  WHERE earner_id = p_earner AND earning_month = p_month FOR UPDATE;

  v_remaining := GREATEST(0, v_cap - COALESCE(v_used,0));
  v_grant := LEAST(p_amount, v_remaining);
  v_reason := CASE WHEN v_grant < p_amount THEN 'tier'||p_tier||'_capped' ELSE 'tier'||p_tier END;

  INSERT INTO referral_rewards(
    earner_id, purchaser_id, source_order_id, tier, reward_cents, status,
    earning_month, policy_id, order_value_cents, settle_at, expires_at, reason)
  VALUES (p_earner, p_purchaser, p_order, p_tier, v_grant, 'pending',
          p_month, p_policy, p_order_value, p_settle, p_expires, v_reason)
  ON CONFLICT (source_order_id, earner_id, tier) DO NOTHING;

  IF v_grant > 0 THEN
    UPDATE referral_cap_usage SET earned_cents = earned_cents + v_grant, updated_at = now()
    WHERE earner_id = p_earner AND earning_month = p_month;
  END IF;
  RETURN v_grant;
END;
$$;
REVOKE ALL ON FUNCTION public._referral_grant(uuid,uuid,uuid,smallint,int,date,timestamptz,timestamptz,uuid,int) FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

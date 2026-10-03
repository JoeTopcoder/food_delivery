-- HotBite Member Referral Rewards — 7 : admin policy control (prospective).
-- Inserts a NEW policy version effective now; historical rewards keep their
-- pinned policy_id, so changes never rewrite past earnings.
CREATE OR REPLACE FUNCTION public.admin_referral_set_policy(
  p_enabled boolean,
  p_direct_cents int,
  p_second_cents int,
  p_min_order_cents int,
  p_settlement_hours int,
  p_carry_days int,
  p_cap_cents int,
  p_personal_required int,
  p_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_admin uuid; v_id uuid;
BEGIN
  v_admin := public.require_admin();
  IF p_direct_cents < 0 OR p_second_cents < 0 OR p_cap_cents <= 0 OR p_personal_required < 1 THEN
    RAISE EXCEPTION 'invalid policy values';
  END IF;
  INSERT INTO referral_reward_policies(
    effective_from, enabled, direct_reward_cents, second_tier_reward_cents,
    min_order_value_cents, settlement_delay_hours, carry_forward_days,
    monthly_cap_cents, personal_orders_required, notes, created_by)
  VALUES (now(), p_enabled, p_direct_cents, p_second_cents, p_min_order_cents,
          p_settlement_hours, p_carry_days, p_cap_cents, p_personal_required,
          COALESCE(p_notes,'admin update'), v_admin)
  RETURNING id INTO v_id;
  RETURN jsonb_build_object('ok', true, 'policy_id', v_id);
END;
$$;

-- Convenience read of the current policy as jsonb (authenticated).
CREATE OR REPLACE FUNCTION public.referral_policy_current_json()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT to_jsonb(p) FROM public.referral_policy_current() p;
$$;

GRANT EXECUTE ON FUNCTION public.admin_referral_set_policy(boolean,int,int,int,int,int,int,int,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.referral_policy_current_json() TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

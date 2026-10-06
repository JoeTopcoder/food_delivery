-- ============================================================================
-- CASHIER SHIFT RPCs (Phase 3b) — open/record/submit/approve/adjust + counts.
-- Advisory reconciliation only; moves no money.
-- ============================================================================

-- Open a shift. One unresolved shift per cashier per restaurant (unique index).
CREATE OR REPLACE FUNCTION public.shift_open(p_restaurant uuid, p_opening_float_cents bigint)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid; v_tz text;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;
  IF NOT public.is_restaurant_staff(p_restaurant, v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_a_member'); END IF;
  IF coalesce(p_opening_float_cents,0) < 0 THEN RETURN jsonb_build_object('ok',false,'reason','bad_float'); END IF;
  v_tz := coalesce((SELECT timezone FROM public.restaurants WHERE id=p_restaurant),'America/Jamaica');
  BEGIN
    INSERT INTO public.cashier_shifts(restaurant_id,cashier_user_id,status,business_date,timezone,opening_float_cents)
      VALUES (p_restaurant, v_uid, 'open', public.restaurant_business_date(p_restaurant), v_tz, coalesce(p_opening_float_cents,0))
      RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok',false,'reason','already_has_open_shift');
  END;
  PERFORM public._rstaff_audit(p_restaurant, v_uid, 'shift_open', v_uid, NULL, NULL,
    jsonb_build_object('shift_id',v_id,'opening_float_cents',coalesce(p_opening_float_cents,0)));
  RETURN jsonb_build_object('ok',true,'shift_id',v_id);
END; $$;
REVOKE ALL ON FUNCTION public.shift_open(uuid,bigint) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.shift_open(uuid,bigint) TO authenticated, service_role;

-- Record a cash movement on an OPEN shift (shift's cashier, or a manager/owner
-- handling a manager-closure shift). Dedupes an order's cash per kind.
CREATE OR REPLACE FUNCTION public.shift_record_cash(
  p_shift uuid, p_kind text, p_amount_cents bigint, p_order_id uuid DEFAULT NULL, p_note text DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); sh public.cashier_shifts;
BEGIN
  SELECT * INTO sh FROM public.cashier_shifts WHERE id=p_shift FOR UPDATE;
  IF sh.id IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  IF sh.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','shift_not_open'); END IF;
  IF NOT (sh.cashier_user_id = v_uid OR public.can_manage_restaurant_staff(sh.restaurant_id, v_uid)) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  IF p_kind NOT IN ('receipt','deposit','refund','withdrawal','rider_cash_received') THEN
    RETURN jsonb_build_object('ok',false,'reason','bad_kind'); END IF;
  IF coalesce(p_amount_cents,0) < 0 THEN RETURN jsonb_build_object('ok',false,'reason','bad_amount'); END IF;
  BEGIN
    INSERT INTO public.shift_cash_movements(shift_id,restaurant_id,kind,amount_cents,order_id,note,created_by)
      VALUES (p_shift, sh.restaurant_id, p_kind, coalesce(p_amount_cents,0), p_order_id, p_note, v_uid);
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok',false,'reason','duplicate_order_cash');
  END;
  RETURN jsonb_build_object('ok',true,'expected_cash_cents',public.shift_expected_cash_cents(p_shift));
END; $$;
REVOKE ALL ON FUNCTION public.shift_record_cash(uuid,text,bigint,uuid,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.shift_record_cash(uuid,text,bigint,uuid,text) TO authenticated, service_role;

-- Submit a closing count. Freezes the report for review. Explanation required
-- when there is any variance. Allowed for the shift cashier, or a manager/owner
-- when the shift needs manager closure.
CREATE OR REPLACE FUNCTION public.shift_submit(p_shift uuid, p_counted_cash_cents bigint, p_explanation text DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); sh public.cashier_shifts; v_expected bigint; v_variance bigint;
BEGIN
  SELECT * INTO sh FROM public.cashier_shifts WHERE id=p_shift FOR UPDATE;
  IF sh.id IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  IF sh.status <> 'open' THEN RETURN jsonb_build_object('ok',false,'reason','not_open'); END IF;
  IF NOT (sh.cashier_user_id = v_uid
          OR (sh.requires_manager_closure AND public.can_manage_restaurant_staff(sh.restaurant_id, v_uid))) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  IF coalesce(p_counted_cash_cents,0) < 0 THEN RETURN jsonb_build_object('ok',false,'reason','bad_count'); END IF;

  v_expected := public.shift_expected_cash_cents(p_shift);
  v_variance := coalesce(p_counted_cash_cents,0) - v_expected;
  IF v_variance <> 0 AND coalesce(trim(p_explanation),'')='' THEN
    RETURN jsonb_build_object('ok',false,'reason','explanation_required','variance_cents',v_variance); END IF;

  UPDATE public.cashier_shifts SET
    status='submitted', closed_at=now(), counted_cash_cents=coalesce(p_counted_cash_cents,0),
    expected_cash_cents=v_expected, variance_cents=v_variance, variance_explanation=p_explanation,
    submitted_at=now(), submitted_by=v_uid, updated_at=now()
  WHERE id=p_shift;
  PERFORM public._rstaff_audit(sh.restaurant_id, v_uid, 'shift_submit', sh.cashier_user_id, p_explanation,
    NULL, jsonb_build_object('shift_id',p_shift,'expected_cents',v_expected,'counted_cents',p_counted_cash_cents,'variance_cents',v_variance));
  RETURN jsonb_build_object('ok',true,'expected_cents',v_expected,'variance_cents',v_variance);
END; $$;
REVOKE ALL ON FUNCTION public.shift_submit(uuid,bigint,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.shift_submit(uuid,bigint,text) TO authenticated, service_role;

-- Approve or return a submitted shift. Nobody approves their own report; the
-- approver may be neither the shift cashier nor the submitter.
CREATE OR REPLACE FUNCTION public.shift_approve(p_shift uuid, p_approve boolean, p_reason text DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); sh public.cashier_shifts;
BEGIN
  SELECT * INTO sh FROM public.cashier_shifts WHERE id=p_shift FOR UPDATE;
  IF sh.id IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  IF sh.status <> 'submitted' THEN RETURN jsonb_build_object('ok',false,'reason','not_submitted'); END IF;
  IF NOT public.can_manage_restaurant_staff(sh.restaurant_id, v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  IF v_uid = sh.cashier_user_id OR v_uid = sh.submitted_by THEN
    RETURN jsonb_build_object('ok',false,'reason','cannot_approve_own_report'); END IF;

  IF p_approve THEN
    UPDATE public.cashier_shifts SET status='approved', approved_at=now(), approved_by=v_uid, updated_at=now()
     WHERE id=p_shift;
    PERFORM public._rstaff_audit(sh.restaurant_id, v_uid, 'shift_approve', sh.cashier_user_id, NULL, NULL,
      jsonb_build_object('shift_id',p_shift));
    RETURN jsonb_build_object('ok',true,'status','approved');
  ELSE
    IF coalesce(trim(p_reason),'')='' THEN RETURN jsonb_build_object('ok',false,'reason','return_reason_required'); END IF;
    UPDATE public.cashier_shifts SET status='open', return_reason=p_reason, submitted_at=NULL, submitted_by=NULL,
      closed_at=NULL, updated_at=now()
     WHERE id=p_shift;
    PERFORM public._rstaff_audit(sh.restaurant_id, v_uid, 'shift_return', sh.cashier_user_id, p_reason, NULL,
      jsonb_build_object('shift_id',p_shift));
    RETURN jsonb_build_object('ok',true,'status','returned');
  END IF;
END; $$;
REVOKE ALL ON FUNCTION public.shift_approve(uuid,boolean,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.shift_approve(uuid,boolean,text) TO authenticated, service_role;

-- Post-approval correction (owner only). Separate adjustment record; never
-- overwrites the approved figures.
CREATE OR REPLACE FUNCTION public.shift_adjust(p_shift uuid, p_amount_cents bigint, p_reason text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); sh public.cashier_shifts;
BEGIN
  SELECT * INTO sh FROM public.cashier_shifts WHERE id=p_shift;
  IF sh.id IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  IF public.restaurant_staff_role(sh.restaurant_id, v_uid) <> 'owner' THEN
    RETURN jsonb_build_object('ok',false,'reason','owner_only'); END IF;
  IF sh.status <> 'approved' THEN RETURN jsonb_build_object('ok',false,'reason','only_approved_adjustable'); END IF;
  IF coalesce(trim(p_reason),'')='' THEN RETURN jsonb_build_object('ok',false,'reason','reason_required'); END IF;
  INSERT INTO public.shift_adjustments(shift_id,restaurant_id,amount_cents,reason,actor_user_id)
    VALUES (p_shift, sh.restaurant_id, p_amount_cents, p_reason, v_uid);
  PERFORM public._rstaff_audit(sh.restaurant_id, v_uid, 'shift_adjust', sh.cashier_user_id, p_reason, NULL,
    jsonb_build_object('shift_id',p_shift,'amount_cents',p_amount_cents));
  RETURN jsonb_build_object('ok',true);
END; $$;
REVOKE ALL ON FUNCTION public.shift_adjust(uuid,bigint,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.shift_adjust(uuid,bigint,text) TO authenticated, service_role;

-- Dashboard counts (owner/manager): presence + shift state in one call.
CREATE OR REPLACE FUNCTION public.cashier_dashboard_counts(p_restaurant uuid)
  RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT CASE WHEN NOT public.can_manage_restaurant_staff(p_restaurant)
    THEN jsonb_build_object('ok',false,'reason','not_authorized')
    ELSE jsonb_build_object(
      'ok',true,
      'active_cashiers',(SELECT count(*) FROM public.restaurant_staff WHERE restaurant_id=p_restaurant AND role='cashier' AND is_active),
      'online',(SELECT count(DISTINCT p.user_id) FROM public.cashier_presence p
                JOIN public.restaurant_staff s ON s.user_id=p.user_id AND s.restaurant_id=p_restaurant AND s.role='cashier' AND s.is_active
                WHERE p.restaurant_id=p_restaurant
                  AND p.last_seen_at > now() - make_interval(secs => public.cf_config_int('cashier_presence_timeout_s',90))),
      'open_shifts',(SELECT count(*) FROM public.cashier_shifts WHERE restaurant_id=p_restaurant AND status='open'),
      'submitted_awaiting_approval',(SELECT count(*) FROM public.cashier_shifts WHERE restaurant_id=p_restaurant AND status='submitted'),
      'needs_manager_closure',(SELECT count(*) FROM public.cashier_shifts WHERE restaurant_id=p_restaurant AND status='open' AND requires_manager_closure),
      'long_open',(SELECT count(*) FROM public.cashier_shifts WHERE restaurant_id=p_restaurant AND status='open'
                   AND opened_at < now() - make_interval(hours => public.cf_config_int('shift_open_flag_hours',16))))
  END;
$$;
GRANT EXECUTE ON FUNCTION public.cashier_dashboard_counts(uuid) TO authenticated, service_role;

-- Deactivating a cashier with an open shift flags it for manager closure
-- (never auto-closed / never assumes a count). Re-defines staff_set_active to
-- add the flagging step.
CREATE OR REPLACE FUNCTION public.staff_set_active(p_restaurant uuid, p_user uuid, p_active boolean)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_actor uuid := auth.uid(); v_actor_role text; v_target_role text; v_before jsonb;
BEGIN
  v_actor_role := public.restaurant_staff_role(p_restaurant, v_actor);
  IF v_actor_role NOT IN ('owner','manager') THEN RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  IF p_user = v_actor THEN RETURN jsonb_build_object('ok',false,'reason','no_self_action'); END IF;
  IF EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id=p_restaurant AND r.owner_id=p_user) THEN
    RETURN jsonb_build_object('ok',false,'reason','cannot_modify_owner'); END IF;
  SELECT role INTO v_target_role FROM public.restaurant_staff WHERE restaurant_id=p_restaurant AND user_id=p_user;
  IF v_target_role IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_a_member'); END IF;
  IF v_actor_role='manager' AND v_target_role<>'cashier' THEN
    RETURN jsonb_build_object('ok',false,'reason','manager_manages_cashiers_only'); END IF;

  SELECT to_jsonb(s) INTO v_before FROM public.restaurant_staff s WHERE restaurant_id=p_restaurant AND user_id=p_user;
  UPDATE public.restaurant_staff
     SET is_active=p_active, deactivated_at=CASE WHEN p_active THEN NULL ELSE now() END, updated_at=now()
   WHERE restaurant_id=p_restaurant AND user_id=p_user;

  -- Flag any open shift for manager closure (do NOT auto-close).
  IF NOT p_active THEN
    UPDATE public.cashier_shifts SET requires_manager_closure=true, updated_at=now()
     WHERE restaurant_id=p_restaurant AND cashier_user_id=p_user AND status='open';
  END IF;

  PERFORM public._rstaff_audit(p_restaurant, v_actor,
    CASE WHEN p_active THEN 'reactivate' ELSE 'deactivate' END, p_user, NULL, v_before,
    jsonb_build_object('is_active',p_active));
  RETURN jsonb_build_object('ok',true,'is_active',p_active);
END; $$;

NOTIFY pgrst, 'reload schema';

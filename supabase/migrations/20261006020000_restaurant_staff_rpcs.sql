-- ============================================================================
-- RESTAURANT STAFF — RPCs enforcing fixed-role rules + audit (Phase 1b).
-- All SECURITY DEFINER, pinned search_path, revoked from anon/PUBLIC.
-- ============================================================================

-- Internal audit writer (service/definer only; not client-callable).
CREATE OR REPLACE FUNCTION public._rstaff_audit(
  p_restaurant uuid, p_actor uuid, p_action text, p_target uuid,
  p_reason text, p_before jsonb, p_after jsonb)
  RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  INSERT INTO public.restaurant_staff_audit
    (restaurant_id, actor_user_id, action, target_user_id, reason, before_data, after_data)
  VALUES (p_restaurant, p_actor, p_action, p_target, p_reason, p_before, p_after);
$$;
REVOKE ALL ON FUNCTION public._rstaff_audit(uuid,uuid,text,uuid,text,jsonb,jsonb) FROM public, anon, authenticated;

-- Create an invitation. Returns the RAW token (only the hash is stored) for the
-- edge function to email. Owner → manager|cashier; manager → cashier only.
CREATE OR REPLACE FUNCTION public.staff_invite_create(p_restaurant uuid, p_email text, p_role text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
DECLARE v_actor uuid := auth.uid(); v_role text; v_token text; v_hash text; v_id uuid;
        v_email text := lower(trim(p_email)); v_recent int;
BEGIN
  IF v_actor IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;
  v_role := public.restaurant_staff_role(p_restaurant, v_actor);
  IF v_role NOT IN ('owner','manager') THEN RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  IF p_role NOT IN ('manager','cashier') THEN RETURN jsonb_build_object('ok',false,'reason','bad_role'); END IF;
  IF v_role='manager' AND p_role<>'cashier' THEN RETURN jsonb_build_object('ok',false,'reason','manager_can_invite_cashier_only'); END IF;
  IF v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' THEN RETURN jsonb_build_object('ok',false,'reason','bad_email'); END IF;

  -- Already an active member?
  IF EXISTS (SELECT 1 FROM public.restaurant_staff s JOIN public.users u ON u.id=s.user_id
             WHERE s.restaurant_id=p_restaurant AND lower(u.email)=v_email AND s.is_active) THEN
    RETURN jsonb_build_object('ok',false,'reason','already_member'); END IF;

  -- Rate limit: max 30 invites/hour per restaurant.
  SELECT count(*) INTO v_recent FROM public.staff_invitations
   WHERE restaurant_id=p_restaurant AND created_at > now() - interval '1 hour';
  IF v_recent >= 30 THEN RETURN jsonb_build_object('ok',false,'reason','rate_limited'); END IF;

  -- Resend: revoke any existing pending invite for this email.
  UPDATE public.staff_invitations SET status='revoked'
   WHERE restaurant_id=p_restaurant AND lower(email)=v_email AND status='pending';

  v_token := replace(gen_random_uuid()::text,'-','') || replace(gen_random_uuid()::text,'-','');
  v_hash  := encode(digest(v_token,'sha256'),'hex');
  INSERT INTO public.staff_invitations(restaurant_id,email,role,token_hash,invited_by,expires_at)
    VALUES (p_restaurant, v_email, p_role, v_hash, v_actor, now() + interval '72 hours')
    RETURNING id INTO v_id;

  PERFORM public._rstaff_audit(p_restaurant, v_actor, 'invite_create', NULL, NULL, NULL,
    jsonb_build_object('email',v_email,'role',p_role,'invitation_id',v_id));
  RETURN jsonb_build_object('ok',true,'invitation_id',v_id,'token',v_token,'email',v_email,'role',p_role);
END; $$;
REVOKE ALL ON FUNCTION public.staff_invite_create(uuid,text,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.staff_invite_create(uuid,text,text) TO authenticated, service_role;

-- Accept an invitation. Atomic + single-use; the authenticated user's VERIFIED
-- email must match the invitation; inviter authority + expiry re-checked.
CREATE OR REPLACE FUNCTION public.staff_accept_invitation(p_token text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, extensions, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_hash text; inv public.staff_invitations;
        v_user_email text; v_verified boolean;
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;
  v_hash := encode(digest(coalesce(p_token,''),'sha256'),'hex');

  SELECT lower(u.email), (au.email_confirmed_at IS NOT NULL)
    INTO v_user_email, v_verified
  FROM public.users u LEFT JOIN auth.users au ON au.id=u.id WHERE u.id=v_uid;
  IF NOT coalesce(v_verified,false) THEN RETURN jsonb_build_object('ok',false,'reason','email_not_verified'); END IF;

  -- Lock + consume the pending invite atomically.
  UPDATE public.staff_invitations SET status='accepted', accepted_at=now(), accepted_user_id=v_uid
   WHERE token_hash=v_hash AND status='pending' AND expires_at > now()
     AND lower(email)=v_user_email
   RETURNING * INTO inv;
  IF inv.id IS NULL THEN
    -- Distinguish expiry/mismatch for a friendlier message.
    IF EXISTS (SELECT 1 FROM public.staff_invitations WHERE token_hash=v_hash AND status='pending' AND expires_at<=now())
      THEN RETURN jsonb_build_object('ok',false,'reason','expired'); END IF;
    RETURN jsonb_build_object('ok',false,'reason','invalid_or_email_mismatch');
  END IF;

  -- Re-check the inviter still has authority.
  IF public.restaurant_staff_role(inv.restaurant_id, inv.invited_by) NOT IN ('owner','manager') THEN
    RETURN jsonb_build_object('ok',false,'reason','inviter_no_longer_authorized'); END IF;

  -- Create / reactivate membership (no duplicates).
  INSERT INTO public.restaurant_staff(restaurant_id,user_id,role,is_active,invited_by)
    VALUES (inv.restaurant_id, v_uid, inv.role, true, inv.invited_by)
  ON CONFLICT (restaurant_id,user_id) DO UPDATE
    SET role=EXCLUDED.role, is_active=true, deactivated_at=NULL, updated_at=now();

  PERFORM public._rstaff_audit(inv.restaurant_id, v_uid, 'invite_accept', v_uid, NULL, NULL,
    jsonb_build_object('role',inv.role,'invitation_id',inv.id));
  RETURN jsonb_build_object('ok',true,'restaurant_id',inv.restaurant_id,'role',inv.role);
END; $$;
REVOKE ALL ON FUNCTION public.staff_accept_invitation(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.staff_accept_invitation(text) TO authenticated, service_role;

-- Activate / deactivate a membership.
CREATE OR REPLACE FUNCTION public.staff_set_active(p_restaurant uuid, p_user uuid, p_active boolean)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_actor uuid := auth.uid(); v_actor_role text; v_target_role text; v_before jsonb;
BEGIN
  v_actor_role := public.restaurant_staff_role(p_restaurant, v_actor);
  IF v_actor_role NOT IN ('owner','manager') THEN RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  IF p_user = v_actor THEN RETURN jsonb_build_object('ok',false,'reason','no_self_action'); END IF;
  -- Owner (restaurants.owner_id) can never be deactivated here.
  IF EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id=p_restaurant AND r.owner_id=p_user) THEN
    RETURN jsonb_build_object('ok',false,'reason','cannot_modify_owner'); END IF;
  SELECT role INTO v_target_role FROM public.restaurant_staff WHERE restaurant_id=p_restaurant AND user_id=p_user;
  IF v_target_role IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_a_member'); END IF;
  -- Managers may only manage cashiers.
  IF v_actor_role='manager' AND v_target_role<>'cashier' THEN
    RETURN jsonb_build_object('ok',false,'reason','manager_manages_cashiers_only'); END IF;

  SELECT to_jsonb(s) INTO v_before FROM public.restaurant_staff s WHERE restaurant_id=p_restaurant AND user_id=p_user;
  UPDATE public.restaurant_staff
     SET is_active=p_active, deactivated_at=CASE WHEN p_active THEN NULL ELSE now() END, updated_at=now()
   WHERE restaurant_id=p_restaurant AND user_id=p_user;
  PERFORM public._rstaff_audit(p_restaurant, v_actor,
    CASE WHEN p_active THEN 'reactivate' ELSE 'deactivate' END, p_user, NULL, v_before,
    jsonb_build_object('is_active',p_active));
  RETURN jsonb_build_object('ok',true,'is_active',p_active);
END; $$;
REVOKE ALL ON FUNCTION public.staff_set_active(uuid,uuid,boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.staff_set_active(uuid,uuid,boolean) TO authenticated, service_role;

-- Change a member's role (owner only; manager|cashier only; never owner/self).
CREATE OR REPLACE FUNCTION public.staff_set_role(p_restaurant uuid, p_user uuid, p_role text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_actor uuid := auth.uid(); v_before jsonb;
BEGIN
  IF public.restaurant_staff_role(p_restaurant, v_actor) <> 'owner' THEN
    RETURN jsonb_build_object('ok',false,'reason','owner_only'); END IF;
  IF p_role NOT IN ('manager','cashier') THEN RETURN jsonb_build_object('ok',false,'reason','bad_role'); END IF;
  IF p_user = v_actor THEN RETURN jsonb_build_object('ok',false,'reason','no_self_action'); END IF;
  IF EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id=p_restaurant AND r.owner_id=p_user) THEN
    RETURN jsonb_build_object('ok',false,'reason','cannot_modify_owner'); END IF;
  SELECT to_jsonb(s) INTO v_before FROM public.restaurant_staff s WHERE restaurant_id=p_restaurant AND user_id=p_user;
  IF v_before IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_a_member'); END IF;
  UPDATE public.restaurant_staff SET role=p_role, updated_at=now()
   WHERE restaurant_id=p_restaurant AND user_id=p_user;
  PERFORM public._rstaff_audit(p_restaurant, v_actor, 'role_change', p_user, NULL, v_before,
    jsonb_build_object('role',p_role));
  RETURN jsonb_build_object('ok',true,'role',p_role);
END; $$;
REVOKE ALL ON FUNCTION public.staff_set_role(uuid,uuid,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.staff_set_role(uuid,uuid,text) TO authenticated, service_role;

-- Revoke a pending invitation.
CREATE OR REPLACE FUNCTION public.staff_revoke_invitation(p_invitation_id uuid)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_actor uuid := auth.uid(); v_rest uuid;
BEGIN
  SELECT restaurant_id INTO v_rest FROM public.staff_invitations WHERE id=p_invitation_id AND status='pending';
  IF v_rest IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  IF NOT public.can_manage_restaurant_staff(v_rest, v_actor) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  UPDATE public.staff_invitations SET status='revoked' WHERE id=p_invitation_id AND status='pending';
  PERFORM public._rstaff_audit(v_rest, v_actor, 'invite_revoke', NULL, NULL, NULL,
    jsonb_build_object('invitation_id',p_invitation_id));
  RETURN jsonb_build_object('ok',true);
END; $$;
REVOKE ALL ON FUNCTION public.staff_revoke_invitation(uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.staff_revoke_invitation(uuid) TO authenticated, service_role;

-- Staff list for the dashboard (owner/manager only): member + name/email/role/status.
CREATE OR REPLACE FUNCTION public.staff_list_members(p_restaurant uuid)
  RETURNS TABLE(user_id uuid, name text, email text, role text, is_active boolean,
                created_at timestamptz, deactivated_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT s.user_id, u.name, u.email, s.role, s.is_active, s.created_at, s.deactivated_at
  FROM public.restaurant_staff s JOIN public.users u ON u.id=s.user_id
  WHERE s.restaurant_id=p_restaurant AND public.can_manage_restaurant_staff(p_restaurant)
  ORDER BY s.is_active DESC, s.role, u.name;
$$;
GRANT EXECUTE ON FUNCTION public.staff_list_members(uuid) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

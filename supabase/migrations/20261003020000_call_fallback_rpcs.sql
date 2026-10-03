-- ============================================================================
-- CALL FALLBACK — authorization, safe projection, transition & reconcile RPCs.
-- ============================================================================

-- Is the current auth.uid() the driver assigned to this order, and is the order
-- still eligible for calling (active delivery, or within the post-delivery grace
-- window)? Returns the customer_user_id when eligible, else NULL.
CREATE OR REPLACE FUNCTION public.cf_order_callable_for_driver(p_order_id uuid, p_driver_user uuid)
  RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT o.user_id
  FROM public.orders o
  JOIN public.drivers d ON d.id = o.driver_id
  WHERE o.id = p_order_id
    AND d.user_id = p_driver_user
    AND (
      o.status IN ('confirmed','preparing','ready','picked_up','on_the_way','out_for_delivery')
      OR (o.status = 'delivered'
          AND coalesce(o.delivered_at, o.updated_at)
              > now() - make_interval(mins => public.cf_config_int('call_fallback_grace_minutes',15)))
    );
$$;

-- Driver requests a telephone fallback. Authorizes, enforces limits, and
-- atomically creates ONE session (dedupe via unique index). Never returns phones.
CREATE OR REPLACE FUNCTION public.request_call_fallback(
  p_order_id uuid, p_call_id uuid, p_reason text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_driver uuid := auth.uid();
  v_customer uuid;
  v_attempts int;
  v_last timestamptz;
  v_id uuid;
  v_max int := public.cf_config_int('call_fallback_max_attempts',2);
  v_cooldown int := public.cf_config_int('call_fallback_cooldown_s',60);
BEGIN
  IF v_driver IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;
  IF NOT public.call_fallback_enabled() THEN
    RETURN jsonb_build_object('ok',false,'reason','feature_disabled'); END IF;
  IF p_reason NOT IN ('connect_timeout','reconnect_failed','no_answer_manual') THEN
    RETURN jsonb_build_object('ok',false,'reason','bad_reason'); END IF;

  v_customer := public.cf_order_callable_for_driver(p_order_id, v_driver);
  IF v_customer IS NULL THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized_or_not_eligible'); END IF;

  -- Idempotency: if an active fallback already exists for this call, return it.
  SELECT id INTO v_id FROM public.call_fallback_sessions
   WHERE call_id = p_call_id
     AND status IN ('requested','dialing_driver','awaiting_driver_press','dialing_customer','bridged')
   LIMIT 1;
  IF v_id IS NOT NULL THEN
    RETURN jsonb_build_object('ok',true,'fallback_id',v_id,'status','existing','deduped',true); END IF;

  -- Attempt + cooldown limits (per order per driver).
  SELECT count(*), max(created_at) INTO v_attempts, v_last
  FROM public.call_fallback_sessions
  WHERE order_id = p_order_id AND driver_user_id = v_driver;
  IF v_attempts >= v_max THEN
    RETURN jsonb_build_object('ok',false,'reason','max_attempts_reached'); END IF;
  IF v_last IS NOT NULL AND v_last > now() - make_interval(secs => v_cooldown) THEN
    RETURN jsonb_build_object('ok',false,'reason','cooldown'); END IF;

  BEGIN
    INSERT INTO public.call_fallback_sessions
      (call_id, order_id, driver_user_id, customer_user_id, reason, status, provider,
       attempt_no, deadline_at)
    VALUES
      (p_call_id, p_order_id, v_driver, v_customer, p_reason, 'requested',
       coalesce((SELECT value FROM public.app_config WHERE key='call_fallback_provider'),'mock'),
       v_attempts + 1, now() + interval '90 seconds')
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    SELECT id INTO v_id FROM public.call_fallback_sessions
     WHERE call_id = p_call_id
       AND status IN ('requested','dialing_driver','awaiting_driver_press','dialing_customer','bridged')
     LIMIT 1;
    RETURN jsonb_build_object('ok',true,'fallback_id',v_id,'status','existing','deduped',true);
  END;

  RETURN jsonb_build_object('ok',true,'fallback_id',v_id,'status','requested');
END; $$;
REVOKE ALL ON FUNCTION public.request_call_fallback(uuid,uuid,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.request_call_fallback(uuid,uuid,text) TO authenticated, service_role;

-- Safe status projection for the requesting driver (NO phones, NO provider SIDs).
CREATE OR REPLACE FUNCTION public.get_call_fallback_status(p_fallback_id uuid)
  RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'fallback_id', s.id, 'status', s.status, 'reason', s.reason,
    'attempt_no', s.attempt_no, 'failure_code', s.failure_code,
    'updated_at', s.updated_at)
  FROM public.call_fallback_sessions s
  WHERE s.id = p_fallback_id AND s.driver_user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.get_call_fallback_status(uuid) TO authenticated, service_role;

-- Driver cancels a still-pending fallback (not yet bridged).
CREATE OR REPLACE FUNCTION public.cancel_call_fallback(p_fallback_id uuid)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_row public.call_fallback_sessions;
BEGIN
  UPDATE public.call_fallback_sessions
     SET status='cancelled', ended_at=now(), updated_at=now()
   WHERE id = p_fallback_id AND driver_user_id = auth.uid()
     AND status IN ('requested','dialing_driver','awaiting_driver_press','dialing_customer')
   RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_cancellable'); END IF;
  RETURN jsonb_build_object('ok',true,'status','cancelled');
END; $$;
GRANT EXECUTE ON FUNCTION public.cancel_call_fallback(uuid) TO authenticated, service_role;

-- SERVICE-ONLY: resolve both E.164 phone numbers at dial time + RE-CHECK that the
-- driver is still authorized for the order. Returns NULL phones if not authorized.
CREATE OR REPLACE FUNCTION public.cf_resolve_phones(p_fallback_id uuid)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE s public.call_fallback_sessions; v_driver_phone text; v_customer_phone text; v_ok uuid;
BEGIN
  SELECT * INTO s FROM public.call_fallback_sessions WHERE id = p_fallback_id;
  IF s.id IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  -- Re-authorize immediately before dialing the customer.
  v_ok := public.cf_order_callable_for_driver(s.order_id, s.driver_user_id);
  IF v_ok IS NULL OR v_ok <> s.customer_user_id THEN
    RETURN jsonb_build_object('ok',false,'reason','no_longer_authorized'); END IF;

  SELECT coalesce(d.phone_number, u.phone) INTO v_driver_phone
    FROM public.users u LEFT JOIN public.drivers d ON d.user_id=u.id WHERE u.id=s.driver_user_id;
  SELECT phone INTO v_customer_phone FROM public.users WHERE id=s.customer_user_id;

  IF v_driver_phone IS NULL OR v_customer_phone IS NULL THEN
    RETURN jsonb_build_object('ok',false,'reason','missing_phone'); END IF;

  RETURN jsonb_build_object('ok',true,'driver_phone',v_driver_phone,'customer_phone',v_customer_phone,
    'order_id',s.order_id,'status',s.status);
END; $$;
REVOKE ALL ON FUNCTION public.cf_resolve_phones(uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cf_resolve_phones(uuid) TO service_role;

-- SERVICE-ONLY: atomic status transition with optional provider metadata.
CREATE OR REPLACE FUNCTION public.cf_set_status(
  p_fallback_id uuid, p_expected_status text, p_new_status text,
  p_driver_sid text DEFAULT NULL, p_customer_sid text DEFAULT NULL,
  p_failure_code text DEFAULT NULL, p_cost numeric DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_row public.call_fallback_sessions; v_max int := public.cf_config_int('call_fallback_max_duration_s',300);
BEGIN
  UPDATE public.call_fallback_sessions SET
    status = p_new_status,
    provider_driver_sid   = coalesce(p_driver_sid, provider_driver_sid),
    provider_customer_sid = coalesce(p_customer_sid, provider_customer_sid),
    failure_code = coalesce(p_failure_code, failure_code),
    cost_amount  = coalesce(p_cost, cost_amount),
    dialed_customer_at = CASE WHEN p_new_status='dialing_customer' THEN now() ELSE dialed_customer_at END,
    bridged_at   = CASE WHEN p_new_status='bridged' THEN now() ELSE bridged_at END,
    ended_at     = CASE WHEN p_new_status IN ('completed','failed','cancelled','no_answer') THEN now() ELSE ended_at END,
    deadline_at  = CASE WHEN p_new_status='bridged' THEN now() + make_interval(secs => v_max)
                        WHEN p_new_status IN ('completed','failed','cancelled','no_answer') THEN NULL
                        ELSE now() + interval '90 seconds' END,
    updated_at = now()
  WHERE id = p_fallback_id
    AND (p_expected_status IS NULL OR status = p_expected_status)
  RETURNING * INTO v_row;
  IF v_row.id IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','state_conflict'); END IF;
  RETURN jsonb_build_object('ok',true,'status',v_row.status);
END; $$;
REVOKE ALL ON FUNCTION public.cf_set_status(uuid,text,text,text,text,text,numeric) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cf_set_status(uuid,text,text,text,text,text,numeric) TO service_role;

-- Durable timeout worker (run by cron). Expires sessions whose deadline passed:
-- pending/dialing -> failed (timeout); bridged past max duration -> completed.
CREATE OR REPLACE FUNCTION public.cf_reconcile_deadlines()
  RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_n int;
BEGIN
  UPDATE public.call_fallback_sessions
     SET status = CASE WHEN status='bridged' THEN 'completed' ELSE 'failed' END,
         failure_code = CASE WHEN status='bridged' THEN failure_code ELSE coalesce(failure_code,'timeout') END,
         ended_at = now(), deadline_at = NULL, updated_at = now()
   WHERE deadline_at IS NOT NULL AND deadline_at < now()
     AND status IN ('requested','dialing_driver','awaiting_driver_press','dialing_customer','bridged');
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n;
END; $$;
REVOKE ALL ON FUNCTION public.cf_reconcile_deadlines() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cf_reconcile_deadlines() TO service_role;

-- Admin call-log view (safe: no phones; SIDs visible to admin only via base-table RLS).
CREATE OR REPLACE FUNCTION public.admin_call_fallback_log(p_limit int DEFAULT 100)
  RETURNS TABLE(id uuid, order_id uuid, driver_name text, reason text, status text,
                duration_seconds int, failure_code text, cost_amount numeric, created_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT s.id, s.order_id, du.name, s.reason, s.status,
         CASE WHEN s.bridged_at IS NOT NULL AND s.ended_at IS NOT NULL
              THEN EXTRACT(EPOCH FROM (s.ended_at - s.bridged_at))::int END,
         s.failure_code, s.cost_amount, s.created_at
  FROM public.call_fallback_sessions s
  LEFT JOIN public.users du ON du.id = s.driver_user_id
  WHERE public.is_admin()
  ORDER BY s.created_at DESC
  LIMIT greatest(1, least(p_limit, 500));
$$;
GRANT EXECUTE ON FUNCTION public.admin_call_fallback_log(int) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Restaurant Pickup Coordinator — engine (trigger, dial, outcome rules, jobs).
-- All functions are idempotent and re-check conditions so duplicate events or
-- concurrent runs cannot double-call or produce conflicting status updates.
-- ============================================================================

-- The follow-up threshold in minutes (config-driven).
CREATE OR REPLACE FUNCTION public.pickup_threshold_minutes()
RETURNS int LANGUAGE sql STABLE AS $$
  SELECT COALESCE((SELECT value::int FROM app_config WHERE key='pickup_followup_minutes'), 15);
$$;

-- ALL trigger conditions in one place (used by scan AND re-checked before dialing
-- and before executing a scheduled job).
CREATE OR REPLACE FUNCTION public.pickup_conditions_met(p_order_id uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE
SET search_path = public
AS $$
DECLARE o orders%ROWTYPE; v_min int;
BEGIN
  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF NOT FOUND THEN RETURN false; END IF;
  -- 3 & 4: still awaiting prep (not preparing/ready/out_for_delivery/delivered/cancelled).
  IF o.status NOT IN ('pending','confirmed') THEN RETURN false; END IF;
  -- payment collected (prepaid card must be completed; COD/cash ok).
  IF COALESCE(o.payment_method,'') IN ('stripe','card')
     AND COALESCE(o.payment_status,'') <> 'completed' THEN RETURN false; END IF;
  -- 2: >= threshold minutes since acceptance (confirmed_at, else placement).
  v_min := public.pickup_threshold_minutes();
  IF COALESCE(o.confirmed_at, o.created_at) > now() - make_interval(mins => v_min) THEN
    RETURN false;
  END IF;
  RETURN true;
END;
$$;

-- Scan: enqueue exactly one call per due order (idempotent), and cancel any
-- queued call whose order left the trigger window before dialing.
CREATE OR REPLACE FUNCTION public.pickup_scan_and_enqueue()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_enq int := 0; v_cancel int := 0; r record;
BEGIN
  -- Cancel queued calls that no longer qualify (e.g. restaurant moved to Preparing).
  FOR r IN SELECT c.id, c.order_id FROM restaurant_pickup_calls c
           WHERE c.status='queued' FOR UPDATE
  LOOP
    IF NOT public.pickup_conditions_met(r.order_id) THEN
      UPDATE restaurant_pickup_calls
         SET status='cancelled', outcome='conditions_changed', completed_at=now(),
             notes=COALESCE(notes,'')||' auto-cancelled: order left trigger window'
       WHERE id=r.id;
      v_cancel := v_cancel + 1;
    END IF;
  END LOOP;

  -- Enqueue due orders with no existing call row (UNIQUE(order_id) = one per order).
  FOR r IN
    SELECT o.id AS order_id, o.restaurant_id
    FROM orders o
    WHERE o.status IN ('pending','confirmed')
      AND (COALESCE(o.payment_method,'') NOT IN ('stripe','card') OR o.payment_status='completed')
      AND COALESCE(o.confirmed_at, o.created_at) <= now() - make_interval(mins => public.pickup_threshold_minutes())
      AND o.created_at >= now() - interval '3 hours'   -- don't chase ancient stuck orders
      AND NOT EXISTS (SELECT 1 FROM restaurant_pickup_calls c WHERE c.order_id = o.id)
    LIMIT 200
  LOOP
    INSERT INTO restaurant_pickup_calls(order_id, restaurant_id, status)
    VALUES (r.order_id, r.restaurant_id, 'queued')
    ON CONFLICT (order_id) DO NOTHING;
    v_enq := v_enq + 1;
  END LOOP;

  RETURN jsonb_build_object('enqueued', v_enq, 'cancelled', v_cancel);
END;
$$;

-- Called by the telephony integration immediately before placing the call.
-- Re-checks conditions; cancels the call if the order left the window; else
-- marks it dialing and returns the phone + short reference for the dialer.
CREATE OR REPLACE FUNCTION public.pickup_begin_dial(p_call_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE c restaurant_pickup_calls%ROWTYPE; v_phone text; v_name text;
BEGIN
  SELECT * INTO c FROM restaurant_pickup_calls WHERE id=p_call_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','call_not_found'); END IF;
  IF c.status <> 'queued' THEN
    RETURN jsonb_build_object('ok',false,'reason','not_queued','status',c.status);
  END IF;
  IF NOT public.pickup_conditions_met(c.order_id) THEN
    UPDATE restaurant_pickup_calls SET status='cancelled', outcome='conditions_changed',
           completed_at=now() WHERE id=p_call_id;
    RETURN jsonb_build_object('ok',false,'reason','conditions_changed');
  END IF;
  SELECT r.phone, r.name INTO v_phone, v_name FROM restaurants r WHERE r.id=c.restaurant_id;
  UPDATE restaurant_pickup_calls SET status='dialing', dialed_at=now() WHERE id=p_call_id;
  RETURN jsonb_build_object('ok',true,'call_id',p_call_id,
    'order_ref', upper(substr(c.order_id::text,1,8)),
    'restaurant_name', v_name, 'restaurant_phone', v_phone);
END;
$$;

-- Internal: authorized status transition + timeline event + rider notify (only
-- on a genuine change). Records the source of the change.
CREATE OR REPLACE FUNCTION public._pickup_set_status(
  p_order_id uuid, p_new_status text, p_source text, p_call_id uuid)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE o orders%ROWTYPE; v_url text; v_key text;
BEGIN
  SELECT * INTO o FROM orders WHERE id=p_order_id FOR UPDATE;
  IF o.status = p_new_status THEN RETURN; END IF;  -- no genuine change

  UPDATE orders SET status=p_new_status, updated_at=now(),
    preparing_started_at = CASE WHEN p_new_status='preparing' THEN COALESCE(preparing_started_at, now()) ELSE preparing_started_at END,
    ready_at = CASE WHEN p_new_status='ready' THEN now() ELSE ready_at END
  WHERE id=p_order_id;

  INSERT INTO order_status_events(order_id, status, actor_type, metadata)
  VALUES (p_order_id, p_new_status, 'system',
          jsonb_build_object('actor', 'ai_pickup_coordinator',
                             'source', p_source, 'call_id', p_call_id));

  -- Notify the assigned rider only when the status genuinely changed (esp. Ready).
  IF o.driver_id IS NOT NULL THEN
    v_url := 'https://yharweliruemjexmuuxn.supabase.co';
    v_key := coalesce(nullif(current_setting('app.settings.service_role_key', true), ''),
                      'sb_publishable_TSislwYLCUtwfkUnglQWBQ_3drsd82-');
    BEGIN
      PERFORM extensions.http_post(
        url := v_url || '/functions/v1/send-fcm-notification',
        body := jsonb_build_object(
          'topic', 'driver_' || o.driver_id::text,
          'title', CASE WHEN p_new_status='ready' THEN 'Order ready for pickup' ELSE 'Order update' END,
          'body',  'Order #' || upper(substr(p_order_id::text,1,8)) || ' is now ' || p_new_status || '.',
          'data',  jsonb_build_object('type','pickup_status','order_id',p_order_id::text,'status',p_new_status)
        )::text,
        headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key)
      );
    EXCEPTION WHEN OTHERS THEN NULL; -- notification failure must not block the transition
    END;
  END IF;
END;
$$;

-- Record the call outcome and apply the STATUS RULES. Idempotent: only acts on a
-- queued/dialing call. Supplied by the telephony/IVR integration or an agent.
CREATE OR REPLACE FUNCTION public.pickup_record_call_outcome(
  p_call_id uuid,
  p_prep_underway boolean DEFAULT NULL,
  p_ready_now boolean DEFAULT false,
  p_confirmed_ready_at timestamptz DEFAULT NULL,
  p_auto_authorized boolean DEFAULT false,
  p_delay_reported boolean DEFAULT false,
  p_unfulfillable boolean DEFAULT false,
  p_notes text DEFAULT NULL)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE c restaurant_pickup_calls%ROWTYPE; o orders%ROWTYPE; v_outcome text;
BEGIN
  SELECT * INTO c FROM restaurant_pickup_calls WHERE id=p_call_id FOR UPDATE;
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','call_not_found'); END IF;
  IF c.status NOT IN ('queued','dialing') THEN
    RETURN jsonb_build_object('ok',true,'idempotent',true,'status',c.status,'outcome',c.outcome);
  END IF;

  SELECT * INTO o FROM orders WHERE id=c.order_id;

  -- Order already progressed/closed on its own → nothing to change.
  IF o.status NOT IN ('pending','confirmed') THEN
    v_outcome := 'conditions_changed';
  ELSIF p_unfulfillable THEN
    v_outcome := 'unfulfillable';           -- escalate, no status change
    PERFORM public._pickup_cancel_jobs(c.order_id, 'unfulfillable');
  ELSIF p_delay_reported THEN
    v_outcome := 'delay';                    -- record delay; cancel any auto-ready job
    IF p_confirmed_ready_at IS NOT NULL THEN
      UPDATE orders SET expected_ready_at = p_confirmed_ready_at WHERE id=c.order_id;
    END IF;
    PERFORM public._pickup_cancel_jobs(c.order_id, 'delay_reported');
  ELSIF p_ready_now THEN
    PERFORM public._pickup_set_status(c.order_id, 'ready', 'call_ready_now', p_call_id);
    v_outcome := 'ready_now';
    PERFORM public._pickup_cancel_jobs(c.order_id, 'ready_now');
  ELSIF p_prep_underway IS TRUE THEN
    PERFORM public._pickup_set_status(c.order_id, 'preparing', 'call_confirmed', p_call_id);
    IF p_confirmed_ready_at IS NOT NULL AND p_confirmed_ready_at > now() THEN
      UPDATE orders SET expected_ready_at = p_confirmed_ready_at WHERE id=c.order_id;
      IF p_auto_authorized THEN
        -- Schedule the authorized automatic Ready (supersede any existing active job).
        UPDATE restaurant_ready_jobs SET status='superseded', executed_at=now()
          WHERE order_id=c.order_id AND status='scheduled';
        INSERT INTO restaurant_ready_jobs(order_id, call_id, run_at, authorized, source)
          VALUES (c.order_id, p_call_id, p_confirmed_ready_at, true, 'restaurant-authorized automated update');
        v_outcome := 'scheduled_auto';
      ELSE
        v_outcome := 'expected_only';        -- store expected time; no auto Ready
      END IF;
    ELSE
      v_outcome := 'preparing';
    END IF;
  ELSE
    v_outcome := 'no_prep';                  -- prep not started; escalate, no status change
  END IF;

  UPDATE restaurant_pickup_calls SET
    status='completed', completed_at=now(),
    prep_underway = p_prep_underway,
    confirmed_ready_at = p_confirmed_ready_at,
    auto_ready_authorized = p_auto_authorized,
    delay_reported = p_delay_reported,
    outcome = v_outcome,
    notes = COALESCE(p_notes, notes)
  WHERE id=p_call_id;

  RETURN jsonb_build_object('ok',true,'outcome',v_outcome);
END;
$$;

-- Cancel/supersede any active scheduled Ready job for an order.
CREATE OR REPLACE FUNCTION public._pickup_cancel_jobs(p_order_id uuid, p_reason text)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE restaurant_ready_jobs SET status='cancelled', executed_at=now(),
         source = COALESCE(source,'')||' | cancelled:'||p_reason
   WHERE order_id=p_order_id AND status='scheduled';
$$;

-- Execute due scheduled Ready jobs. Re-checks the order is still Preparing, not
-- cancelled, no newer delay, and the authorization still applies before marking
-- Ready with the authorized-automated source. Idempotent + concurrency-safe.
CREATE OR REPLACE FUNCTION public.pickup_run_ready_jobs()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE j record; o orders%ROWTYPE; v_done int := 0; v_skip int := 0;
BEGIN
  FOR j IN SELECT * FROM restaurant_ready_jobs
           WHERE status='scheduled' AND run_at <= now() FOR UPDATE
  LOOP
    SELECT * INTO o FROM orders WHERE id=j.order_id;
    IF j.authorized
       AND o.status = 'preparing'
       AND NOT EXISTS (SELECT 1 FROM restaurant_pickup_calls c
                       WHERE c.order_id=j.order_id AND c.delay_reported IS TRUE)
    THEN
      PERFORM public._pickup_set_status(j.order_id, 'ready',
              'restaurant-authorized automated update', j.call_id);
      UPDATE restaurant_ready_jobs SET status='done', executed_at=now() WHERE id=j.id;
      v_done := v_done + 1;
    ELSE
      UPDATE restaurant_ready_jobs SET status='cancelled', executed_at=now(),
             source=COALESCE(source,'')||' | skipped:conditions_no_longer_hold' WHERE id=j.id;
      v_skip := v_skip + 1;
    END IF;
  END LOOP;
  RETURN jsonb_build_object('marked_ready', v_done, 'skipped', v_skip);
END;
$$;

REVOKE ALL ON FUNCTION public.pickup_scan_and_enqueue() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pickup_begin_dial(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pickup_record_call_outcome(uuid,boolean,boolean,timestamptz,boolean,boolean,boolean,text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.pickup_run_ready_jobs() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._pickup_set_status(uuid,text,text,uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._pickup_cancel_jobs(uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.pickup_scan_and_enqueue() TO service_role;
GRANT EXECUTE ON FUNCTION public.pickup_begin_dial(uuid) TO service_role;
GRANT EXECUTE ON FUNCTION public.pickup_record_call_outcome(uuid,boolean,boolean,timestamptz,boolean,boolean,boolean,text) TO service_role;
GRANT EXECUTE ON FUNCTION public.pickup_run_ready_jobs() TO service_role;
GRANT EXECUTE ON FUNCTION public.pickup_conditions_met(uuid) TO service_role, authenticated;
GRANT EXECUTE ON FUNCTION public.pickup_threshold_minutes() TO service_role, authenticated;

-- Cron: scan every 3 minutes, run due Ready jobs every minute.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname='pg_cron') THEN
    PERFORM cron.unschedule('pickup-scan') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='pickup-scan');
    PERFORM cron.unschedule('pickup-ready-jobs') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='pickup-ready-jobs');
    PERFORM cron.schedule('pickup-scan', '*/3 * * * *', $c$ SELECT public.pickup_scan_and_enqueue(); $c$);
    PERFORM cron.schedule('pickup-ready-jobs', '* * * * *', $c$ SELECT public.pickup_run_ready_jobs(); $c$);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

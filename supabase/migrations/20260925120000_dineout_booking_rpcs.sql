-- HotBite DineOut — booking engine (atomic, concurrency-safe). All mutations go
-- through these SECURITY DEFINER RPCs. The GiST EXCLUDE on
-- dineout_reservation_tables is the race-proof guarantee: two concurrent holds
-- for the same table/time can never both succeed.

-- ── ATOMIC: create a hold (or confirmed booking when no deposit) ────────────
CREATE OR REPLACE FUNCTION public.dineout_create_hold(
  p_restaurant_id uuid,
  p_reserved_from timestamptz,
  p_party_size    int,
  p_package_id    uuid DEFAULT NULL,
  p_preorder      jsonb DEFAULT '[]'::jsonb,
  p_idempotency_key text DEFAULT NULL,
  p_guest_name    text DEFAULT NULL,
  p_guest_phone   text DEFAULT NULL
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  s public.dineout_settings;
  v_uid uuid := auth.uid();
  v_dur int; v_to timestamptz; v_buf timestamptz;
  v_res_id uuid; v_ref text; v_status text;
  v_assigned boolean := false;
  cand record; combo record; member uuid;
  v_pkg public.dineout_packages;
  v_subtotal numeric := 0; v_deposit numeric := 0;
  v_existing uuid; v_online_count int; v_dow int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  IF p_idempotency_key IS NOT NULL THEN
    SELECT id INTO v_existing FROM dineout_reservations WHERE idempotency_key = p_idempotency_key;
    IF v_existing IS NOT NULL THEN
      RETURN (SELECT to_jsonb(r) FROM dineout_reservations r WHERE r.id = v_existing);
    END IF;
  END IF;

  SELECT * INTO s FROM dineout_settings WHERE restaurant_id = p_restaurant_id;
  IF s.restaurant_id IS NULL OR NOT s.enabled THEN RAISE EXCEPTION 'DINEOUT_DISABLED'; END IF;
  IF p_party_size < s.min_party OR p_party_size > s.max_party THEN RAISE EXCEPTION 'PARTY_OUT_OF_RANGE'; END IF;
  IF p_reserved_from < now() THEN RAISE EXCEPTION 'PAST_TIME'; END IF;
  IF p_reserved_from > now() + make_interval(days => s.advance_booking_days) THEN RAISE EXCEPTION 'TOO_FAR_AHEAD'; END IF;

  SELECT duration_min INTO v_dur FROM dineout_duration_rules
    WHERE restaurant_id=p_restaurant_id AND p_party_size BETWEEN min_party AND max_party
    ORDER BY (max_party-min_party) ASC LIMIT 1;
  v_dur := COALESCE(v_dur, s.default_duration_min);
  v_to  := p_reserved_from + make_interval(mins => v_dur);
  v_buf := v_to + make_interval(mins => s.cleanup_buffer_min);

  -- within a dine-in hours window for the restaurant's local weekday
  v_dow := EXTRACT(DOW FROM (p_reserved_from AT TIME ZONE s.timezone))::int;
  IF NOT EXISTS (
    SELECT 1 FROM dineout_schedules sc
    WHERE sc.restaurant_id=p_restaurant_id AND sc.day_of_week=v_dow
      AND (p_reserved_from AT TIME ZONE s.timezone)::time >= sc.open_time
      AND (v_to AT TIME ZONE s.timezone)::time <= sc.close_time
  ) THEN RAISE EXCEPTION 'OUTSIDE_HOURS'; END IF;

  IF EXISTS (SELECT 1 FROM dineout_exceptions e WHERE e.restaurant_id=p_restaurant_id AND e.table_id IS NULL
             AND tstzrange(e.blocked_from,e.blocked_to) && tstzrange(p_reserved_from,v_buf)) THEN
    RAISE EXCEPTION 'BLOCKED_PERIOD';
  END IF;

  IF s.max_online_per_slot IS NOT NULL THEN
    SELECT count(*) INTO v_online_count FROM dineout_reservations r
      WHERE r.restaurant_id=p_restaurant_id AND r.source='online'
        AND r.status IN ('hold','pending_payment','confirmed','seated')
        AND tstzrange(r.reserved_from,r.buffer_to) && tstzrange(p_reserved_from,v_buf);
    IF v_online_count >= s.max_online_per_slot THEN RAISE EXCEPTION 'ONLINE_LIMIT_REACHED'; END IF;
  END IF;

  IF p_package_id IS NOT NULL THEN
    SELECT * INTO v_pkg FROM dineout_packages WHERE id=p_package_id AND restaurant_id=p_restaurant_id AND is_available;
    IF v_pkg.id IS NULL THEN RAISE EXCEPTION 'PACKAGE_UNAVAILABLE'; END IF;
    v_subtotal := v_pkg.price * (CASE WHEN v_pkg.per_person THEN p_party_size ELSE 1 END);
  END IF;
  v_subtotal := v_subtotal + COALESCE((
    SELECT sum(COALESCE(m.dinein_price, m.price) * COALESCE((i->>'quantity')::int,1))
    FROM jsonb_array_elements(COALESCE(p_preorder,'[]'::jsonb)) i
    JOIN menus m ON m.id = (i->>'menu_item_id')::uuid), 0);
  v_deposit := CASE WHEN s.deposit_required
                    THEN s.deposit_amount * (CASE WHEN s.deposit_per_person THEN p_party_size ELSE 1 END)
                    ELSE 0 END;
  v_status := CASE WHEN s.deposit_required AND v_deposit > 0 THEN 'pending_payment' ELSE 'confirmed' END;
  v_ref := 'DO-' || upper(substr(md5(random()::text||clock_timestamp()::text),1,8));

  INSERT INTO dineout_reservations(
    restaurant_id, user_id, reservation_ref, party_size, reserved_from, reserved_to, buffer_to,
    status, source, package_id, preorder, guest_name, guest_phone,
    subtotal, deposit_amount, deposit_status, total, payable_at_restaurant,
    idempotency_key, hold_expires_at)
  VALUES (
    p_restaurant_id, v_uid, v_ref, p_party_size, p_reserved_from, v_to, v_buf,
    v_status, 'online', p_package_id, COALESCE(p_preorder,'[]'::jsonb), p_guest_name, p_guest_phone,
    v_subtotal, v_deposit, CASE WHEN v_deposit>0 THEN 'pending' ELSE 'none' END,
    v_subtotal, GREATEST(v_subtotal - v_deposit, 0),
    p_idempotency_key,
    CASE WHEN v_status='pending_payment' THEN now() + make_interval(mins => s.hold_ttl_min) ELSE NULL END)
  RETURNING id INTO v_res_id;

  -- Single table: smallest that fits, exclusion-safe.
  FOR cand IN
    SELECT t.id FROM dineout_tables t
    WHERE t.restaurant_id=p_restaurant_id AND t.is_active AND t.online_bookable AND NOT t.held_for_walkin
      AND t.seat_capacity >= p_party_size
      AND NOT EXISTS (SELECT 1 FROM dineout_exceptions e WHERE e.table_id=t.id
                      AND tstzrange(e.blocked_from,e.blocked_to) && tstzrange(p_reserved_from,v_buf))
    ORDER BY t.seat_capacity ASC, t.sort_order ASC
  LOOP
    BEGIN
      INSERT INTO dineout_reservation_tables(reservation_id, table_id, restaurant_id, during)
        VALUES (v_res_id, cand.id, p_restaurant_id, tstzrange(p_reserved_from, v_buf, '[)'));
      v_assigned := true; EXIT;
    EXCEPTION WHEN exclusion_violation THEN CONTINUE;  -- taken by a concurrent booking
    END;
  END LOOP;

  -- Permitted combination fallback (all member tables must be free together).
  IF NOT v_assigned THEN
    FOR combo IN
      SELECT * FROM dineout_table_combinations c
      WHERE c.restaurant_id=p_restaurant_id AND c.is_active AND c.online_bookable
        AND c.total_capacity >= p_party_size
      ORDER BY c.total_capacity ASC
    LOOP
      BEGIN
        FOREACH member IN ARRAY combo.table_ids LOOP
          INSERT INTO dineout_reservation_tables(reservation_id, table_id, restaurant_id, during)
            VALUES (v_res_id, member, p_restaurant_id, tstzrange(p_reserved_from, v_buf, '[)'));
        END LOOP;
        v_assigned := true; EXIT;
      EXCEPTION WHEN exclusion_violation THEN CONTINUE;  -- savepoint rolls back partial combo
      END;
    END LOOP;
  END IF;

  IF NOT v_assigned THEN RAISE EXCEPTION 'NO_AVAILABILITY'; END IF;  -- rolls back reservation

  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (v_res_id, NULL, v_status, v_uid, 'online booking');

  RETURN (SELECT to_jsonb(r) FROM dineout_reservations r WHERE r.id=v_res_id);
END;
$fn$;
REVOKE ALL ON FUNCTION public.dineout_create_hold(uuid,timestamptz,int,uuid,jsonb,text,text,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dineout_create_hold(uuid,timestamptz,int,uuid,jsonb,text,text,text) TO authenticated, service_role;

-- ── idempotent confirm (after deposit paid, or straight from hold) ─────────
CREATE OR REPLACE FUNCTION public.dineout_confirm_reservation(
  p_reservation_id uuid, p_payment_intent_id text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE r public.dineout_reservations;
BEGIN
  SELECT * INTO r FROM dineout_reservations WHERE id=p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  IF NOT (r.user_id=auth.uid() OR public.current_user_owns_restaurant(r.restaurant_id)
          OR public.is_admin() OR COALESCE(auth.role(),'')='service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF r.status='confirmed' THEN RETURN to_jsonb(r); END IF;   -- idempotent
  IF r.status NOT IN ('hold','pending_payment') THEN RAISE EXCEPTION 'BAD_STATE'; END IF;
  UPDATE dineout_reservations SET status='confirmed',
     deposit_status = CASE WHEN deposit_amount>0 THEN 'paid' ELSE deposit_status END,
     payment_intent_id = COALESCE(p_payment_intent_id, payment_intent_id),
     hold_expires_at = NULL, updated_at = now()
   WHERE id=p_reservation_id RETURNING * INTO r;
  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (p_reservation_id, 'pending_payment', 'confirmed', auth.uid(), 'confirmed');
  RETURN to_jsonb(r);
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.dineout_confirm_reservation(uuid,text) TO authenticated, service_role;

-- ── cron: release expired holds (frees capacity safely) ────────────────────
CREATE OR REPLACE FUNCTION public.dineout_release_expired_holds()
RETURNS int LANGUAGE sql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  WITH expired AS (
    UPDATE dineout_reservations SET status='expired', updated_at=now()
     WHERE status IN ('hold','pending_payment') AND hold_expires_at IS NOT NULL AND hold_expires_at < now()
     RETURNING id
  ), rel AS (
    UPDATE dineout_reservation_tables SET active=false
     WHERE reservation_id IN (SELECT id FROM expired) AND active
     RETURNING 1
  )
  SELECT COALESCE((SELECT count(*) FROM expired), 0)::int;
$fn$;
GRANT EXECUTE ON FUNCTION public.dineout_release_expired_holds() TO service_role;

-- ── staff / guest operations ───────────────────────────────────────────────
-- helper: assert caller manages this reservation's restaurant
CREATE OR REPLACE FUNCTION public._dineout_assert_staff(p_res public.dineout_reservations)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  IF NOT (public.current_user_owns_restaurant(p_res.restaurant_id) OR public.is_admin()
          OR COALESCE(auth.role(),'')='service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN'; END IF;
END; $fn$;

CREATE OR REPLACE FUNCTION public.dineout_seat(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r public.dineout_reservations;
BEGIN
  SELECT * INTO r FROM dineout_reservations WHERE id=p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  PERFORM public._dineout_assert_staff(r);
  IF r.status NOT IN ('confirmed') THEN RAISE EXCEPTION 'BAD_STATE'; END IF;
  UPDATE dineout_reservations SET status='seated', seated_at=now(), updated_at=now() WHERE id=p_reservation_id RETURNING * INTO r;
  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (p_reservation_id, 'confirmed', 'seated', auth.uid(), 'checked in / seated');
  RETURN to_jsonb(r);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.dineout_seat(uuid) TO authenticated, service_role;

-- Two-step release: mark departed, then clean+release. Estimated end NEVER frees.
CREATE OR REPLACE FUNCTION public.dineout_mark_departed(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r public.dineout_reservations;
BEGIN
  SELECT * INTO r FROM dineout_reservations WHERE id=p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  PERFORM public._dineout_assert_staff(r);
  IF r.status <> 'seated' THEN RAISE EXCEPTION 'BAD_STATE'; END IF;
  UPDATE dineout_reservations SET departed_at=now(), updated_at=now() WHERE id=p_reservation_id RETURNING * INTO r;
  -- table stays active (still needs cleaning) — capacity NOT yet released.
  RETURN to_jsonb(r);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.dineout_mark_departed(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dineout_clean_and_release(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r public.dineout_reservations;
BEGIN
  SELECT * INTO r FROM dineout_reservations WHERE id=p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  PERFORM public._dineout_assert_staff(r);
  IF r.status NOT IN ('seated') THEN RAISE EXCEPTION 'BAD_STATE'; END IF;
  UPDATE dineout_reservations SET status='completed', cleaned_at=now(),
     departed_at=COALESCE(departed_at, now()), updated_at=now() WHERE id=p_reservation_id RETURNING * INTO r;
  UPDATE dineout_reservation_tables SET active=false WHERE reservation_id=p_reservation_id AND active;
  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (p_reservation_id, 'seated', 'completed', auth.uid(), 'cleaned & released');
  RETURN to_jsonb(r);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.dineout_clean_and_release(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dineout_no_show(p_reservation_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r public.dineout_reservations;
BEGIN
  SELECT * INTO r FROM dineout_reservations WHERE id=p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  PERFORM public._dineout_assert_staff(r);
  IF r.status NOT IN ('confirmed') THEN RAISE EXCEPTION 'BAD_STATE'; END IF;
  UPDATE dineout_reservations SET status='no_show',
     deposit_status = CASE WHEN deposit_amount>0 THEN 'forfeited' ELSE deposit_status END, updated_at=now()
   WHERE id=p_reservation_id RETURNING * INTO r;
  UPDATE dineout_reservation_tables SET active=false WHERE reservation_id=p_reservation_id AND active;
  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (p_reservation_id, 'confirmed', 'no_show', auth.uid(), 'no-show');
  RETURN to_jsonb(r);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.dineout_no_show(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.dineout_cancel(p_reservation_id uuid, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE r public.dineout_reservations; s public.dineout_settings; v_late boolean;
BEGIN
  SELECT * INTO r FROM dineout_reservations WHERE id=p_reservation_id FOR UPDATE;
  IF r.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;
  -- guest may cancel own; staff/admin may cancel any of their restaurant's.
  IF NOT (r.user_id=auth.uid() OR public.current_user_owns_restaurant(r.restaurant_id)
          OR public.is_admin() OR COALESCE(auth.role(),'')='service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN'; END IF;
  IF r.status IN ('cancelled','completed','no_show','expired') THEN RETURN to_jsonb(r); END IF; -- idempotent
  SELECT * INTO s FROM dineout_settings WHERE restaurant_id=r.restaurant_id;
  v_late := r.reserved_from - now() < make_interval(hours => COALESCE(s.cancellation_cutoff_hrs,0));
  UPDATE dineout_reservations SET status='cancelled', cancelled_at=now(), cancellation_reason=p_reason,
     deposit_status = CASE WHEN deposit_amount>0 THEN (CASE WHEN v_late THEN 'forfeited' ELSE 'refunded' END) ELSE deposit_status END,
     updated_at=now()
   WHERE id=p_reservation_id RETURNING * INTO r;
  UPDATE dineout_reservation_tables SET active=false WHERE reservation_id=p_reservation_id AND active;
  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (p_reservation_id, r.status, 'cancelled', auth.uid(), COALESCE(p_reason,'cancelled'));
  RETURN to_jsonb(r);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.dineout_cancel(uuid,text) TO authenticated, service_role;

-- Walk-in: staff seat a party directly on a specific table (exclusion-safe).
CREATE OR REPLACE FUNCTION public.dineout_walkin(
  p_restaurant_id uuid, p_table_id uuid, p_party_size int, p_duration_min int DEFAULT NULL,
  p_guest_name text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE s public.dineout_settings; v_dur int; v_to timestamptz; v_buf timestamptz; v_res_id uuid; v_ref text;
BEGIN
  IF NOT (public.current_user_owns_restaurant(p_restaurant_id) OR public.is_admin()
          OR COALESCE(auth.role(),'')='service_role') THEN RAISE EXCEPTION 'FORBIDDEN'; END IF;
  SELECT * INTO s FROM dineout_settings WHERE restaurant_id=p_restaurant_id;
  v_dur := COALESCE(p_duration_min, s.default_duration_min, 90);
  v_to  := now() + make_interval(mins => v_dur);
  v_buf := v_to + make_interval(mins => COALESCE(s.cleanup_buffer_min,0));
  v_ref := 'DW-' || upper(substr(md5(random()::text||clock_timestamp()::text),1,8));
  INSERT INTO dineout_reservations(restaurant_id, user_id, reservation_ref, party_size, reserved_from,
     reserved_to, buffer_to, status, source, guest_name)
   VALUES (p_restaurant_id, NULL, v_ref, p_party_size, now(), v_to, v_buf, 'seated', 'walkin', p_guest_name)
   RETURNING id INTO v_res_id;
  -- exclusion constraint rejects if the table is occupied for this window
  INSERT INTO dineout_reservation_tables(reservation_id, table_id, restaurant_id, during)
    VALUES (v_res_id, p_table_id, p_restaurant_id, tstzrange(now(), v_buf, '[)'));
  UPDATE dineout_reservations SET seated_at=now() WHERE id=v_res_id;
  INSERT INTO dineout_status_history(reservation_id, from_status, to_status, changed_by, note)
    VALUES (v_res_id, NULL, 'seated', auth.uid(), 'walk-in seated');
  RETURN (SELECT to_jsonb(r) FROM dineout_reservations r WHERE r.id=v_res_id);
END; $fn$;
GRANT EXECUTE ON FUNCTION public.dineout_walkin(uuid,uuid,int,int,text) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

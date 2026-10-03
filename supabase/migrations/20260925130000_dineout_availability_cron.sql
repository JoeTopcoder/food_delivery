-- DineOut availability (read-only slot list for the customer picker) + hold-expiry
-- cron + a "running long" staff alert helper. The authoritative capacity check
-- stays in dineout_create_hold (atomic); this is only for display.

CREATE OR REPLACE FUNCTION public.dineout_availability(
  p_restaurant_id uuid, p_date date, p_party_size int
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE
  s public.dineout_settings; v_dow int; slots jsonb := '[]'::jsonb;
  v_slot timestamptz; sc record; v_dur int; v_to timestamptz; v_buf timestamptz; v_ok boolean;
BEGIN
  SELECT * INTO s FROM dineout_settings WHERE restaurant_id=p_restaurant_id;
  IF s.restaurant_id IS NULL OR NOT s.enabled THEN
    RETURN jsonb_build_object('enabled', false, 'slots', '[]'::jsonb);
  END IF;
  v_dow := EXTRACT(DOW FROM p_date)::int;
  SELECT duration_min INTO v_dur FROM dineout_duration_rules
    WHERE restaurant_id=p_restaurant_id AND p_party_size BETWEEN min_party AND max_party
    ORDER BY (max_party-min_party) LIMIT 1;
  v_dur := COALESCE(v_dur, s.default_duration_min);

  FOR sc IN SELECT open_time, close_time FROM dineout_schedules
            WHERE restaurant_id=p_restaurant_id AND day_of_week=v_dow LOOP
    v_slot := ((p_date + sc.open_time)::timestamp) AT TIME ZONE s.timezone;
    WHILE ((v_slot AT TIME ZONE s.timezone)::time + make_interval(mins => v_dur)) <= sc.close_time LOOP
      v_to  := v_slot + make_interval(mins => v_dur);
      v_buf := v_to + make_interval(mins => s.cleanup_buffer_min);
      IF v_slot > now() THEN
        SELECT EXISTS (
          SELECT 1 FROM dineout_tables t
          WHERE t.restaurant_id=p_restaurant_id AND t.is_active AND t.online_bookable
            AND NOT t.held_for_walkin AND t.seat_capacity >= p_party_size
            AND NOT EXISTS (SELECT 1 FROM dineout_reservation_tables rt
                            WHERE rt.table_id=t.id AND rt.active AND rt.during && tstzrange(v_slot, v_buf))
            AND NOT EXISTS (SELECT 1 FROM dineout_exceptions e
                            WHERE e.restaurant_id=p_restaurant_id AND (e.table_id=t.id OR e.table_id IS NULL)
                              AND tstzrange(e.blocked_from, e.blocked_to) && tstzrange(v_slot, v_buf))
        ) INTO v_ok;
        slots := slots || jsonb_build_object('time', v_slot, 'available', v_ok);
      END IF;
      v_slot := v_slot + make_interval(mins => s.booking_interval_min);
    END LOOP;
  END LOOP;
  RETURN jsonb_build_object('enabled', true, 'duration_min', v_dur, 'slots', slots);
END;
$fn$;
REVOKE ALL ON FUNCTION public.dineout_availability(uuid,date,int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.dineout_availability(uuid,date,int) TO authenticated, service_role;

-- Overdue tables: seated past their buffer end and not yet released. Staff alert
-- source; the table stays unavailable (active) until they clean & release.
CREATE OR REPLACE FUNCTION public.dineout_overdue_tables(p_restaurant_id uuid)
RETURNS TABLE(reservation_id uuid, reservation_ref text, table_labels text, minutes_over int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $fn$
  SELECT r.id, r.reservation_ref,
         string_agg(t.label, ', ' ORDER BY t.label),
         (EXTRACT(EPOCH FROM (now() - r.buffer_to))/60)::int
  FROM dineout_reservations r
  JOIN dineout_reservation_tables rt ON rt.reservation_id=r.id AND rt.active
  JOIN dineout_tables t ON t.id=rt.table_id
  WHERE r.restaurant_id=p_restaurant_id AND r.status='seated' AND r.buffer_to < now()
  GROUP BY r.id, r.reservation_ref;
$fn$;
GRANT EXECUTE ON FUNCTION public.dineout_overdue_tables(uuid) TO authenticated, service_role;

-- Cron: release expired holds every 2 minutes.
SELECT cron.unschedule('dineout-release-holds') WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname='dineout-release-holds');
SELECT cron.schedule('dineout-release-holds', '*/2 * * * *', $$SELECT public.dineout_release_expired_holds();$$);

NOTIFY pgrst, 'reload schema';

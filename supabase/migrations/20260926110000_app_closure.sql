-- ============================================================================
-- App closure ("we're closed for the holiday") — a global kill switch for
-- CHECKOUT on specific dates. Customers can still browse and add to cart, and
-- can still SCHEDULE an order for an OPEN date; only checkout for a CLOSED date
-- is blocked. Enforced server-side by a BEFORE INSERT trigger on orders, so no
-- client can bypass it. A public status RPC drives the home notice banner.
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.app_closures (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  closed_date date NOT NULL UNIQUE,
  reason      text,
  active      boolean NOT NULL DEFAULT true,
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_app_closures_active ON public.app_closures(closed_date) WHERE active;

ALTER TABLE public.app_closures ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_closures_admin ON public.app_closures;
CREATE POLICY app_closures_admin ON public.app_closures FOR ALL
  USING (EXISTS (SELECT 1 FROM users u WHERE u.id=auth.uid() AND u.role='admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM users u WHERE u.id=auth.uid() AND u.role='admin'));

-- Default closed message.
INSERT INTO app_config(key,value)
SELECT 'app_closed_message',
  'We''re closed today. You can still browse and add to cart, and schedule an order for another day. Thanks for your patience!'
WHERE NOT EXISTS (SELECT 1 FROM app_config WHERE key='app_closed_message');

-- Today's date in the business timezone.
CREATE OR REPLACE FUNCTION public.hotbite_today()
RETURNS date LANGUAGE sql STABLE AS $$
  SELECT (now() AT TIME ZONE 'America/Jamaica')::date;
$$;

-- Is checkout closed on a given date?
CREATE OR REPLACE FUNCTION public.app_is_closed_on(p_date date)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM app_closures WHERE active AND closed_date = p_date);
$$;

-- Public status for the customer app (banner + checkout).
CREATE OR REPLACE FUNCTION public.app_closure_status()
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE v_today date := public.hotbite_today(); v_closed boolean;
BEGIN
  v_closed := public.app_is_closed_on(v_today);
  RETURN jsonb_build_object(
    'today', v_today,
    'closed_today', v_closed,
    'message', COALESCE((SELECT reason FROM app_closures WHERE active AND closed_date=v_today),
                        (SELECT value FROM app_config WHERE key='app_closed_message')),
    'upcoming', COALESCE((SELECT jsonb_agg(jsonb_build_object('date',closed_date,'reason',reason) ORDER BY closed_date)
                          FROM app_closures WHERE active AND closed_date >= v_today), '[]'::jsonb));
END;
$$;
GRANT EXECUTE ON FUNCTION public.app_closure_status() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.app_is_closed_on(date) TO authenticated, anon, service_role;
GRANT EXECUTE ON FUNCTION public.hotbite_today() TO authenticated, anon, service_role;

-- Admin: set / clear a closure date; quick-close today; set message.
CREATE OR REPLACE FUNCTION public.admin_set_app_closure(p_date date, p_active boolean, p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_admin uuid;
BEGIN
  v_admin := public.require_admin();
  INSERT INTO app_closures(closed_date, reason, active, created_by)
  VALUES (p_date, p_reason, p_active, v_admin)
  ON CONFLICT (closed_date) DO UPDATE SET active=EXCLUDED.active, reason=COALESCE(EXCLUDED.reason, app_closures.reason);
  RETURN jsonb_build_object('ok',true,'date',p_date,'active',p_active);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_app_closure(date,boolean,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_close_today(p_reason text DEFAULT NULL)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  SELECT public.admin_set_app_closure(public.hotbite_today(), true, p_reason);
$$;
GRANT EXECUTE ON FUNCTION public.admin_close_today(text) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_set_closure_message(p_message text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public.require_admin();
  INSERT INTO app_config(key,value) VALUES ('app_closed_message', COALESCE(p_message,''))
    ON CONFLICT (key) DO UPDATE SET value=EXCLUDED.value;
  RETURN jsonb_build_object('ok',true);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_closure_message(text) TO authenticated;

-- Authoritative enforcement: block an order whose fulfillment date is closed.
-- Immediate orders target today; scheduled orders target their scheduled date.
-- Scheduling for an OPEN date is always allowed.
CREATE OR REPLACE FUNCTION public.enforce_app_closure()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_target date;
BEGIN
  v_target := COALESCE((NEW.scheduled_for AT TIME ZONE 'America/Jamaica')::date, public.hotbite_today());
  IF public.app_is_closed_on(v_target) THEN
    RAISE EXCEPTION 'APP_CLOSED: HotBite is closed on %. You can still schedule an order for an open date.', v_target
      USING ERRCODE='check_violation';
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_enforce_app_closure ON public.orders;
CREATE TRIGGER trg_enforce_app_closure BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.enforce_app_closure();

NOTIFY pgrst, 'reload schema';

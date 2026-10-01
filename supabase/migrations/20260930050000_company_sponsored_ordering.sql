-- ============================================================================
-- Company-Sponsored Ordering — backend (data model + server-authoritative RPCs).
--
-- Companies register, employees apply with their normal HotBite account, the
-- company admin approves. Approved employees of an ACTIVE company may place ONE
-- company-sponsored order per Jamaica calendar day, from a restaurant within the
-- company's radius, delivered to the company address. The employee pays for food
-- only; the company owes delivery + service fees (flat daily tiers).
--
-- Money for company charges is stored in INTEGER CENTS (JMD) — never float.
-- All validation/pricing is server-side. RLS confines each role.
-- ============================================================================

-- ─── Tables ─────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.companies (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name           text NOT NULL,
  admin_user_id  uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  contact_email  text,
  contact_phone  text,
  delivery_address text NOT NULL,
  latitude       double precision,
  longitude      double precision,
  radius_km      smallint NOT NULL DEFAULT 3 CHECK (radius_km IN (2,3,4)),
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS companies_admin_idx ON public.companies(admin_user_id);

CREATE TABLE IF NOT EXISTS public.company_members (
  id         uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  user_id    uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  status     text NOT NULL DEFAULT 'pending'
               CHECK (status IN ('pending','approved','rejected','suspended')),
  applied_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  decided_by uuid REFERENCES public.users(id),
  UNIQUE (company_id, user_id)
);
CREATE INDEX IF NOT EXISTS company_members_user_idx ON public.company_members(user_id);
CREATE INDEX IF NOT EXISTS company_members_company_idx ON public.company_members(company_id);

-- Daily usage / reservation. Partial unique index enforces ONE active
-- (reserved|placed) sponsorship per employee per Jamaica day — the atomic
-- guard against two simultaneous checkouts both succeeding.
CREATE TABLE IF NOT EXISTS public.company_sponsorship_usage (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  company_id  uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  usage_date  date NOT NULL,
  status      text NOT NULL DEFAULT 'reserved'
                CHECK (status IN ('reserved','placed','released')),
  order_id    uuid REFERENCES public.orders(id) ON DELETE SET NULL,
  expires_at  timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS company_usage_one_per_day
  ON public.company_sponsorship_usage(user_id, usage_date)
  WHERE status IN ('reserved','placed');
CREATE INDEX IF NOT EXISTS company_usage_company_date_idx
  ON public.company_sponsorship_usage(company_id, usage_date, status);

-- Finalised daily statement per company (settled charges + snapshot of rules).
CREATE TABLE IF NOT EXISTS public.company_daily_statements (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  company_id           uuid NOT NULL REFERENCES public.companies(id) ON DELETE CASCADE,
  statement_date       date NOT NULL,
  qualifying_orders    int  NOT NULL DEFAULT 0,
  delivery_tier_cents  int  NOT NULL DEFAULT 0,  -- per-order delivery fee applied
  total_delivery_cents int  NOT NULL DEFAULT 0,
  total_service_cents  int  NOT NULL DEFAULT 0,
  total_owed_cents     int  NOT NULL DEFAULT 0,
  is_final             boolean NOT NULL DEFAULT false,
  pricing_rules        jsonb,                    -- snapshot so later config can't rewrite history
  finalized_at         timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now(),
  UNIQUE (company_id, statement_date)
);

-- ─── Sponsorship fields on the existing order record ────────────────────────
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_company_sponsored     boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS company_id               uuid REFERENCES public.companies(id),
  ADD COLUMN IF NOT EXISTS company_sponsorship_date date,
  ADD COLUMN IF NOT EXISTS company_delivery_cents   int,
  ADD COLUMN IF NOT EXISTS company_service_cents    int,
  ADD COLUMN IF NOT EXISTS company_address_snapshot jsonb,
  ADD COLUMN IF NOT EXISTS company_distance_km      double precision,
  ADD COLUMN IF NOT EXISTS company_radius_km        smallint,
  ADD COLUMN IF NOT EXISTS company_charge_status    text
      CHECK (company_charge_status IN ('estimated','final'));

-- ─── Helpers ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.jamaica_today()
  RETURNS date LANGUAGE sql STABLE SET search_path = public, pg_temp
AS $$ SELECT (now() AT TIME ZONE 'America/Jamaica')::date $$;

-- Straight-line (haversine) distance in km.
CREATE OR REPLACE FUNCTION public.geo_distance_km(
  lat1 double precision, lon1 double precision,
  lat2 double precision, lon2 double precision)
  RETURNS double precision LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN lat1 IS NULL OR lon1 IS NULL OR lat2 IS NULL OR lon2 IS NULL THEN NULL
    ELSE 6371.0 * 2 * asin(sqrt(
        power(sin(radians(lat2-lat1)/2),2) +
        cos(radians(lat1))*cos(radians(lat2))*power(sin(radians(lon2-lon1)/2),2)
      ))
  END
$$;

-- Flat daily delivery tier (JMD cents) for a given qualifying-order count.
CREATE OR REPLACE FUNCTION public.company_delivery_tier_cents(p_count int)
  RETURNS int LANGUAGE sql IMMUTABLE SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN p_count >= 31 THEN 15000
    WHEN p_count >= 11 THEN 20000
    ELSE 25900
  END
$$;

-- Is the caller the admin of this company?
CREATE OR REPLACE FUNCTION public.is_company_admin(p_company uuid)
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM public.companies c
                 WHERE c.id = p_company AND c.admin_user_id = auth.uid());
$$;

-- ─── Membership RPCs ────────────────────────────────────────────────────────
-- Employee applies to a company (pinned to the caller; cannot self-approve).
CREATE OR REPLACE FUNCTION public.company_apply(p_company_id uuid)
  RETURNS public.company_members
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_row public.company_members;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  INSERT INTO public.company_members (company_id, user_id, status)
  VALUES (p_company_id, v_uid, 'pending')
  ON CONFLICT (company_id, user_id) DO UPDATE
    SET status = CASE WHEN public.company_members.status IN ('rejected','suspended')
                      THEN 'pending' ELSE public.company_members.status END,
        applied_at = now()
  RETURNING * INTO v_row;
  RETURN v_row;
END; $$;

-- Company admin approves/rejects/suspends a member (never the employee).
CREATE OR REPLACE FUNCTION public.company_decide_member(p_member_id uuid, p_status text)
  RETURNS public.company_members
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_row public.company_members;
BEGIN
  IF p_status NOT IN ('approved','rejected','suspended') THEN
    RAISE EXCEPTION 'Invalid status %', p_status;
  END IF;
  SELECT * INTO v_row FROM public.company_members WHERE id = p_member_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Member not found'; END IF;
  IF NOT public.is_company_admin(v_row.company_id) AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  UPDATE public.company_members
     SET status = p_status, decided_at = now(), decided_by = auth.uid()
   WHERE id = p_member_id
  RETURNING * INTO v_row;
  RETURN v_row;
END; $$;

-- ─── Eligibility / distance ─────────────────────────────────────────────────
-- Companies the caller can currently use for a sponsored order (approved +
-- active + not already used today).
CREATE OR REPLACE FUNCTION public.company_eligible_for_checkout()
  RETURNS TABLE (company_id uuid, name text, delivery_address text,
                 latitude double precision, longitude double precision, radius_km smallint)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT c.id, c.name, c.delivery_address, c.latitude, c.longitude, c.radius_km
  FROM public.companies c
  JOIN public.company_members m ON m.company_id = c.id
  WHERE m.user_id = auth.uid() AND m.status = 'approved' AND c.is_active
    AND NOT EXISTS (
      SELECT 1 FROM public.company_sponsorship_usage u
      WHERE u.user_id = auth.uid() AND u.usage_date = public.jamaica_today()
        AND u.status IN ('reserved','placed')
    );
$$;

-- Validate a restaurant against a company's radius. Returns eligibility + reason.
CREATE OR REPLACE FUNCTION public.company_check_restaurant(p_company_id uuid, p_restaurant_id uuid)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE c public.companies; rlat double precision; rlon double precision; d double precision;
BEGIN
  SELECT * INTO c FROM public.companies WHERE id = p_company_id;
  IF c.id IS NULL THEN RETURN jsonb_build_object('eligible',false,'reason','company_not_found'); END IF;
  SELECT latitude, longitude INTO rlat, rlon FROM public.restaurants WHERE id = p_restaurant_id;
  IF c.latitude IS NULL OR c.longitude IS NULL OR rlat IS NULL OR rlon IS NULL THEN
    RETURN jsonb_build_object('eligible',false,'reason','missing_coordinates','radius_km',c.radius_km);
  END IF;
  d := public.geo_distance_km(rlat, rlon, c.latitude, c.longitude);
  RETURN jsonb_build_object(
    'eligible', d <= c.radius_km,
    'reason', CASE WHEN d <= c.radius_km THEN 'ok' ELSE 'outside_radius' END,
    'distance_km', round(d::numeric,3), 'radius_km', c.radius_km);
END; $$;

-- ─── Atomic reserve / confirm / release ─────────────────────────────────────
-- Reserve the day's single sponsorship. Revalidates membership, company status,
-- coordinates and radius, then takes the per-user/day slot via the partial
-- unique index. Returns reservation id + estimated company charge.
CREATE OR REPLACE FUNCTION public.company_reserve_sponsorship(
  p_company_id uuid, p_restaurant_id uuid, p_hold_minutes int DEFAULT 15)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); c public.companies; chk jsonb;
        v_id uuid; v_today date := public.jamaica_today(); v_count int; v_tier int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;
  SELECT * INTO c FROM public.companies WHERE id = p_company_id;
  IF c.id IS NULL OR NOT c.is_active THEN
    RETURN jsonb_build_object('ok',false,'reason','company_inactive'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.company_members m
                 WHERE m.company_id = p_company_id AND m.user_id = v_uid AND m.status='approved') THEN
    RETURN jsonb_build_object('ok',false,'reason','not_approved_member'); END IF;
  chk := public.company_check_restaurant(p_company_id, p_restaurant_id);
  IF (chk->>'eligible')::boolean IS NOT TRUE THEN
    RETURN jsonb_build_object('ok',false,'reason', chk->>'reason',
                              'distance_km', chk->'distance_km','radius_km', c.radius_km); END IF;

  -- Clear any of this user's own expired reservations before taking the slot.
  UPDATE public.company_sponsorship_usage SET status='released'
   WHERE user_id=v_uid AND usage_date=v_today AND status='reserved'
     AND expires_at IS NOT NULL AND expires_at < now();

  BEGIN
    INSERT INTO public.company_sponsorship_usage (user_id, company_id, usage_date, status, expires_at)
    VALUES (v_uid, p_company_id, v_today, 'reserved', now() + make_interval(mins => p_hold_minutes))
    RETURNING id INTO v_id;
  EXCEPTION WHEN unique_violation THEN
    RETURN jsonb_build_object('ok',false,'reason','already_used_today');
  END;

  -- Estimated per-order delivery based on the company's current day count (+ this one).
  SELECT count(*) INTO v_count FROM public.company_sponsorship_usage
   WHERE company_id=p_company_id AND usage_date=v_today AND status IN ('reserved','placed');
  v_tier := public.company_delivery_tier_cents(v_count);

  RETURN jsonb_build_object(
    'ok', true, 'reservation_id', v_id,
    'company_id', p_company_id, 'company_name', c.name,
    'delivery_address', c.delivery_address,
    'latitude', c.latitude, 'longitude', c.longitude, 'radius_km', c.radius_km,
    'distance_km', chk->'distance_km',
    'estimated_delivery_cents', v_tier);
END; $$;

-- Confirm after the order is created: links the order, zeroes the employee's
-- delivery/service, records the company charges (estimated), marks slot placed.
CREATE OR REPLACE FUNCTION public.company_confirm_sponsorship(
  p_reservation_id uuid, p_order_id uuid)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE u public.company_sponsorship_usage; c public.companies; o public.orders;
        v_service_cents int; v_count int; v_tier int;
BEGIN
  SELECT * INTO u FROM public.company_sponsorship_usage WHERE id=p_reservation_id FOR UPDATE;
  IF u.id IS NULL THEN RAISE EXCEPTION 'Reservation not found'; END IF;
  IF u.status = 'placed' AND u.order_id = p_order_id THEN
    RETURN jsonb_build_object('ok',true,'already',true);  -- idempotent
  END IF;
  IF u.status <> 'reserved' THEN RAISE EXCEPTION 'Reservation not active'; END IF;

  SELECT * INTO c FROM public.companies WHERE id=u.company_id;
  SELECT * INTO o FROM public.orders WHERE id=p_order_id;
  IF o.id IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;

  -- Service fee the company absorbs = whatever the order computed (JMD -> cents).
  v_service_cents := round(coalesce(o.platform_service_fee,0)::numeric * 100)::int;

  SELECT count(*) INTO v_count FROM public.company_sponsorship_usage
   WHERE company_id=u.company_id AND usage_date=u.usage_date AND status IN ('reserved','placed');
  v_tier := public.company_delivery_tier_cents(v_count);

  UPDATE public.company_sponsorship_usage
     SET status='placed', order_id=p_order_id, expires_at=NULL WHERE id=p_reservation_id;

  UPDATE public.orders SET
     is_company_sponsored = true,
     company_id = u.company_id,
     company_sponsorship_date = u.usage_date,
     company_delivery_cents = v_tier,
     company_service_cents  = v_service_cents,
     company_address_snapshot = jsonb_build_object('address',c.delivery_address,'lat',c.latitude,'lon',c.longitude),
     company_distance_km = public.geo_distance_km(
        (SELECT latitude FROM public.restaurants WHERE id=o.restaurant_id),
        (SELECT longitude FROM public.restaurants WHERE id=o.restaurant_id),
        c.latitude, c.longitude),
     company_radius_km = c.radius_km,
     company_charge_status = 'estimated'
   WHERE id = p_order_id;

  RETURN jsonb_build_object('ok',true,'delivery_cents',v_tier,'service_cents',v_service_cents);
END; $$;

-- Release a reservation that never became an order (failed/abandoned payment).
CREATE OR REPLACE FUNCTION public.company_release_sponsorship(p_reservation_id uuid)
  RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.company_sponsorship_usage
     SET status='released'
   WHERE id=p_reservation_id AND user_id=auth.uid() AND status='reserved';
END; $$;

-- ─── Estimates & finalisation ───────────────────────────────────────────────
-- Live estimate for a company's day (admin view).
CREATE OR REPLACE FUNCTION public.company_daily_estimate(p_company_id uuid, p_date date DEFAULT NULL)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE d date := coalesce(p_date, public.jamaica_today());
        v_count int; v_tier int; v_service int; v_fin boolean;
BEGIN
  IF NOT public.is_company_admin(p_company_id) AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized'; END IF;
  SELECT is_final INTO v_fin FROM public.company_daily_statements
   WHERE company_id=p_company_id AND statement_date=d;
  IF v_fin THEN
    RETURN (SELECT to_jsonb(s) FROM public.company_daily_statements s
            WHERE company_id=p_company_id AND statement_date=d) || jsonb_build_object('final',true);
  END IF;
  SELECT count(*) INTO v_count FROM public.orders
   WHERE company_id=p_company_id AND company_sponsorship_date=d
     AND is_company_sponsored AND status <> 'cancelled';
  v_tier := public.company_delivery_tier_cents(v_count);
  SELECT coalesce(sum(company_service_cents),0) INTO v_service FROM public.orders
   WHERE company_id=p_company_id AND company_sponsorship_date=d
     AND is_company_sponsored AND status <> 'cancelled';
  RETURN jsonb_build_object('final',false,'date',d,'qualifying_orders',v_count,
    'delivery_tier_cents',v_tier,'total_delivery_cents',v_tier*v_count,
    'total_service_cents',v_service,'total_owed_cents',v_tier*v_count + v_service);
END; $$;

-- Finalise a closed day. Idempotent: upserts the statement, applies the final
-- tier to every qualifying order, stamps them 'final'. Safe to retry.
CREATE OR REPLACE FUNCTION public.company_finalize_day(p_company_id uuid, p_date date)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_count int; v_tier int; v_service int;
BEGIN
  SELECT count(*), coalesce(sum(company_service_cents),0)
    INTO v_count, v_service FROM public.orders
   WHERE company_id=p_company_id AND company_sponsorship_date=p_date
     AND is_company_sponsored AND status <> 'cancelled';
  v_tier := public.company_delivery_tier_cents(v_count);

  UPDATE public.orders
     SET company_delivery_cents = v_tier, company_charge_status='final'
   WHERE company_id=p_company_id AND company_sponsorship_date=p_date
     AND is_company_sponsored AND status <> 'cancelled';

  INSERT INTO public.company_daily_statements AS s
    (company_id, statement_date, qualifying_orders, delivery_tier_cents,
     total_delivery_cents, total_service_cents, total_owed_cents, is_final,
     pricing_rules, finalized_at)
  VALUES (p_company_id, p_date, v_count, v_tier, v_tier*v_count, v_service,
          v_tier*v_count + v_service, true,
          jsonb_build_object('tiers', jsonb_build_array(
            jsonb_build_object('min',1,'max',10,'cents',25900),
            jsonb_build_object('min',11,'max',30,'cents',20000),
            jsonb_build_object('min',31,'max',null,'cents',15000))),
          now())
  ON CONFLICT (company_id, statement_date) DO UPDATE
    SET qualifying_orders=excluded.qualifying_orders,
        delivery_tier_cents=excluded.delivery_tier_cents,
        total_delivery_cents=excluded.total_delivery_cents,
        total_service_cents=excluded.total_service_cents,
        total_owed_cents=excluded.total_owed_cents,
        is_final=true, finalized_at=now();

  RETURN jsonb_build_object('ok',true,'qualifying_orders',v_count,
    'delivery_tier_cents',v_tier,'total_owed_cents',v_tier*v_count + v_service);
END; $$;

-- ─── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.companies                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_members           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_sponsorship_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_daily_statements  ENABLE ROW LEVEL SECURITY;

-- companies: anyone signed in can read active companies (to search/apply);
-- the company admin manages their own; HotBite admin manages all.
CREATE POLICY companies_read ON public.companies FOR SELECT TO authenticated
  USING (is_active OR admin_user_id = auth.uid() OR public.is_admin());
CREATE POLICY companies_admin_update ON public.companies FOR UPDATE TO authenticated
  USING (admin_user_id = auth.uid() OR public.is_admin())
  WITH CHECK (admin_user_id = auth.uid() OR public.is_admin());
CREATE POLICY companies_insert ON public.companies FOR INSERT TO authenticated
  WITH CHECK (admin_user_id = auth.uid() OR public.is_admin());
CREATE POLICY companies_admin_delete ON public.companies FOR DELETE TO authenticated
  USING (public.is_admin());

-- company_members: employee sees their own rows; company admin sees their
-- company's; HotBite admin sees all. Writes go through RPCs (SECURITY DEFINER).
CREATE POLICY members_read ON public.company_members FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_company_admin(company_id) OR public.is_admin());

-- usage: employee sees own; company admin sees their company's; admin all.
CREATE POLICY usage_read ON public.company_sponsorship_usage FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_company_admin(company_id) OR public.is_admin());

-- statements: company admin + HotBite admin.
CREATE POLICY statements_read ON public.company_daily_statements FOR SELECT TO authenticated
  USING (public.is_company_admin(company_id) OR public.is_admin());

-- ─── Grants (RPCs) ──────────────────────────────────────────────────────────
REVOKE ALL ON FUNCTION public.company_apply(uuid),
  public.company_decide_member(uuid,text),
  public.company_eligible_for_checkout(),
  public.company_check_restaurant(uuid,uuid),
  public.company_reserve_sponsorship(uuid,uuid,int),
  public.company_confirm_sponsorship(uuid,uuid),
  public.company_release_sponsorship(uuid),
  public.company_daily_estimate(uuid,date),
  public.company_finalize_day(uuid,date),
  public.is_company_admin(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_apply(uuid),
  public.company_decide_member(uuid,text),
  public.company_eligible_for_checkout(),
  public.company_check_restaurant(uuid,uuid),
  public.company_reserve_sponsorship(uuid,uuid,int),
  public.company_release_sponsorship(uuid),
  public.company_daily_estimate(uuid,date),
  public.is_company_admin(uuid) TO authenticated;
-- confirm + finalize are server/service only (called by edge fn / cron).
GRANT EXECUTE ON FUNCTION public.company_confirm_sponsorship(uuid,uuid),
  public.company_finalize_day(uuid,date) TO service_role;

NOTIFY pgrst, 'reload schema';

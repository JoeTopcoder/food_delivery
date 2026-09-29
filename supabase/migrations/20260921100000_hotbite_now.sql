-- HotBite Now — premium "fast-prep" home section.
-- Restaurants self-opt-in with a committed prep time; customers see an
-- eligibility-filtered carousel; orders carry an immutable is_hotbite_now flag.
-- Reuses: restaurants owner RLS (owner_id = auth.uid()), order_status_events
-- for real prep-performance, existing order/cart/checkout flow (flag only).

-- 1. Restaurant opt-in columns -------------------------------------------------
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS hotbite_now_enabled boolean NOT NULL DEFAULT false;

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS hotbite_now_prep_minutes integer NOT NULL DEFAULT 15;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'restaurants_hotbite_prep_range'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT restaurants_hotbite_prep_range
      CHECK (hotbite_now_prep_minutes BETWEEN 5 AND 60);
  END IF;
END$$;

-- 2. Immutable per-order flag --------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_hotbite_now boolean NOT NULL DEFAULT false;

-- Set the flag at insert from the restaurant's current opt-in (grocery never
-- qualifies). Snapshot is immutable — flipping the restaurant toggle later must
-- not rewrite historical orders.
CREATE OR REPLACE FUNCTION public.set_order_hotbite_now_flag()
RETURNS trigger
LANGUAGE plpgsql
AS $fn$
DECLARE
  v_enabled boolean;
  v_store   text;
BEGIN
  IF NEW.is_hotbite_now IS DISTINCT FROM true THEN
    SELECT r.hotbite_now_enabled, r.store_type
      INTO v_enabled, v_store
    FROM public.restaurants r WHERE r.id = NEW.restaurant_id;

    NEW.is_hotbite_now :=
      COALESCE(v_enabled, false) AND COALESCE(v_store, 'food') <> 'grocery';
  END IF;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_set_order_hotbite_now_flag ON public.orders;
CREATE TRIGGER trg_set_order_hotbite_now_flag
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.set_order_hotbite_now_flag();

-- 3. Prep-performance helper — avg confirmed→ready minutes, last 30 days -------
CREATE OR REPLACE FUNCTION public.hotbite_now_avg_prep_minutes(p_restaurant_id uuid)
RETURNS numeric
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  WITH pairs AS (
    SELECT
      o.id,
      min(e.occurred_at) FILTER (WHERE e.status IN ('confirmed','preparing','accepted')) AS started,
      min(e.occurred_at) FILTER (WHERE e.status IN ('ready','ready_for_pickup')) AS ready
    FROM public.orders o
    JOIN public.order_status_events e ON e.order_id = o.id
    WHERE o.restaurant_id = p_restaurant_id
      AND o.created_at > now() - interval '30 days'
    GROUP BY o.id
  )
  SELECT round(avg(EXTRACT(EPOCH FROM (ready - started)) / 60.0)::numeric, 1)
  FROM pairs
  WHERE started IS NOT NULL AND ready IS NOT NULL AND ready > started;
$fn$;

-- 4. Customer-facing eligibility feed -----------------------------------------
-- Eligible = opted in, open, verified, non-grocery, has ≥1 available menu item,
-- and (when coordinates supplied) within p_radius_km. Ordered by committed prep.
CREATE OR REPLACE FUNCTION public.get_hotbite_now_restaurants(
  p_lat        double precision DEFAULT NULL,
  p_lng        double precision DEFAULT NULL,
  p_radius_km  double precision DEFAULT 10.0,
  p_limit      integer          DEFAULT 20
)
RETURNS TABLE (
  id                       uuid,
  name                     text,
  image_url                text,
  cuisine_type             text,
  rating                   numeric,
  review_count             integer,
  estimated_delivery_time  integer,
  hotbite_now_prep_minutes integer,
  avg_prep_minutes         numeric,
  distance_km              double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
  SELECT
    r.id,
    r.name,
    r.image_url,
    r.cuisine_type,
    r.rating,
    r.review_count,
    r.estimated_delivery_time,
    r.hotbite_now_prep_minutes,
    public.hotbite_now_avg_prep_minutes(r.id) AS avg_prep_minutes,
    CASE
      WHEN p_lat IS NULL OR p_lng IS NULL
           OR r.latitude IS NULL OR r.longitude IS NULL THEN NULL
      ELSE 6371.0 * 2 * asin(sqrt(
        power(sin(radians(r.latitude - p_lat) / 2), 2) +
        cos(radians(p_lat)) * cos(radians(r.latitude)) *
        power(sin(radians(r.longitude - p_lng) / 2), 2)
      ))
    END AS distance_km
  FROM public.restaurants r
  WHERE r.hotbite_now_enabled = true
    AND COALESCE(r.is_open, true) = true
    AND COALESCE(r.is_verified, false) = true
    AND COALESCE(r.store_type, 'food') <> 'grocery'
    AND EXISTS (
      SELECT 1 FROM public.menus m
      WHERE m.restaurant_id = r.id
        AND COALESCE(m.is_available, true) = true
    )
    AND (
      p_lat IS NULL OR p_lng IS NULL OR r.latitude IS NULL OR r.longitude IS NULL
      OR 6371.0 * 2 * asin(sqrt(
        power(sin(radians(r.latitude - p_lat) / 2), 2) +
        cos(radians(p_lat)) * cos(radians(r.latitude)) *
        power(sin(radians(r.longitude - p_lng) / 2), 2)
      )) <= p_radius_km
    )
  ORDER BY r.hotbite_now_prep_minutes ASC, r.rating DESC NULLS LAST
  LIMIT GREATEST(p_limit, 1);
$fn$;

GRANT EXECUTE ON FUNCTION public.get_hotbite_now_restaurants(
  double precision, double precision, double precision, integer) TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.hotbite_now_avg_prep_minutes(uuid) TO authenticated;

-- 5. Admin management RPC — set opt-in + prep on any restaurant ----------------
CREATE OR REPLACE FUNCTION public.admin_set_hotbite_now(
  p_restaurant_id uuid,
  p_enabled       boolean,
  p_prep_minutes  integer DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $fn$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'not authorized';
  END IF;
  IF p_prep_minutes IS NOT NULL AND p_prep_minutes NOT BETWEEN 5 AND 60 THEN
    RAISE EXCEPTION 'prep minutes must be between 5 and 60';
  END IF;

  UPDATE public.restaurants
     SET hotbite_now_enabled = p_enabled,
         hotbite_now_prep_minutes =
           COALESCE(p_prep_minutes, hotbite_now_prep_minutes)
   WHERE id = p_restaurant_id;
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.admin_set_hotbite_now(uuid, boolean, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

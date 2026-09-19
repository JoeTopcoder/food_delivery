-- Real demand heatmap. Computes each active zone's live metrics from actual
-- data rather than the static seeded columns on `zones`:
--   * active_orders     = unassigned active orders whose restaurant sits in the
--                         zone radius
--   * available_drivers = online drivers with a fresh (<15 min) location in the
--                         zone radius
--   * demand_level / surge_multiplier = derived from orders-per-available-driver
-- Distances use the haversine formula inline (no PostGIS dependency).
CREATE OR REPLACE FUNCTION public.get_demand_zones()
RETURNS TABLE (
  id                text,
  name              text,
  latitude          double precision,
  longitude         double precision,
  radius_km         double precision,
  active_orders     integer,
  available_drivers integer,
  demand_level      text,
  surge_multiplier  double precision
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  WITH zone_orders AS (
    SELECT z.id AS zid, count(*)::int AS n
    FROM zones z
    JOIN orders o
      ON o.driver_id IS NULL
     AND o.is_pickup = false
     AND o.status IN ('pending','confirmed','preparing','ready')
    JOIN restaurants r ON r.id = o.restaurant_id
    WHERE z.is_active
      AND r.latitude IS NOT NULL AND r.longitude IS NOT NULL
      AND (6371 * acos(least(1, greatest(-1,
            cos(radians(z.latitude)) * cos(radians(r.latitude)) *
            cos(radians(r.longitude - z.longitude)) +
            sin(radians(z.latitude)) * sin(radians(r.latitude))
          )))) <= z.radius_km
    GROUP BY z.id
  ),
  zone_drivers AS (
    SELECT z.id AS zid, count(DISTINCT d.id)::int AS n
    FROM zones z
    JOIN drivers d ON d.is_available = true
    JOIN driver_locations dl
      ON dl.driver_id = d.id
     AND dl.updated_at > now() - interval '15 minutes'
    WHERE z.is_active
      AND (6371 * acos(least(1, greatest(-1,
            cos(radians(z.latitude)) * cos(radians(dl.latitude)) *
            cos(radians(dl.longitude - z.longitude)) +
            sin(radians(z.latitude)) * sin(radians(dl.latitude))
          )))) <= z.radius_km
    GROUP BY z.id
  ),
  computed AS (
    SELECT
      z.id, z.name, z.latitude, z.longitude, z.radius_km,
      coalesce(zo.n, 0) AS orders,
      coalesce(zd.n, 0) AS drivers,
      coalesce(zo.n, 0)::numeric / greatest(coalesce(zd.n, 0), 1) AS per_driver
    FROM zones z
    LEFT JOIN zone_orders  zo ON zo.zid = z.id
    LEFT JOIN zone_drivers zd ON zd.zid = z.id
    WHERE z.is_active
  )
  SELECT
    id::text, name, latitude, longitude, radius_km,
    orders AS active_orders,
    drivers AS available_drivers,
    CASE
      WHEN orders = 0            THEN 'low'
      WHEN per_driver >= 3       THEN 'very_high'
      WHEN per_driver >= 1.5     THEN 'high'
      WHEN per_driver >= 0.75    THEN 'moderate'
      ELSE 'normal'
    END AS demand_level,
    CASE
      WHEN orders = 0        THEN 1.0
      WHEN per_driver >= 3   THEN 2.0
      WHEN per_driver >= 1.5 THEN 1.5
      ELSE 1.0
    END AS surge_multiplier
  FROM computed
  ORDER BY active_orders DESC, name;
$$;

GRANT EXECUTE ON FUNCTION public.get_demand_zones() TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

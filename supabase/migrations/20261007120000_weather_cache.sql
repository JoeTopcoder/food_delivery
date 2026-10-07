-- Shared weather cache for the customer home-screen weather card.
--
-- Rows are keyed by a coarse geographic cell (~1 km, lat/lon rounded to 2 dp)
-- plus the forecast settings (units + days), so customers in nearby areas
-- share a single upstream WeatherAPI.com call. Only the get-weather Edge
-- Function (service role) reads or writes this table; clients never touch it
-- directly. We deliberately store NO customer ids and NO complete addresses —
-- only the rounded representative cell coordinates and the normalized payload.

CREATE TABLE IF NOT EXISTS public.weather_cache (
  cell_key              text PRIMARY KEY,           -- e.g. "17.98,-76.80|c|d1"
  lat                   numeric(6,2) NOT NULL,      -- representative cell coord
  lon                   numeric(6,2) NOT NULL,      -- representative cell coord
  payload               jsonb        NOT NULL,      -- small normalized response
  provider_observed_at  timestamptz,                -- provider's last_updated
  fetched_at            timestamptz  NOT NULL DEFAULT now(),  -- backend retrieval
  expires_at            timestamptz  NOT NULL        -- fetched_at + ~10 min
);

CREATE INDEX IF NOT EXISTS weather_cache_expires_idx
  ON public.weather_cache (expires_at);

-- RLS on with NO policies: the anon/authenticated roles get zero access, so no
-- client can read or (more importantly) forge/poison cache rows. The Edge
-- Function uses the service-role key, which bypasses RLS.
ALTER TABLE public.weather_cache ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.weather_cache FROM anon, authenticated;

-- Bounded storage: a helper the function (or a cron) can call to purge rows
-- that are well past expiry. Kept SECURITY DEFINER + service-role only.
CREATE OR REPLACE FUNCTION public.prune_weather_cache()
RETURNS integer
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  WITH del AS (
    DELETE FROM public.weather_cache
    WHERE expires_at < now() - interval '1 hour'
    RETURNING 1
  )
  SELECT count(*)::int FROM del;
$$;

REVOKE ALL ON FUNCTION public.prune_weather_cache() FROM PUBLIC, anon, authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Fix linter 0010 (security_definer_view) on public.driver_leaderboard without
-- breaking the feature.
--
-- The view shows every VERIFIED driver's public leaderboard stats (name,
-- avatar, deliveries, rating, vehicle, ranks). RLS on drivers/users only lets a
-- user read their OWN row, so a plain security_invoker view would return an
-- empty leaderboard. We also must NOT broadly open drivers/users via RLS —
-- those tables hold sensitive columns (earnings, float, location, email, phone).
--
-- Fix: a SECURITY DEFINER *function* returns only the safe leaderboard columns
-- (controlled, minimal projection), and the view is recreated as
-- security_invoker selecting from it. The linter is satisfied (the view no
-- longer bypasses RLS), the app keeps querying `driver_leaderboard` unchanged,
-- and base-table PII stays protected.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.driver_leaderboard_rows()
  RETURNS TABLE (
    driver_id            uuid,
    user_id              uuid,
    driver_name          text,
    avatar_url           text,
    completed_deliveries integer,
    rating               double precision,
    vehicle_type         text,
    deliveries_rank      bigint,
    rating_rank          bigint
  )
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path = public
AS $function$
  SELECT d.id AS driver_id,
         d.user_id,
         u.name AS driver_name,
         u.profile_image_url AS avatar_url,
         d.completed_deliveries,
         d.rating,
         d.vehicle_type,
         rank() OVER (ORDER BY d.completed_deliveries DESC) AS deliveries_rank,
         rank() OVER (ORDER BY d.rating DESC NULLS LAST) AS rating_rank
  FROM drivers d
  JOIN users u ON u.id = d.user_id
  WHERE d.is_verified = true
  ORDER BY d.completed_deliveries DESC;
$function$;

REVOKE ALL ON FUNCTION public.driver_leaderboard_rows() FROM public;
GRANT EXECUTE ON FUNCTION public.driver_leaderboard_rows() TO authenticated;

-- Recreate the view as security_invoker over the definer function.
DROP VIEW IF EXISTS public.driver_leaderboard;
CREATE VIEW public.driver_leaderboard
  WITH (security_invoker = on) AS
  SELECT * FROM public.driver_leaderboard_rows();

GRANT SELECT ON public.driver_leaderboard TO authenticated;

NOTIFY pgrst, 'reload schema';

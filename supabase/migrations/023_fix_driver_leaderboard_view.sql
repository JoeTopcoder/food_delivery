-- Fix leaderboard view to include all drivers with at least 1 delivery
-- (previously only showed is_verified = true drivers)
CREATE OR REPLACE VIEW public.driver_leaderboard AS
SELECT
  d.id AS driver_id,
  d.user_id,
  u.name AS driver_name,
  u.profile_image_url AS avatar_url,
  d.completed_deliveries,
  d.rating,
  d.vehicle_type,
  d.total_earnings,
  RANK() OVER (ORDER BY d.completed_deliveries DESC) AS deliveries_rank,
  RANK() OVER (ORDER BY d.rating DESC NULLS LAST) AS rating_rank
FROM public.drivers d
JOIN public.users u ON u.id = d.user_id
WHERE d.completed_deliveries > 0
ORDER BY d.completed_deliveries DESC;

GRANT SELECT ON public.driver_leaderboard TO authenticated;

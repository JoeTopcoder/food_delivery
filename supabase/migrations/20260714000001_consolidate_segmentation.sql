-- ─────────────────────────────────────────────────────────────────────────────
-- Consolidate the two independent customer-segmentation systems into one
-- source of truth.
--
-- Before this migration, two systems classified the same customer from the
-- same underlying order history, disagreeing in principle:
--   - "Brain Engine": compute_user_profile() (049/052) — per-user,
--     client-triggered on app open, writes user_intelligence_profiles
--     .user_segment ('new_user'/'inactive'/'power_user'/'regular'/'casual')
--     + .churn_risk. Drives customer-facing personalization (home screen
--     recommendations, ad ranking, SmartOfferBanner).
--   - "Decision Engine": update_user_segments() (20260424000020) — nightly
--     cron, independently re-aggregates orders into user_metrics, classifies
--     with different thresholds into segment ('new'/'active'/'at_risk'
--     /'loyal'). Drives the admin panel only.
--
-- A customer could be "power_user" in one and "at_risk" in the other at the
-- same time. Fix: Brain Engine becomes canonical. Decision Engine's segment
-- becomes a derived projection of it, not an independent computation.
-- user_metrics's OTHER columns (avg_order_value, days_since_last_order,
-- order_frequency) are untouched — still independently computed/accurate,
-- only the segment LABEL changes to be derived.
--
-- Not fixed here (separate, bigger follow-up, noted so it isn't forgotten):
-- generate_targeted_coupon() (Brain Engine) and generate_promotions()
-- (Decision Engine) are still two uncoordinated discount-issuing mechanisms
-- that could both fire for the same at-risk customer.
-- ─────────────────────────────────────────────────────────────────────────────

-- Brain Engine today only computes for users who've actually opened the app
-- recently (client-triggered). The admin-facing segment distribution needs
-- everyone covered, including dormant users who never trigger it. Reuses
-- compute_user_profile() verbatim per user — no scoring logic duplicated.
CREATE OR REPLACE FUNCTION public.compute_all_user_profiles()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _user_id uuid;
BEGIN
  FOR _user_id IN SELECT id FROM public.users WHERE is_active = true LOOP
    PERFORM public.compute_user_profile(_user_id);
  END LOOP;
END;
$$;

-- Was: independently classified segment from user_metrics's own columns.
-- Now: derives it from user_intelligence_profiles.user_segment via a fixed
-- mapping, so both systems always agree for a given user.
CREATE OR REPLACE FUNCTION public.update_user_segments()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.user_metrics um
  SET segment = CASE uip.user_segment
      WHEN 'new_user'   THEN 'new'
      WHEN 'inactive'   THEN 'at_risk'
      WHEN 'power_user' THEN 'loyal'
      WHEN 'regular'    THEN 'active'
      WHEN 'casual'     THEN 'active'
      ELSE 'new'
    END,
    updated_at = now()
  FROM public.user_intelligence_profiles uip
  WHERE um.user_id = uip.user_id;
END;
$$;

-- Ensure Brain Engine data is fresh for everyone before Decision Engine
-- derives segments from it.
CREATE OR REPLACE FUNCTION public.run_decision_engine()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  PERFORM public.refresh_user_metrics();
  PERFORM public.compute_all_user_profiles();
  PERFORM public.update_user_segments();
  PERFORM public.generate_promotions();
END;
$$;

GRANT EXECUTE ON FUNCTION public.compute_all_user_profiles() TO service_role;

-- The existing decision_engine_daily cron (01:00 UTC) already calls
-- run_decision_engine() — no new schedule needed, just a heavier body
-- running at the same time slot.

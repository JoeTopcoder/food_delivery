-- ============================================================================
-- HotBite Member Referral Rewards — 6 : daily maintenance cron
-- ----------------------------------------------------------------------------
-- Once a day: (1) expire pending rewards past their carry-forward life, and
-- (2) retry unlock for earners who now have an active membership + a settled,
-- non-expired pending reward. This covers the "unlock when membership renews"
-- case, where no new order would otherwise trigger unlock.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.referral_daily_maintenance()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_exp jsonb; r record; v_unlocked int := 0;
BEGIN
  v_exp := public.referral_expire_pending();

  FOR r IN
    SELECT DISTINCT rr.earner_id
    FROM referral_rewards rr
    WHERE rr.status = 'pending'
      AND rr.settle_at <= now()
      AND rr.expires_at > now()
      AND rr.reward_cents > 0
      AND public.is_hotbite_plus_member(rr.earner_id)
  LOOP
    PERFORM public.referral_unlock_rewards(r.earner_id);
    v_unlocked := v_unlocked + 1;
  END LOOP;

  RETURN jsonb_build_object('expired', v_exp, 'unlock_attempts', v_unlocked);
END;
$$;

REVOKE ALL ON FUNCTION public.referral_daily_maintenance() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.referral_daily_maintenance() TO service_role;

-- Schedule daily at 06:10 UTC (~01:10 Jamaica). Guard if pg_cron is present.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('referral_daily_maintenance')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'referral_daily_maintenance');
    PERFORM cron.schedule('referral_daily_maintenance', '10 6 * * *',
      $cron$ SELECT public.referral_daily_maintenance(); $cron$);
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

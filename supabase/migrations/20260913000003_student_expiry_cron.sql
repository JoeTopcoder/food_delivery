-- Daily sweep: expire student verifications past their ID expiry (Phase 8/10).
-- Runs 00:10; suspends only student benefits (accounts stay active). Skipped
-- gracefully if pg_cron isn't enabled — call expire_student_verifications()
-- from any scheduler otherwise.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    PERFORM cron.unschedule('expire_student_verifications')
      WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'expire_student_verifications');
    PERFORM cron.schedule(
      'expire_student_verifications',
      '10 0 * * *',
      'SELECT public.expire_student_verifications()'
    );
  END IF;
END;
$$;

NOTIFY pgrst, 'reload schema';

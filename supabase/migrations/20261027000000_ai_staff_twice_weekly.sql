-- Run the AI staff only two days a week: Mondays and Fridays (cron DOW 1,5).
-- These are the staff reporting/assessment jobs. Operational automations
-- (pickup dialing, store reminders, call fallback, hold release, etc.) are
-- intentionally left on their original cadence.
--
-- cron.schedule(name,...) upserts by job name, preserving the job but changing
-- its schedule.

-- AI staff daily reports & admin briefing (was hourly, self-gating).
SELECT cron.schedule('ai-staff-daily', '0 * * * 1,5', 'SELECT public.run_ai_staff_daily();');

-- 3 cybersecurity AI staff daily assessment (was 06:00 daily).
SELECT cron.schedule('daily_security_assessment', '0 6 * * 1,5', $$SELECT public.run_security_assessment('cron');$$);

-- Referral Economics Guardian AI staff (was 07:00 daily).
SELECT cron.schedule('referral-guardian-daily', '0 7 * * 1,5', 'SELECT public.referral_guardian_daily();');

-- ─────────────────────────────────────────────────────────────────────────────
-- Limit birthday edits to 2 per rolling year — server-side enforcement so it
-- can't be bypassed by calling the API directly. Abuse-prevention measure:
-- without this, a customer could keep changing their birthday to farm a new
-- $X-off code every day.
--
-- Rules:
-- - Setting the birthday for the FIRST time (NULL -> a value) is always
--   allowed and does not count against the limit — only actual edits to an
--   already-set birthday do.
-- - The limit is a rolling 365-day window, not a calendar year, so it can't
--   be gamed around the Dec 31 / Jan 1 boundary.
-- - birthday_change_log is a lightweight audit trail (who changed what,
--   when) — self-readable so the app could show "N changes left" if wanted,
--   admin-readable for support/abuse investigation. Only the trigger writes
--   to it (SECURITY DEFINER); no client insert/update/delete policy exists.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.birthday_change_log (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  old_birthday  date,
  new_birthday  date NOT NULL,
  changed_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_birthday_change_log_user_time
  ON public.birthday_change_log(user_id, changed_at);

ALTER TABLE public.birthday_change_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "birthday_change_log_self_read" ON public.birthday_change_log;
CREATE POLICY "birthday_change_log_self_read"
  ON public.birthday_change_log FOR SELECT
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "birthday_change_log_admin_all" ON public.birthday_change_log;
CREATE POLICY "birthday_change_log_admin_all"
  ON public.birthday_change_log FOR ALL
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE users.id = auth.uid() AND users.role = 'admin')
  );

CREATE OR REPLACE FUNCTION public.enforce_birthday_change_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _recent_changes int;
BEGIN
  -- First-time set (NULL -> value) is always allowed, doesn't count.
  IF OLD.birthday IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT count(*) INTO _recent_changes
  FROM public.birthday_change_log
  WHERE user_id = NEW.id
    AND changed_at >= now() - interval '365 days';

  IF _recent_changes >= 2 THEN
    RAISE EXCEPTION 'Birthday can only be changed twice per year. Please contact support if you need to update it again.'
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO public.birthday_change_log (user_id, old_birthday, new_birthday)
  VALUES (NEW.id, OLD.birthday, NEW.birthday);

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_birthday_change_limit ON public.users;
CREATE TRIGGER trg_enforce_birthday_change_limit
  BEFORE UPDATE ON public.users
  FOR EACH ROW
  WHEN (OLD.birthday IS DISTINCT FROM NEW.birthday)
  EXECUTE FUNCTION public.enforce_birthday_change_limit();

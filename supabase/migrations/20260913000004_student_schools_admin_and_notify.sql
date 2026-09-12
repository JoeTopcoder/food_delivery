-- Phase 16/23 + Phase 20: admin management of participating schools, and
-- student notifications driven off the audit log (uses the existing
-- notifications table + its push trigger).

-- ── Admin can read ALL schools (incl. inactive) and manage them ──────────────
-- The public policy only exposes is_active schools for selection; admins need
-- the full list plus insert/update to run the participating-school list.
DROP POLICY IF EXISTS schools_admin_all ON public.schools;
CREATE POLICY schools_admin_all ON public.schools
  FOR ALL TO authenticated
  USING (public.current_user_is_admin())
  WITH CHECK (public.current_user_is_admin());

-- ── Notify the student when key verification events happen ───────────────────
-- Fires off the append-only audit log so every path (RPC or cron) notifies
-- consistently. Runs in the audit-writer's (SECURITY DEFINER) context, so it
-- may insert into notifications regardless of that table's RLS.
CREATE OR REPLACE FUNCTION public._notify_on_student_audit()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE v_title TEXT; v_body TEXT;
BEGIN
  IF NEW.student_id IS NULL THEN RETURN NEW; END IF;

  IF NEW.action = 'driver reported school delivery problem' THEN
    v_title := 'Student benefits suspended';
    v_body  := 'Your student benefits have been temporarily suspended because a '
            || 'delivery was not confirmed at the registered school. The company '
            || 'will review this.';
  ELSIF NEW.action = 'ID expired' THEN
    v_title := 'Student ID expired';
    v_body  := 'Your student ID has expired. Upload your updated student ID to '
            || 'restore student benefits.';
  ELSIF NEW.action = 'benefits restored' THEN
    v_title := 'Student benefits restored';
    v_body  := 'Your student benefits have been restored.';
  ELSIF NEW.action = 'OCR validated' AND NEW.new_status = 'approved' THEN
    v_title := 'Student ID verified';
    v_body  := 'Your student ID has been verified and your student benefits are active.';
  ELSIF NEW.action = 'OCR validated' AND NEW.new_status = 'needs_update' THEN
    v_title := 'Student ID needs updating';
    v_body  := coalesce(NEW.reason, 'Please re-upload your student ID.');
  ELSE
    RETURN NEW;  -- not a user-facing event
  END IF;

  INSERT INTO public.notifications (user_id, type, title, body, data)
  VALUES (NEW.student_id, 'student_verification', v_title, v_body,
          jsonb_build_object('action', NEW.action, 'new_status', NEW.new_status));
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_notify_student_audit ON public.student_verification_audit;
CREATE TRIGGER trg_notify_student_audit
  AFTER INSERT ON public.student_verification_audit
  FOR EACH ROW EXECUTE FUNCTION public._notify_on_student_audit();

NOTIFY pgrst, 'reload schema';

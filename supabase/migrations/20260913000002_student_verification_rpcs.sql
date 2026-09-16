-- ════════════════════════════════════════════════════════════════════════════
-- Student ID verification — SECURITY DEFINER RPCs (Phase 5/6/9/10/11/13).
--
-- All privileged transitions live here so clients never write verification_status
-- or benefits_active directly. OCR runs on-device (chosen model); the client
-- submits the extracted fields and this layer does the VALIDATION + approval
-- decision server-side and stores the image for admin spot-check.
-- ════════════════════════════════════════════════════════════════════════════

-- ── Text-normalisation helpers ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._norm_text(t TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT upper(btrim(regexp_replace(coalesce(t,''), '\s+', ' ', 'g')));
$$;

-- IDs: strip everything but letters/digits, uppercase.
CREATE OR REPLACE FUNCTION public._norm_id(t TEXT)
RETURNS TEXT LANGUAGE sql IMMUTABLE AS $$
  SELECT upper(regexp_replace(coalesce(t,''), '[^A-Za-z0-9]', '', 'g'));
$$;

-- Caller may manage a student iff they ARE the student or an active linked parent.
CREATE OR REPLACE FUNCTION public._can_manage_student(p_student UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_student = auth.uid()
    OR EXISTS (SELECT 1 FROM public.parent_student_links l
               WHERE l.student_id = p_student AND l.parent_id = auth.uid()
                 AND l.status = 'active');
$$;

-- ── 1. Submit a verification attempt (creates a 'processing' row) ────────────
CREATE OR REPLACE FUNCTION public.submit_student_verification(
  p_student_id        UUID,
  p_student_name      TEXT,
  p_student_id_number TEXT,
  p_school_id         UUID,
  p_id_image_url      TEXT,
  p_selfie_url        TEXT DEFAULT NULL
)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_id UUID;
BEGIN
  IF NOT public._can_manage_student(p_student_id) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;
  IF coalesce(btrim(p_id_image_url),'') = '' THEN
    RAISE EXCEPTION 'A student ID image is required';
  END IF;

  INSERT INTO public.student_verifications
    (user_id, student_name, student_id_number, school_id,
     student_id_image_url, submitted_selfie_url, verification_status, benefits_active)
  VALUES
    (p_student_id, btrim(p_student_name), btrim(p_student_id_number), p_school_id,
     p_id_image_url, p_selfie_url, 'processing', FALSE)
  RETURNING id INTO v_id;

  INSERT INTO public.student_verification_audit
    (student_id, actor_id, actor_type, action, new_status, metadata)
  VALUES (p_student_id, auth.uid(),
          CASE WHEN p_student_id = auth.uid() THEN 'student' ELSE 'parent' END,
          'ID uploaded', 'processing', jsonb_build_object('verification_id', v_id));

  RETURN v_id;
END;
$$;

-- ── 2. Validate on-device OCR output and decide the outcome ──────────────────
CREATE OR REPLACE FUNCTION public.finalize_student_verification(
  p_verification_id  UUID,
  p_extracted_name   TEXT,
  p_extracted_student_id TEXT,
  p_extracted_school TEXT,
  p_issue_date       DATE,
  p_expiration_date  DATE,
  p_document_number  TEXT,
  p_ocr_confidence   NUMERIC
)
RETURNS public.student_verifications
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v      public.student_verifications;
  v_threshold  NUMERIC;
  v_school_active BOOLEAN;
  v_school_name  TEXT;
  v_name_ok   BOOLEAN;
  v_id_ok     BOOLEAN;
  v_school_ok BOOLEAN;
  v_exp_ok    BOOLEAN;
  v_conf_ok   BOOLEAN;
  v_status    TEXT;
  v_reason    TEXT;
  v_benefits  BOOLEAN := FALSE;
BEGIN
  SELECT * INTO v FROM public.student_verifications WHERE id = p_verification_id;
  IF v.id IS NULL THEN RAISE EXCEPTION 'Verification not found'; END IF;
  IF NOT public._can_manage_student(v.user_id) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;
  IF v.verification_status NOT IN ('processing','pending','needs_update','manual_review') THEN
    RAISE EXCEPTION 'This verification is already %', v.verification_status;
  END IF;

  SELECT coalesce(value::numeric, 60) INTO v_threshold
    FROM public.app_config WHERE key = 'student_ocr_confidence_threshold';
  v_threshold := coalesce(v_threshold, 60);

  SELECT is_active, name INTO v_school_active, v_school_name
    FROM public.schools WHERE id = v.school_id;

  -- Match checks (normalised; formatting differences tolerated for names).
  v_name_ok := public._norm_text(v.student_name) <> ''
    AND (public._norm_text(v.student_name) = public._norm_text(p_extracted_name)
         OR public._norm_text(p_extracted_name) LIKE '%'||public._norm_text(v.student_name)||'%'
         OR public._norm_text(v.student_name) LIKE '%'||public._norm_text(p_extracted_name)||'%');
  v_id_ok := public._norm_id(v.student_id_number) <> ''
    AND public._norm_id(v.student_id_number) = public._norm_id(p_extracted_student_id);
  -- School name is advisory: matched when readable, not disqualifying when blank.
  v_school_ok := coalesce(btrim(p_extracted_school),'') = ''
    OR public._norm_text(p_extracted_school) LIKE '%'||public._norm_text(v_school_name)||'%'
    OR public._norm_text(v_school_name) LIKE '%'||public._norm_text(p_extracted_school)||'%';
  v_exp_ok := p_expiration_date IS NOT NULL AND p_expiration_date >= current_date;
  v_conf_ok := coalesce(p_ocr_confidence, 0) >= v_threshold;

  -- Decide. School must be a participating (active) school to be eligible.
  IF coalesce(v_school_active, FALSE) = FALSE THEN
    v_status := 'rejected'; v_reason := 'Selected school is not a participating school.';
  ELSIF NOT v_conf_ok THEN
    v_status := 'needs_update'; v_reason := 'The ID image was too unclear to read. Please upload a clearer photo.';
  ELSIF p_expiration_date IS NULL THEN
    v_status := 'needs_update'; v_reason := 'Could not read an expiration date on the ID.';
  ELSIF NOT v_exp_ok THEN
    v_status := 'needs_update'; v_reason := 'This student ID has expired. Please upload a current ID.';
  ELSIF NOT v_id_ok OR NOT v_name_ok THEN
    v_status := 'manual_review';
    v_reason := 'The ID details did not clearly match what was entered.';
  ELSE
    v_status := 'approved'; v_benefits := TRUE;
  END IF;

  UPDATE public.student_verifications SET
    extracted_name = btrim(p_extracted_name),
    extracted_student_id = btrim(p_extracted_student_id),
    extracted_school = btrim(p_extracted_school),
    extracted_issue_date = p_issue_date,
    extracted_expiration_date = p_expiration_date,
    extracted_document_number = btrim(p_document_number),
    ocr_confidence = p_ocr_confidence,
    name_match = v_name_ok, student_id_match = v_id_ok,
    school_match = v_school_ok, expiration_valid = v_exp_ok,
    verification_status = v_status,
    benefits_active = v_benefits,
    rejection_reason = CASE WHEN v_status IN ('rejected','needs_update') THEN v_reason END,
    review_reason    = CASE WHEN v_status = 'manual_review' THEN v_reason END,
    verified_at = CASE WHEN v_status = 'approved' THEN now() END,
    expires_at  = CASE WHEN v_status = 'approved' THEN p_expiration_date::timestamptz END,
    updated_at = now()
  WHERE id = p_verification_id
  RETURNING * INTO v;

  -- Only the latest approved verification stays active for a student.
  IF v_status = 'approved' THEN
    UPDATE public.student_verifications
       SET benefits_active = FALSE, updated_at = now()
     WHERE user_id = v.user_id AND id <> v.id AND benefits_active = TRUE;
  END IF;

  INSERT INTO public.student_verification_audit
    (student_id, actor_id, actor_type, action, old_status, new_status, reason, metadata)
  VALUES (v.user_id, auth.uid(),
          CASE WHEN v.user_id = auth.uid() THEN 'student' ELSE 'parent' END,
          'OCR validated', 'processing', v_status, v_reason,
          jsonb_build_object('verification_id', v.id, 'ocr_confidence', p_ocr_confidence,
            'name_match', v_name_ok, 'student_id_match', v_id_ok,
            'school_match', v_school_ok, 'expiration_valid', v_exp_ok));

  RETURN v;
END;
$$;

-- ── 3. Daily expiry sweep (cron / service role) ──────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_student_verifications()
RETURNS INTEGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r RECORD; n INTEGER := 0;
BEGIN
  IF auth.uid() IS NOT NULL AND NOT public.current_user_is_admin() THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;
  FOR r IN
    SELECT id, user_id FROM public.student_verifications
     WHERE verification_status = 'approved' AND benefits_active = TRUE
       AND expires_at IS NOT NULL AND expires_at < now()
  LOOP
    UPDATE public.student_verifications
       SET verification_status = 'expired', benefits_active = FALSE, updated_at = now()
     WHERE id = r.id;
    INSERT INTO public.student_verification_audit
      (student_id, actor_type, action, old_status, new_status, reason, metadata)
    VALUES (r.user_id, 'system', 'ID expired', 'approved', 'expired',
            'Student ID expired.', jsonb_build_object('verification_id', r.id));
    n := n + 1;
  END LOOP;
  RETURN n;
END;
$$;

-- ── 4. Driver school-delivery confirmation (Phase 10) ────────────────────────
CREATE OR REPLACE FUNCTION public.confirm_student_delivery(
  p_order_id  UUID,
  p_confirmed BOOLEAN,
  p_reason    TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_driver UUID; v_student UUID; v_school UUID; v_rtype TEXT; v_ver UUID;
BEGIN
  SELECT driver_id, student_id, school_id, recipient_type
    INTO v_driver, v_student, v_school, v_rtype
    FROM public.orders WHERE id = p_order_id;
  IF v_driver IS NULL AND v_rtype IS NULL THEN RAISE EXCEPTION 'Order not found'; END IF;
  -- Only the order's assigned driver (or an admin) may confirm.
  IF NOT (v_driver = auth.uid() OR public.current_user_is_admin()) THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;
  IF v_rtype IS DISTINCT FROM 'student' THEN
    RAISE EXCEPTION 'This order is not a student delivery';
  END IF;

  -- One confirmation per order.
  INSERT INTO public.student_delivery_confirmations
    (order_id, student_id, school_id, driver_id, delivery_confirmed, reason)
  VALUES (p_order_id, v_student, v_school, coalesce(v_driver, auth.uid()), p_confirmed, p_reason)
  ON CONFLICT (order_id) DO NOTHING;

  IF p_confirmed THEN
    INSERT INTO public.student_verification_audit
      (student_id, actor_id, actor_type, action, reason, metadata)
    VALUES (v_student, auth.uid(), 'driver', 'driver confirmed school delivery',
            p_reason, jsonb_build_object('order_id', p_order_id, 'school_id', v_school));
    RETURN jsonb_build_object('status','confirmed');
  END IF;

  -- NO: suspend the student's current benefits and open a company review.
  UPDATE public.student_verifications
     SET verification_status = 'suspended', benefits_active = FALSE, updated_at = now()
   WHERE user_id = v_student AND benefits_active = TRUE
  RETURNING id INTO v_ver;

  INSERT INTO public.student_delivery_reviews
    (order_id, student_id, school_id, driver_id, reason, status)
  VALUES (p_order_id, v_student, v_school, coalesce(v_driver, auth.uid()),
          coalesce(p_reason, 'Driver reported delivery not completed at the registered school.'),
          'pending');

  INSERT INTO public.student_verification_audit
    (student_id, actor_id, actor_type, action, new_status, reason, metadata)
  VALUES (v_student, auth.uid(), 'driver', 'driver reported school delivery problem',
          'suspended', p_reason, jsonb_build_object('order_id', p_order_id, 'verification_id', v_ver));

  RETURN jsonb_build_object('status','suspended');
END;
$$;

-- ── 5. Admin resolves a delivery review (Phase 11/17) ────────────────────────
CREATE OR REPLACE FUNCTION public.admin_resolve_student_review(
  p_review_id UUID,
  p_action    TEXT,   -- restore | keep_suspended | confirm_issue
  p_notes     TEXT DEFAULT NULL
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_student UUID; v_ver public.student_verifications; v_new_status TEXT;
BEGIN
  IF NOT public.current_user_is_admin() THEN
    RAISE EXCEPTION 'Forbidden' USING errcode = 'insufficient_privilege';
  END IF;
  SELECT student_id INTO v_student FROM public.student_delivery_reviews WHERE id = p_review_id;
  IF v_student IS NULL THEN RAISE EXCEPTION 'Review not found'; END IF;

  IF p_action = 'restore' THEN
    -- Latest verification for the student; only restore if it hasn't expired.
    SELECT * INTO v_ver FROM public.student_verifications
     WHERE user_id = v_student ORDER BY created_at DESC LIMIT 1;
    IF v_ver.id IS NULL THEN RAISE EXCEPTION 'No verification on file for this student'; END IF;
    IF v_ver.expires_at IS NOT NULL AND v_ver.expires_at < now() THEN
      RAISE EXCEPTION 'Cannot restore: the student ID has expired. The student must upload a current ID.';
    END IF;
    UPDATE public.student_verifications
       SET verification_status = 'approved', benefits_active = TRUE, updated_at = now()
     WHERE id = v_ver.id;
    v_new_status := 'resolved';
    INSERT INTO public.student_verification_audit
      (student_id, actor_id, actor_type, action, new_status, reason, metadata)
    VALUES (v_student, auth.uid(), 'admin', 'benefits restored', 'approved', p_notes,
            jsonb_build_object('review_id', p_review_id));
  ELSIF p_action = 'keep_suspended' THEN
    v_new_status := 'kept_suspended';
    INSERT INTO public.student_verification_audit
      (student_id, actor_id, actor_type, action, reason, metadata)
    VALUES (v_student, auth.uid(), 'admin', 'admin kept student suspended', p_notes,
            jsonb_build_object('review_id', p_review_id));
  ELSIF p_action = 'confirm_issue' THEN
    v_new_status := 'confirmed_issue';
    INSERT INTO public.student_verification_audit
      (student_id, actor_id, actor_type, action, reason, metadata)
    VALUES (v_student, auth.uid(), 'admin', 'admin confirmed delivery issue', p_notes,
            jsonb_build_object('review_id', p_review_id));
  ELSE
    RAISE EXCEPTION 'Unknown action %', p_action;
  END IF;

  UPDATE public.student_delivery_reviews
     SET status = v_new_status, admin_notes = p_notes,
         resolved_at = now(), resolved_by = auth.uid()
   WHERE id = p_review_id;

  RETURN jsonb_build_object('status', v_new_status);
END;
$$;

-- ── 6. Eligibility helper (Phase 9) ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.student_benefits_active(p_user_id UUID)
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.student_verifications v
    WHERE v.user_id = p_user_id
      AND v.verification_status = 'approved'
      AND v.benefits_active = TRUE
      AND (v.expires_at IS NULL OR v.expires_at > now())
  );
$$;

-- ── Grants ───────────────────────────────────────────────────────────────────
REVOKE EXECUTE ON FUNCTION public.expire_student_verifications() FROM PUBLIC, anon;
DO $g$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
    WHERE n.nspname='public' AND p.proname IN
      ('submit_student_verification','finalize_student_verification',
       'confirm_student_delivery','admin_resolve_student_review',
       'student_benefits_active','expire_student_verifications')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC, anon', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated, service_role', r.sig);
  END LOOP;
END $g$;

NOTIFY pgrst, 'reload schema';

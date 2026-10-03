-- ============================================================================
-- HotBite Member Referral Rewards — 2/5 : attribution history + codes
-- ----------------------------------------------------------------------------
-- Each purchasing account has AT MOST ONE current referring account (who
-- receives its direct/second-tier rewards). Attribution is versioned with
-- effective dates so it can change for FUTURE orders without ever rewriting who
-- was credited on already-completed orders. The table itself is the audit trail
-- (changed_by + reason + effective_from/to per row).
--
-- Multiple accounts per person are allowed: shared ownership is NEVER a reason
-- to reject an attribution. Only same-ACCOUNT self-links and graph CYCLES are
-- blocked, purely for data integrity.
-- ============================================================================

-- 1. Ensure every account can have a referral code. --------------------------
CREATE OR REPLACE FUNCTION public.referral_gen_code()
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE v_code text; v_exists boolean;
BEGIN
  LOOP
    -- HB + 6 base32-ish chars (no ambiguous 0/O/1/I).
    v_code := 'HB' || (
      SELECT string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789',
                               (floor(random()*31)+1)::int, 1), '')
      FROM generate_series(1,6)
    );
    SELECT EXISTS(SELECT 1 FROM users WHERE referral_code = v_code) INTO v_exists;
    EXIT WHEN NOT v_exists;
  END LOOP;
  RETURN v_code;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_referral_code(p_user uuid)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_code text;
BEGIN
  SELECT referral_code INTO v_code FROM users WHERE id = p_user;
  IF v_code IS NULL OR v_code = '' THEN
    v_code := referral_gen_code();
    UPDATE users SET referral_code = v_code WHERE id = p_user;
  END IF;
  RETURN v_code;
END;
$$;

-- Auto-assign a code on new user rows.
CREATE OR REPLACE FUNCTION public.trg_assign_referral_code()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.referral_code IS NULL OR NEW.referral_code = '' THEN
    NEW.referral_code := public.referral_gen_code();
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_users_referral_code ON public.users;
CREATE TRIGGER trg_users_referral_code BEFORE INSERT ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.trg_assign_referral_code();

-- Backfill existing accounts that lack a code.
UPDATE users SET referral_code = public.referral_gen_code()
WHERE referral_code IS NULL OR referral_code = '';

-- 2. Attribution history table. ----------------------------------------------
CREATE TABLE IF NOT EXISTS public.referral_attributions (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  purchaser_id   uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  referrer_id    uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  effective_from timestamptz NOT NULL DEFAULT now(),
  effective_to   timestamptz,                      -- NULL = current
  changed_by     uuid REFERENCES users(id),
  reason         text,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT ra_not_self CHECK (purchaser_id <> referrer_id)
);
-- Exactly one CURRENT referrer per purchaser.
CREATE UNIQUE INDEX IF NOT EXISTS uq_ra_current_purchaser
  ON public.referral_attributions(purchaser_id) WHERE effective_to IS NULL;
CREATE INDEX IF NOT EXISTS idx_ra_referrer ON public.referral_attributions(referrer_id) WHERE effective_to IS NULL;
CREATE INDEX IF NOT EXISTS idx_ra_purchaser_time ON public.referral_attributions(purchaser_id, effective_from DESC);

ALTER TABLE public.referral_attributions ENABLE ROW LEVEL SECURITY;
-- A user may see attributions where they are the purchaser or the referrer.
DROP POLICY IF EXISTS ra_self_select ON public.referral_attributions;
CREATE POLICY ra_self_select ON public.referral_attributions FOR SELECT
  USING (purchaser_id = auth.uid() OR referrer_id = auth.uid()
         OR EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'));
-- Writes go only through SECURITY DEFINER RPCs (no direct client writes).
DROP POLICY IF EXISTS ra_admin_write ON public.referral_attributions;
CREATE POLICY ra_admin_write ON public.referral_attributions FOR ALL
  USING (EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'))
  WITH CHECK (EXISTS (SELECT 1 FROM users u WHERE u.id = auth.uid() AND u.role = 'admin'));

-- 3. Attribution resolution helpers. -----------------------------------------
-- The referrer in force for a purchaser at instant p_ts (NULL if none).
CREATE OR REPLACE FUNCTION public.referral_referrer_at(p_purchaser uuid, p_ts timestamptz)
RETURNS uuid
LANGUAGE sql STABLE
AS $$
  SELECT referrer_id FROM public.referral_attributions
  WHERE purchaser_id = p_purchaser
    AND effective_from <= p_ts
    AND (effective_to IS NULL OR effective_to > p_ts)
  ORDER BY effective_from DESC
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.referral_current_referrer(p_purchaser uuid)
RETURNS uuid
LANGUAGE sql STABLE
AS $$ SELECT public.referral_referrer_at(p_purchaser, now()); $$;

-- Cycle guard: does making p_referrer the referrer of p_purchaser create a loop
-- in the CURRENT attribution graph? Walks up from p_referrer's own referrer.
CREATE OR REPLACE FUNCTION public.referral_would_cycle(p_purchaser uuid, p_referrer uuid)
RETURNS boolean
LANGUAGE plpgsql STABLE
AS $$
DECLARE v_cur uuid := p_referrer; v_hops int := 0;
BEGIN
  IF p_purchaser = p_referrer THEN RETURN true; END IF;
  WHILE v_cur IS NOT NULL AND v_hops < 100 LOOP
    IF v_cur = p_purchaser THEN RETURN true; END IF;
    v_cur := public.referral_current_referrer(v_cur);
    v_hops := v_hops + 1;
  END LOOP;
  RETURN false;
END;
$$;

-- 4. Internal setter (shared by customer + admin RPCs). ----------------------
CREATE OR REPLACE FUNCTION public._referral_apply_attribution(
  p_purchaser uuid, p_referrer uuid, p_changed_by uuid, p_reason text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_cur uuid;
BEGIN
  IF p_purchaser IS NULL OR p_referrer IS NULL THEN
    RAISE EXCEPTION 'purchaser and referrer required';
  END IF;
  IF p_purchaser = p_referrer THEN
    RAISE EXCEPTION 'An account cannot refer itself' USING ERRCODE='check_violation';
  END IF;
  IF public.referral_would_cycle(p_purchaser, p_referrer) THEN
    RAISE EXCEPTION 'That referral link would create a circular chain'
      USING ERRCODE='check_violation';
  END IF;

  v_cur := public.referral_current_referrer(p_purchaser);
  IF v_cur = p_referrer THEN
    RETURN; -- no change
  END IF;

  -- Close the current attribution (if any) and open a new one.
  UPDATE public.referral_attributions
     SET effective_to = now()
   WHERE purchaser_id = p_purchaser AND effective_to IS NULL;

  INSERT INTO public.referral_attributions
    (purchaser_id, referrer_id, changed_by, reason)
  VALUES (p_purchaser, p_referrer, p_changed_by, p_reason);

  -- Keep the convenience pointer in sync.
  UPDATE users SET referred_by = p_referrer WHERE id = p_purchaser;
END;
$$;

-- Customer-facing: set MY referrer by code (for future orders only).
CREATE OR REPLACE FUNCTION public.referral_set_referrer(p_code text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_me uuid := auth.uid(); v_ref uuid;
BEGIN
  IF v_me IS NULL THEN RAISE EXCEPTION 'Not authenticated' USING ERRCODE='28000'; END IF;
  SELECT id INTO v_ref FROM users WHERE upper(referral_code) = upper(trim(p_code));
  IF v_ref IS NULL THEN RAISE EXCEPTION 'Referral code not found'; END IF;
  PERFORM public._referral_apply_attribution(v_me, v_ref, v_me, 'customer_set_by_code');
  RETURN jsonb_build_object('ok', true, 'referrer_id', v_ref);
END;
$$;

-- Admin-facing: set/replace any purchaser's referrer.
CREATE OR REPLACE FUNCTION public.admin_referral_set_referrer(
  p_purchaser uuid, p_referrer uuid, p_reason text DEFAULT 'admin_change')
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_admin uuid;
BEGIN
  v_admin := public.require_admin();
  PERFORM public._referral_apply_attribution(p_purchaser, p_referrer, v_admin, p_reason);
  RETURN jsonb_build_object('ok', true, 'purchaser_id', p_purchaser, 'referrer_id', p_referrer);
END;
$$;

REVOKE ALL ON FUNCTION public._referral_apply_attribution(uuid,uuid,uuid,text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_referral_code(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_referrer_at(uuid,timestamptz) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_current_referrer(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_would_cycle(uuid,uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.referral_set_referrer(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_referral_set_referrer(uuid,uuid,text) TO authenticated;

NOTIFY pgrst, 'reload schema';

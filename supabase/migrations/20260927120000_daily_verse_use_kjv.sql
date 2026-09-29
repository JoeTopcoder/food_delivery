-- ============================================================================
-- Point the daily verse at the full KJV table (public.kjv_bible_verses) instead
-- of the small curated public.bible_verses set. Same deterministic per-user,
-- per-day selection; same (reference, text) output shape the app already reads.
-- kjv_bible_verses has no is_active column, so the active filter is dropped.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.get_daily_verse(p_user_id uuid DEFAULT NULL)
RETURNS TABLE (reference text, text text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_uid   text;
  v_day   text := to_char((now() AT TIME ZONE 'America/Jamaica'), 'YYYY-MM-DD');
  v_count int;
  v_idx   int;
BEGIN
  -- Pin to the JWT caller when present; fall back to the passed id otherwise.
  v_uid := COALESCE(auth.uid()::text, p_user_id::text, 'anon');
  SELECT count(*) INTO v_count FROM kjv_bible_verses;
  IF v_count = 0 THEN RETURN; END IF;
  v_idx := abs(hashtext(v_uid || v_day)) % v_count;

  RETURN QUERY
  SELECT bv.reference, bv.text FROM (
    SELECT b.reference, b.text, row_number() OVER (ORDER BY b.id) - 1 AS rn
    FROM kjv_bible_verses b
  ) bv
  WHERE bv.rn = v_idx;
END; $$;

REVOKE ALL ON FUNCTION public.get_daily_verse(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_daily_verse(uuid) TO authenticated, anon, service_role;

NOTIFY pgrst, 'reload schema';

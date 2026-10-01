-- ============================================================================
-- An employee can be an APPROVED member of only ONE company at a time.
-- (They may still have pending applications elsewhere; only one approval.)
-- Enforced atomically by a partial unique index, with a friendly error on the
-- approval RPC.
-- ============================================================================

CREATE UNIQUE INDEX IF NOT EXISTS company_members_one_approved
  ON public.company_members(user_id) WHERE status = 'approved';

CREATE OR REPLACE FUNCTION public.company_decide_member(p_member_id uuid, p_status text)
  RETURNS public.company_members
  LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_row public.company_members;
BEGIN
  IF p_status NOT IN ('approved','rejected','suspended') THEN
    RAISE EXCEPTION 'Invalid status %', p_status;
  END IF;
  SELECT * INTO v_row FROM public.company_members WHERE id = p_member_id;
  IF v_row.id IS NULL THEN RAISE EXCEPTION 'Member not found'; END IF;
  IF NOT public.is_company_admin(v_row.company_id) AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'Not authorized';
  END IF;
  -- One approved company per employee.
  IF p_status = 'approved' AND EXISTS (
       SELECT 1 FROM public.company_members m2
       WHERE m2.user_id = v_row.user_id AND m2.status = 'approved'
         AND m2.company_id <> v_row.company_id) THEN
    RAISE EXCEPTION 'This employee is already an approved member of another company.';
  END IF;
  UPDATE public.company_members
     SET status = p_status, decided_at = now(), decided_by = auth.uid()
   WHERE id = p_member_id
  RETURNING * INTO v_row;
  RETURN v_row;
END; $$;
REVOKE ALL ON FUNCTION public.company_decide_member(uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_decide_member(uuid,text) TO authenticated;

NOTIFY pgrst, 'reload schema';

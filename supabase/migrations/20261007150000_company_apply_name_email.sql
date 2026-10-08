-- Collect the applicant's name + contact email when they request to join a
-- company, so the company reviewer sees who is asking (the account profile may
-- be blank or they may want a different contact address).

ALTER TABLE public.company_members
  ADD COLUMN IF NOT EXISTS applicant_name  text,
  ADD COLUMN IF NOT EXISTS applicant_email text;

-- Replace the apply RPC: now takes an optional name + email and stores them.
-- Signature changes, so drop the old 1-arg version first.
DROP FUNCTION IF EXISTS public.company_apply(uuid);

CREATE OR REPLACE FUNCTION public.company_apply(
  p_company_id uuid,
  p_name       text DEFAULT NULL,
  p_email      text DEFAULT NULL
)
RETURNS public.company_members
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_row public.company_members;
  v_name  text := NULLIF(btrim(p_name), '');
  v_email text := NULLIF(btrim(p_email), '');
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'Not signed in'; END IF;

  INSERT INTO public.company_members
    (company_id, user_id, status, applicant_name, applicant_email)
  VALUES (p_company_id, v_uid, 'pending', v_name, v_email)
  ON CONFLICT (company_id, user_id) DO UPDATE
    SET status = CASE WHEN public.company_members.status IN ('rejected','suspended')
                      THEN 'pending' ELSE public.company_members.status END,
        applied_at = now(),
        applicant_name  = COALESCE(EXCLUDED.applicant_name,  public.company_members.applicant_name),
        applicant_email = COALESCE(EXCLUDED.applicant_email, public.company_members.applicant_email)
  RETURNING * INTO v_row;

  RETURN v_row;
END;
$function$;

REVOKE ALL ON FUNCTION public.company_apply(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.company_apply(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

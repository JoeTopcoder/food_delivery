-- Lets the signed-in user check whether THEY have a pending staff invitation,
-- so the customer app can show the "Accept staff invite" entry only to people
-- who were actually invited (regular customers never see it). Matches on the
-- caller's own verified auth email; never exposes other users' invites.

CREATE OR REPLACE FUNCTION public.staff_has_pending_invite()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.staff_invitations si
    WHERE si.status = 'pending'
      AND si.expires_at > now()
      AND lower(si.email) = lower(
            (SELECT u.email FROM auth.users u WHERE u.id = auth.uid())
          )
  );
$$;

REVOKE ALL ON FUNCTION public.staff_has_pending_invite() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.staff_has_pending_invite() TO authenticated;

NOTIFY pgrst, 'reload schema';

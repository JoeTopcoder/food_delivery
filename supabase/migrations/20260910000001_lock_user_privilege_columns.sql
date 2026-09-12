-- SECURITY FIX: a customer could make themselves an admin.
--
-- The users_self_update RLS policy is USING (auth.uid() = id) with a NULL
-- WITH CHECK, so a logged-in user could update their own row to anything —
-- including role = 'admin'. Once admin they pass every is_admin() gate: the
-- whole admin surface, wallet adjustments included. Proven live: an ordinary
-- customer ran UPDATE users SET role='admin' WHERE id=auth.uid() and it took.
--
-- RLS WITH CHECK cannot compare against the OLD row, so ownership alone cannot
-- express "you may edit your row but not your privileges". Two independent
-- defences instead:
--
--   1. Revoke column-level UPDATE on the privilege columns from anon and
--      authenticated. Postgres checks column privileges separately from RLS,
--      so an UPDATE that sets any of these fails outright for those roles.
--      PostgREST only writes columns present in the request body, so an
--      ordinary profile edit (name, phone, avatar) never lists these and is
--      unaffected.
--
--   2. A BEFORE UPDATE trigger that freezes the same columns for any caller
--      who is not an admin, the service role, or direct backend SQL. This
--      catches anything the grant misses (a future policy, a SECURITY DEFINER
--      function that updates users) and is the durable guarantee.

-- ── 1. Column privileges ────────────────────────────────────────────────────
REVOKE UPDATE (role, email_verified, phone_verified, is_active)
  ON public.users FROM authenticated, anon;
-- service_role and postgres keep their grants: edge functions and migrations
-- legitimately set role (approving a restaurant, promoting staff).

-- ── 2. Trigger ──────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.protect_user_privilege_columns()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  -- Privileged = a real admin (JWT whose row is role=admin), the service role
  -- (edge functions), or direct backend SQL with no JWT at all (migrations).
  -- A normal customer JWT is authenticated with a non-null uid and is not an
  -- admin, so it is never privileged.
  v_privileged BOOLEAN :=
       public.is_admin()
    OR auth.role() = 'service_role'
    OR (auth.uid() IS NULL AND auth.role() IS NULL);
BEGIN
  IF v_privileged THEN
    RETURN NEW;
  END IF;

  -- Changing role is only ever an attack from here, so make it loud.
  IF NEW.role IS DISTINCT FROM OLD.role THEN
    RAISE EXCEPTION 'Not allowed to change role'
      USING errcode = 'insufficient_privilege';
  END IF;

  -- Trust flags are frozen silently: a client might round-trip them on a
  -- profile save without meaning to, and an error there would be noise. The
  -- old value simply stands.
  NEW.email_verified := OLD.email_verified;
  NEW.phone_verified := OLD.phone_verified;
  NEW.is_active      := OLD.is_active;
  RETURN NEW;
END;
$fn$;

DROP TRIGGER IF EXISTS trg_protect_user_privilege_columns ON public.users;
CREATE TRIGGER trg_protect_user_privilege_columns
  BEFORE UPDATE ON public.users
  FOR EACH ROW EXECUTE FUNCTION public.protect_user_privilege_columns();

NOTIFY pgrst, 'reload schema';

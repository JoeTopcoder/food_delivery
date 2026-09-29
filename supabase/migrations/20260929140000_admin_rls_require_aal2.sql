-- ============================================================================
-- Enforce two-step verification (MFA / aal2) for admin access AT THE DATABASE.
--
-- Until now, 2FA only guarded the app UI: an attacker with an admin password
-- plus the public anon key could call the API directly and never see the
-- challenge screen. This makes the *database itself* require aal2 for every
-- admin-gated row.
--
-- aal1 = password only, aal2 = password + a verified TOTP code this session.
--
-- Two parts:
--  1. is_admin() / pkg_is_admin() now require the caller's JWT to be aal2.
--     (current_user_is_admin() calls is_admin(), so it inherits this.)
--  2. The 144 policies that inlined `EXISTS(SELECT 1 FROM users WHERE
--     id=auth.uid() AND role='admin')` are rewritten to call is_admin(), so
--     they pick up the aal2 requirement too. Only the admin sub-expression is
--     replaced; every other branch (e.g. "user_id = auth.uid() OR admin") is
--     preserved verbatim.
--
-- IMPORTANT operational note: every admin MUST have TOTP enrolled, or they sit
-- at aal1 forever and lose admin data access. The email recovery path is aal1,
-- so it grants the console shell but NOT aal2 data access — re-enroll TOTP to
-- regain full access. service_role (edge functions) bypasses RLS and is
-- unaffected.
-- ============================================================================

-- 1) Helpers now require aal2 ------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_admin()
  RETURNS boolean
  LANGUAGE sql
  STABLE SECURITY DEFINER
  SET search_path = public
AS $function$
  SELECT EXISTS (
           SELECT 1 FROM public.users
           WHERE id = auth.uid() AND role = 'admin'
         )
     AND (auth.jwt() ->> 'aal') = 'aal2';
$function$;

CREATE OR REPLACE FUNCTION public.pkg_is_admin()
  RETURNS boolean
  LANGUAGE sql
  STABLE SECURITY DEFINER
  SET search_path = public
AS $function$
  SELECT EXISTS (
           SELECT 1 FROM public.users
           WHERE id = auth.uid() AND role = 'admin'
         )
     AND (auth.jwt() ->> 'aal') = 'aal2';
$function$;

-- 2) Convert inline admin EXISTS checks to is_admin() ------------------------
DO $do$
DECLARE
  p   record;
  pat text := 'EXISTS\s*\(\s*SELECT\s+1\s+FROM\s+users(\s+[a-z_]+)?\s+WHERE\s+\(\(([a-z_]+)\.id\s*=\s*auth\.uid\(\)\)\s+AND\s+\(\2\.role\s*=\s*''admin''::text\)\)\)';
  nq  text;
  nc  text;
  stmt text;
BEGIN
  FOR p IN
    SELECT policyname, schemaname, tablename, qual, with_check
    FROM pg_policies
    WHERE schemaname = 'public'
      AND (coalesce(qual,'') || coalesce(with_check,'')) ~ 'role\s*=\s*''admin''::text'
      AND (coalesce(qual,'') || coalesce(with_check,'')) !~ 'is_admin'
  LOOP
    nq := CASE WHEN p.qual IS NULL THEN NULL
               ELSE regexp_replace(p.qual, pat, 'is_admin()', 'g') END;
    nc := CASE WHEN p.with_check IS NULL THEN NULL
               ELSE regexp_replace(p.with_check, pat, 'is_admin()', 'g') END;

    stmt := format('ALTER POLICY %I ON %I.%I', p.policyname, p.schemaname, p.tablename);
    IF nq IS NOT NULL THEN stmt := stmt || format(' USING (%s)', nq); END IF;
    IF nc IS NOT NULL THEN stmt := stmt || format(' WITH CHECK (%s)', nc); END IF;
    EXECUTE stmt;
  END LOOP;
END
$do$;

NOTIFY pgrst, 'reload schema';

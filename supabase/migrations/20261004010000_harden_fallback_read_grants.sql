-- Hardcore audit cleanup: the fallback READ RPCs were still executable by PUBLIC
-- (hence anon) via PostgreSQL's default EXECUTE-to-PUBLIC. They are all gated by
-- auth.uid()/is_admin() so there was no data leak, but defense-in-depth: restrict
-- to authenticated + service_role only.
REVOKE EXECUTE ON FUNCTION public.get_call_fallback_status(uuid) FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.cancel_call_fallback(uuid)      FROM PUBLIC, anon;
REVOKE EXECUTE ON FUNCTION public.admin_call_fallback_log(int)    FROM PUBLIC, anon;
GRANT  EXECUTE ON FUNCTION public.get_call_fallback_status(uuid) TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.cancel_call_fallback(uuid)      TO authenticated, service_role;
GRANT  EXECUTE ON FUNCTION public.admin_call_fallback_log(int)    TO authenticated, service_role;
NOTIFY pgrst, 'reload schema';

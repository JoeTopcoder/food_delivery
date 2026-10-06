-- ============================================================================
-- CASHIER PRESENCE (Phase 2) — live online/offline status, server-authoritative.
--
-- Online status is SEPARATE from shift status (going offline never closes a
-- shift). The backend derives the user from auth, sets the timestamp itself,
-- upserts one row per (user, restaurant, session), and never trusts a
-- client-supplied timestamp or identity. Counts are computed authoritatively.
-- ============================================================================

INSERT INTO public.app_config (key, value) VALUES
  ('cashier_presence_timeout_s','90')
ON CONFLICT (key) DO NOTHING;

CREATE TABLE IF NOT EXISTS public.cashier_presence (
  user_id       uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  session_id    text NOT NULL,
  last_seen_at  timestamptz NOT NULL DEFAULT now(),
  created_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, restaurant_id, session_id)
);
CREATE INDEX IF NOT EXISTS idx_presence_restaurant_seen
  ON public.cashier_presence(restaurant_id, last_seen_at);

ALTER TABLE public.cashier_presence ENABLE ROW LEVEL SECURITY;

-- Read: owner/manager see all; a user sees their own. No client writes.
DROP POLICY IF EXISTS presence_select ON public.cashier_presence;
CREATE POLICY presence_select ON public.cashier_presence FOR SELECT TO authenticated
  USING (public.can_manage_restaurant_staff(restaurant_id) OR user_id = auth.uid());
REVOKE INSERT, UPDATE, DELETE ON public.cashier_presence FROM anon, authenticated;

-- Heartbeat: identity from auth, timestamp from the server, membership checked.
-- Throttled implicitly (an upsert; calling more often just rewrites the row).
CREATE OR REPLACE FUNCTION public.cashier_heartbeat(p_restaurant uuid, p_session text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;
  IF NOT public.is_restaurant_staff(p_restaurant, v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_a_member'); END IF;
  IF coalesce(trim(p_session),'')='' THEN RETURN jsonb_build_object('ok',false,'reason','bad_session'); END IF;

  INSERT INTO public.cashier_presence(user_id, restaurant_id, session_id, last_seen_at)
    VALUES (v_uid, p_restaurant, p_session, now())
  ON CONFLICT (user_id, restaurant_id, session_id)
    DO UPDATE SET last_seen_at = now();
  RETURN jsonb_build_object('ok',true,'at',now());
END; $$;
REVOKE ALL ON FUNCTION public.cashier_heartbeat(uuid,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cashier_heartbeat(uuid,text) TO authenticated, service_role;

-- End this session's presence (logout). Another live session keeps the user online.
CREATE OR REPLACE FUNCTION public.cashier_presence_end(p_restaurant uuid, p_session text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'reason','not_authenticated'); END IF;
  DELETE FROM public.cashier_presence
   WHERE user_id=v_uid AND restaurant_id=p_restaurant AND session_id=p_session;
  RETURN jsonb_build_object('ok',true);
END; $$;
REVOKE ALL ON FUNCTION public.cashier_presence_end(uuid,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cashier_presence_end(uuid,text) TO authenticated, service_role;

-- Authoritative per-cashier status list (owner/manager only). A cashier is
-- online if ANY of their sessions is within the timeout. Counts derived here,
-- never from client presence payloads.
CREATE OR REPLACE FUNCTION public.cashier_presence_list(p_restaurant uuid)
  RETURNS TABLE(user_id uuid, name text, role text, is_active boolean,
                online boolean, last_seen_at timestamptz)
  LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT s.user_id, u.name, s.role, s.is_active,
         (p.last_seen > now() - make_interval(secs => public.cf_config_int('cashier_presence_timeout_s',90))) AS online,
         p.last_seen
  FROM public.restaurant_staff s
  JOIN public.users u ON u.id = s.user_id
  LEFT JOIN (SELECT user_id, max(last_seen_at) last_seen FROM public.cashier_presence
             WHERE restaurant_id = p_restaurant GROUP BY user_id) p ON p.user_id = s.user_id
  WHERE s.restaurant_id = p_restaurant
    AND s.role = 'cashier'
    AND public.can_manage_restaurant_staff(p_restaurant)
  ORDER BY online DESC NULLS LAST, u.name;
$$;
GRANT EXECUTE ON FUNCTION public.cashier_presence_list(uuid) TO authenticated, service_role;

-- Stale-session cleanup (cron). Removes presence rows untouched for >1 hour.
CREATE OR REPLACE FUNCTION public.cashier_presence_cleanup()
  RETURNS int LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE n int;
BEGIN
  DELETE FROM public.cashier_presence WHERE last_seen_at < now() - interval '1 hour';
  GET DIAGNOSTICS n = ROW_COUNT; RETURN n;
END; $$;
REVOKE ALL ON FUNCTION public.cashier_presence_cleanup() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.cashier_presence_cleanup() TO service_role;

-- Realtime so the dashboard refreshes faster (RLS still applies to subscribers).
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_publication_tables WHERE pubname='supabase_realtime'
                 AND schemaname='public' AND tablename='cashier_presence') THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.cashier_presence;
  END IF;
END $$;

SELECT cron.schedule('cashier_presence_cleanup','*/15 * * * *',
  $$SELECT public.cashier_presence_cleanup()$$)
WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname='cashier_presence_cleanup');

NOTIFY pgrst, 'reload schema';

-- SECURITY: app_config was world-readable in full, secrets included.
--
-- The app_config_select policy was USING (true) for public, so the anon key
-- that ships in the app could read every row — including ncb_powertranz_password,
-- an NCB PowerTranz gateway credential. It is a placeholder today and nothing
-- reads it (not the client, not any edge function), but the moment a real
-- gateway password is entered there it would be broadcast to every app user.
--
-- Fix: a category='secret' convention. Secret rows are hidden from anon and
-- authenticated; the service role bypasses RLS, so edge functions still read
-- them. Publishable keys, fee rates and feature flags carry other categories
-- and stay readable, so nothing legitimate breaks.
--
-- When NCB goes live the password should move to an edge-function secret
-- (Deno.env), not live in app_config at all. This migration is the floor, not
-- the ceiling.

UPDATE public.app_config SET category = 'secret'
  WHERE key = 'ncb_powertranz_password';

DROP POLICY IF EXISTS app_config_select ON public.app_config;

CREATE POLICY app_config_select ON public.app_config
  FOR SELECT TO public
  USING (category IS DISTINCT FROM 'secret');

-- Explicit, in case service_role is ever configured without BYPASSRLS: edge
-- functions must always be able to read gateway credentials.
DROP POLICY IF EXISTS app_config_select_service ON public.app_config;
CREATE POLICY app_config_select_service ON public.app_config
  FOR SELECT TO service_role
  USING (true);

NOTIFY pgrst, 'reload schema';

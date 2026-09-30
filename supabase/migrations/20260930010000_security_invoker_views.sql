-- ============================================================================
-- Fix linter 0010 (security_definer_view) on 5 more views by switching them to
-- security_invoker, so they respect the querying user's RLS instead of the
-- view owner's. This can only ever show a caller LESS (their own RLS), never
-- more, so it cannot leak.
--
-- Audiences are already supported by the underlying tables' RLS:
--  - driver_wallet_summary  : drivers RLS = own row (+ admin) -> self/admin
--  - priority_delivery_stats: orders RLS (admin sees all) -> admin screen
--  - daily_actuals          : orders + admin_order_economics -> admin analytics
--  - laundry_admin_analytics: laundry_* admin policies -> admin analytics
--  - laundry_provider_earnings: laundry_payment_splits already allows provider
--    self-read + admin, so a provider sees their own earnings and admin sees all
-- ============================================================================

ALTER VIEW public.driver_wallet_summary     SET (security_invoker = on);
ALTER VIEW public.priority_delivery_stats   SET (security_invoker = on);
ALTER VIEW public.daily_actuals             SET (security_invoker = on);
ALTER VIEW public.laundry_admin_analytics   SET (security_invoker = on);
ALTER VIEW public.laundry_provider_earnings SET (security_invoker = on);

NOTIFY pgrst, 'reload schema';

-- NCB Genius Checkout (PowerTranz) payment integration — hosted redirect
-- checkout that mirrors the Stripe order flow. Columns to link an order to its
-- Genius Checkout session + transaction + reusable token, and a provider switch.
BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS ncb_session_id      text,
  ADD COLUMN IF NOT EXISTS ncb_transaction_id  text,
  ADD COLUMN IF NOT EXISTS ncb_token_id        text;

CREATE INDEX IF NOT EXISTS idx_orders_ncb_session ON public.orders(ncb_session_id);

-- Provider selection:
--   'stripe' : use Stripe only (current behaviour — default, nothing changes)
--   'ncb'    : use NCB Genius Checkout only
--   'auto'   : try NCB first, fall back to Stripe if NCB is unavailable
INSERT INTO app_config (key, value, category, updated_at)
VALUES ('payment_provider', 'stripe', 'general', now())
ON CONFLICT (key) DO NOTHING;

COMMIT;

NOTIFY pgrst, 'reload schema';

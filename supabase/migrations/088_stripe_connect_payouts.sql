-- ============================================================
-- Migration 088: Stripe Connect Instant Payout System
-- ============================================================

-- 1. Add Stripe Connect fields to drivers table
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS stripe_account_id        TEXT,
  ADD COLUMN IF NOT EXISTS stripe_onboarding_url    TEXT,
  ADD COLUMN IF NOT EXISTS payouts_enabled          BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stripe_debit_card_added  BOOLEAN NOT NULL DEFAULT FALSE,
  ADD COLUMN IF NOT EXISTS stripe_account_status    TEXT NOT NULL DEFAULT 'not_connected'
    CHECK (stripe_account_status IN ('not_connected', 'pending', 'active', 'restricted'));

-- 2. Add payout tracking to orders
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS payout_status       TEXT NOT NULL DEFAULT 'pending'
    CHECK (payout_status IN ('pending', 'paid', 'failed')),
  ADD COLUMN IF NOT EXISTS payout_id           TEXT,
  ADD COLUMN IF NOT EXISTS paid_out_at         TIMESTAMPTZ;

-- 3. Payout history table (both instant and standard)
CREATE TABLE IF NOT EXISTS public.payout_history (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id         UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  stripe_payout_id  TEXT UNIQUE,
  amount            NUMERIC(12, 2) NOT NULL,
  currency          TEXT NOT NULL DEFAULT 'usd',
  payout_type       TEXT NOT NULL DEFAULT 'instant'
    CHECK (payout_type IN ('instant', 'standard')),
  status            TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'paid', 'failed', 'cancelled')),
  failure_message   TEXT,
  idempotency_key   TEXT UNIQUE NOT NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. RLS for payout_history
ALTER TABLE public.payout_history ENABLE ROW LEVEL SECURITY;

-- Drivers can read their own payout history
CREATE POLICY "drivers_read_own_payouts"
  ON public.payout_history FOR SELECT
  USING (
    driver_id = (
      SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1
    )
  );

-- Only service role can insert/update (edge functions use service role)
CREATE POLICY "service_role_manage_payouts"
  ON public.payout_history FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- 5. Index for fast per-driver lookups
CREATE INDEX IF NOT EXISTS idx_payout_history_driver_id
  ON public.payout_history(driver_id);

CREATE INDEX IF NOT EXISTS idx_payout_history_status
  ON public.payout_history(status);

CREATE INDEX IF NOT EXISTS idx_drivers_stripe_account_id
  ON public.drivers(stripe_account_id);

-- 6. Updated_at trigger for payout_history
CREATE OR REPLACE FUNCTION public.set_payout_history_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_payout_history_updated_at ON public.payout_history;
CREATE TRIGGER trg_payout_history_updated_at
  BEFORE UPDATE ON public.payout_history
  FOR EACH ROW EXECUTE FUNCTION public.set_payout_history_updated_at();

-- 7. Helper view: driver wallet summary (available balance = earnings - paid out)
CREATE OR REPLACE VIEW public.driver_wallet_summary AS
SELECT
  d.id                       AS driver_id,
  d.user_id,
  d.stripe_account_id,
  d.payouts_enabled,
  d.stripe_debit_card_added,
  d.stripe_account_status,
  COALESCE(d.total_earnings, 0)  AS total_earned,
  COALESCE(d.total_paid_out, 0)  AS total_paid_out,
  GREATEST(0, COALESCE(d.total_earnings, 0) - COALESCE(d.total_paid_out, 0))
                              AS available_balance
FROM public.drivers d;

-- Drivers can read their own wallet summary
CREATE OR REPLACE FUNCTION public.get_driver_wallet_summary(p_user_id UUID)
RETURNS TABLE (
  driver_id             UUID,
  stripe_account_id     TEXT,
  payouts_enabled       BOOLEAN,
  stripe_debit_card_added BOOLEAN,
  stripe_account_status TEXT,
  total_earned          NUMERIC,
  total_paid_out        NUMERIC,
  available_balance     NUMERIC
) SECURITY DEFINER LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  RETURN QUERY
  SELECT
    dws.driver_id,
    dws.stripe_account_id,
    dws.payouts_enabled,
    dws.stripe_debit_card_added,
    dws.stripe_account_status,
    dws.total_earned,
    dws.total_paid_out,
    dws.available_balance
  FROM public.driver_wallet_summary dws
  WHERE dws.user_id = p_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_driver_wallet_summary(UUID) TO authenticated;

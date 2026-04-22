-- ==========================================================================
-- Migration 103: Stripe Connect — Payout Methods + Transactions Ledger
-- ==========================================================================

-- 1. driver_payout_methods — stores attached Stripe external accounts (display only)
CREATE TABLE IF NOT EXISTS public.driver_payout_methods (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id                   UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  stripe_external_account_id  TEXT NOT NULL UNIQUE,
  type                        TEXT NOT NULL CHECK (type IN ('bank_account', 'card')),
  last4                       TEXT NOT NULL,
  brand                       TEXT,        -- 'Visa', 'Mastercard' (cards only)
  bank_name                   TEXT,        -- bank name (bank_accounts only)
  currency                    TEXT NOT NULL DEFAULT 'usd',
  is_default                  BOOLEAN NOT NULL DEFAULT TRUE,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.driver_payout_methods ENABLE ROW LEVEL SECURITY;

CREATE POLICY "drivers_read_own_payout_methods"
  ON public.driver_payout_methods FOR SELECT
  USING (
    driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1)
  );

CREATE POLICY "service_role_manage_payout_methods"
  ON public.driver_payout_methods FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_payout_methods_driver_id
  ON public.driver_payout_methods(driver_id);

-- 2. driver_transactions — full wallet ledger (earnings + payouts)
CREATE TABLE IF NOT EXISTS public.driver_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id         UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  type              TEXT NOT NULL CHECK (type IN ('earning', 'payout', 'adjustment', 'fee', 'tip')),
  amount            NUMERIC(12, 2) NOT NULL,   -- positive = credit, negative = debit
  currency          TEXT NOT NULL DEFAULT 'usd',
  status            TEXT NOT NULL DEFAULT 'completed'
    CHECK (status IN ('pending', 'completed', 'failed')),
  description       TEXT,
  order_id          UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  payout_history_id UUID REFERENCES public.payout_history(id) ON DELETE SET NULL,
  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.driver_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "drivers_read_own_transactions"
  ON public.driver_transactions FOR SELECT
  USING (
    driver_id = (SELECT id FROM public.drivers WHERE user_id = auth.uid() LIMIT 1)
  );

CREATE POLICY "service_role_manage_transactions"
  ON public.driver_transactions FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_driver_transactions_driver_id
  ON public.driver_transactions(driver_id);

CREATE INDEX IF NOT EXISTS idx_driver_transactions_type
  ON public.driver_transactions(type);

CREATE INDEX IF NOT EXISTS idx_driver_transactions_order_id
  ON public.driver_transactions(order_id);

-- 3. Add KYC fields to drivers table for silent identity collection
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS kyc_first_name        TEXT,
  ADD COLUMN IF NOT EXISTS kyc_last_name         TEXT,
  ADD COLUMN IF NOT EXISTS kyc_dob_day           INT,
  ADD COLUMN IF NOT EXISTS kyc_dob_month         INT,
  ADD COLUMN IF NOT EXISTS kyc_dob_year          INT,
  ADD COLUMN IF NOT EXISTS kyc_ssn_last4         TEXT,
  ADD COLUMN IF NOT EXISTS kyc_address_line1     TEXT,
  ADD COLUMN IF NOT EXISTS kyc_address_city      TEXT,
  ADD COLUMN IF NOT EXISTS kyc_address_state     TEXT,
  ADD COLUMN IF NOT EXISTS kyc_address_postal    TEXT,
  ADD COLUMN IF NOT EXISTS kyc_address_country   TEXT DEFAULT 'US',
  ADD COLUMN IF NOT EXISTS kyc_submitted_at      TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS charges_enabled       BOOLEAN NOT NULL DEFAULT FALSE;

-- 4. Insert earning transaction when delivery completes (trigger on payout_history)
-- Earnings are tracked by complete-delivery edge function updating total_earnings.
-- Transactions table is populated by the add-driver-earning edge function.

-- 5. Grant function access
GRANT SELECT ON public.driver_payout_methods TO authenticated;
GRANT SELECT ON public.driver_transactions TO authenticated;

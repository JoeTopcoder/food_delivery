-- ============================================================
-- Stripe Connect Express Payout System
-- Migration: 20260707000001_stripe_connect_payout_system.sql
-- Note: payout_requests already exists from migration 024 (bank payouts).
--       This system uses stripe_payout_requests for Stripe Connect payouts.
-- ============================================================

-- ============================================================
-- TABLES
-- ============================================================

CREATE TABLE IF NOT EXISTS public.stripe_connected_accounts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) NOT NULL,
  role text NOT NULL CHECK (role IN ('driver','restaurant')),
  stripe_account_id text UNIQUE NOT NULL,
  country text DEFAULT 'US',
  currency text DEFAULT 'usd',
  account_type text DEFAULT 'express',
  onboarding_status text DEFAULT 'not_started' CHECK (onboarding_status IN ('not_started','pending','complete','restricted','rejected')),
  charges_enabled boolean DEFAULT false,
  payouts_enabled boolean DEFAULT false,
  details_submitted boolean DEFAULT false,
  transfers_capability_status text,
  requirements_currently_due jsonb DEFAULT '[]',
  requirements_eventually_due jsonb DEFAULT '[]',
  requirements_past_due jsonb DEFAULT '[]',
  disabled_reason text,
  last_synced_at timestamptz,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(user_id, role)
);

CREATE TABLE IF NOT EXISTS public.earnings_ledger (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) NOT NULL,
  role text NOT NULL CHECK (role IN ('driver','restaurant')),
  order_id uuid NULL,
  ride_id uuid NULL,
  restaurant_id uuid NULL,
  driver_id uuid NULL,
  type text NOT NULL CHECK (type IN ('order_earning','ride_earning','tip','bonus','adjustment','refund','chargeback','platform_reversal')),
  direction text NOT NULL CHECK (direction IN ('credit','debit')),
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  currency text DEFAULT 'usd',
  status text DEFAULT 'pending' CHECK (status IN ('pending','available','locked','withdrawn','reversed')),
  available_at timestamptz NOT NULL,
  payout_request_id uuid NULL,
  description text,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.stripe_payout_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) NOT NULL,
  role text NOT NULL CHECK (role IN ('driver','restaurant')),
  stripe_account_id text NOT NULL,
  amount_cents integer NOT NULL CHECK (amount_cents > 0),
  currency text DEFAULT 'usd',
  status text DEFAULT 'requested' CHECK (status IN ('requested','approved','processing','transferred','paid','failed','canceled','rejected')),
  stripe_transfer_id text,
  stripe_payout_id text,
  failure_code text,
  failure_message text,
  admin_note text,
  requested_by uuid REFERENCES auth.users(id),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  idempotency_key text UNIQUE NOT NULL,
  metadata jsonb DEFAULT '{}',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.payout_request_ledger_entries (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  payout_request_id uuid REFERENCES stripe_payout_requests(id) ON DELETE CASCADE NOT NULL,
  ledger_entry_id uuid REFERENCES earnings_ledger(id) NOT NULL,
  amount_cents integer NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE(ledger_entry_id)
);

CREATE TABLE IF NOT EXISTS public.stripe_webhook_events (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  stripe_event_id text UNIQUE NOT NULL,
  type text NOT NULL,
  livemode boolean DEFAULT false,
  processed boolean DEFAULT false,
  error text,
  payload jsonb NOT NULL,
  created_at timestamptz DEFAULT now(),
  processed_at timestamptz
);

CREATE TABLE IF NOT EXISTS public.app_payout_settings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  min_payout_cents integer DEFAULT 1000,
  max_payout_cents integer DEFAULT 500000,
  driver_hold_days integer DEFAULT 2,
  restaurant_hold_days integer DEFAULT 2,
  require_admin_approval boolean DEFAULT true,
  instant_payouts_enabled boolean DEFAULT false,
  platform_currency text DEFAULT 'usd',
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

INSERT INTO public.app_payout_settings DEFAULT VALUES
ON CONFLICT DO NOTHING;

-- ============================================================
-- INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_earnings_ledger_user_role_status ON earnings_ledger(user_id, role, status);
CREATE INDEX IF NOT EXISTS idx_earnings_ledger_available_at ON earnings_ledger(available_at);
CREATE INDEX IF NOT EXISTS idx_earnings_ledger_payout_request_id ON earnings_ledger(payout_request_id);
CREATE INDEX IF NOT EXISTS idx_earnings_ledger_order_id ON earnings_ledger(order_id);
CREATE INDEX IF NOT EXISTS idx_earnings_ledger_ride_id ON earnings_ledger(ride_id);
CREATE INDEX IF NOT EXISTS idx_stripe_payout_requests_user_role_status ON stripe_payout_requests(user_id, role, status);
CREATE INDEX IF NOT EXISTS idx_stripe_payout_requests_stripe_account ON stripe_payout_requests(stripe_account_id);
CREATE INDEX IF NOT EXISTS idx_stripe_payout_requests_created_at ON stripe_payout_requests(created_at);
CREATE INDEX IF NOT EXISTS idx_stripe_connected_accounts_user_id ON stripe_connected_accounts(user_id);

-- ============================================================
-- HELPER FUNCTION
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.users
    WHERE id = auth.uid() AND role = 'admin'
  );
$$;

-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.stripe_connected_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.earnings_ledger ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_payout_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payout_request_ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stripe_webhook_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_payout_settings ENABLE ROW LEVEL SECURITY;

-- stripe_connected_accounts
DROP POLICY IF EXISTS "users_read_own_connected_account" ON public.stripe_connected_accounts;
CREATE POLICY "users_read_own_connected_account"
  ON public.stripe_connected_accounts FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "service_role_write_connected_accounts" ON public.stripe_connected_accounts;
CREATE POLICY "service_role_write_connected_accounts"
  ON public.stripe_connected_accounts FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- earnings_ledger
DROP POLICY IF EXISTS "users_read_own_earnings" ON public.earnings_ledger;
CREATE POLICY "users_read_own_earnings"
  ON public.earnings_ledger FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "service_role_write_earnings" ON public.earnings_ledger;
CREATE POLICY "service_role_write_earnings"
  ON public.earnings_ledger FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- stripe_payout_requests
DROP POLICY IF EXISTS "users_read_own_stripe_payout_requests" ON public.stripe_payout_requests;
CREATE POLICY "users_read_own_stripe_payout_requests"
  ON public.stripe_payout_requests FOR SELECT
  USING (auth.uid() = user_id OR public.is_admin());

DROP POLICY IF EXISTS "service_role_write_stripe_payout_requests" ON public.stripe_payout_requests;
CREATE POLICY "service_role_write_stripe_payout_requests"
  ON public.stripe_payout_requests FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- payout_request_ledger_entries
DROP POLICY IF EXISTS "users_read_own_ledger_entries" ON public.payout_request_ledger_entries;
CREATE POLICY "users_read_own_ledger_entries"
  ON public.payout_request_ledger_entries FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.stripe_payout_requests pr
      WHERE pr.id = payout_request_id
        AND (pr.user_id = auth.uid() OR public.is_admin())
    )
  );

DROP POLICY IF EXISTS "service_role_write_ledger_entries" ON public.payout_request_ledger_entries;
CREATE POLICY "service_role_write_ledger_entries"
  ON public.payout_request_ledger_entries FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- stripe_webhook_events
DROP POLICY IF EXISTS "admins_read_webhook_events" ON public.stripe_webhook_events;
CREATE POLICY "admins_read_webhook_events"
  ON public.stripe_webhook_events FOR SELECT
  USING (public.is_admin());

DROP POLICY IF EXISTS "service_role_write_webhook_events" ON public.stripe_webhook_events;
CREATE POLICY "service_role_write_webhook_events"
  ON public.stripe_webhook_events FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- app_payout_settings
DROP POLICY IF EXISTS "authenticated_read_payout_settings" ON public.app_payout_settings;
CREATE POLICY "authenticated_read_payout_settings"
  ON public.app_payout_settings FOR SELECT
  USING (auth.role() = 'authenticated');

DROP POLICY IF EXISTS "service_role_write_payout_settings" ON public.app_payout_settings;
CREATE POLICY "service_role_write_payout_settings"
  ON public.app_payout_settings FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================
-- RPC FUNCTIONS
-- ============================================================

-- 1. get_user_earnings_summary
CREATE OR REPLACE FUNCTION public.get_user_earnings_summary(p_user_id uuid, p_role text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_available_cents bigint;
  v_pending_cents bigint;
  v_locked_cents bigint;
  v_withdrawn_cents bigint;
  v_lifetime_cents bigint;
BEGIN
  SELECT COALESCE(SUM(CASE WHEN direction='credit' THEN amount_cents ELSE -amount_cents END), 0)
  INTO v_available_cents
  FROM earnings_ledger
  WHERE user_id = p_user_id AND role = p_role AND status = 'available';

  SELECT COALESCE(SUM(amount_cents), 0) INTO v_pending_cents
  FROM earnings_ledger
  WHERE user_id = p_user_id AND role = p_role AND status = 'pending' AND direction = 'credit';

  SELECT COALESCE(SUM(amount_cents), 0) INTO v_locked_cents
  FROM earnings_ledger
  WHERE user_id = p_user_id AND role = p_role AND status = 'locked' AND direction = 'credit';

  SELECT COALESCE(SUM(amount_cents), 0) INTO v_withdrawn_cents
  FROM earnings_ledger
  WHERE user_id = p_user_id AND role = p_role AND status = 'withdrawn' AND direction = 'credit';

  SELECT COALESCE(SUM(CASE WHEN direction='credit' THEN amount_cents ELSE 0 END), 0)
  INTO v_lifetime_cents
  FROM earnings_ledger
  WHERE user_id = p_user_id AND role = p_role AND status != 'reversed';

  RETURN jsonb_build_object(
    'available_balance_cents', GREATEST(v_available_cents, 0),
    'pending_balance_cents', v_pending_cents,
    'locked_balance_cents', v_locked_cents,
    'withdrawn_balance_cents', v_withdrawn_cents,
    'lifetime_earned_cents', v_lifetime_cents
  );
END;
$$;

-- 2. lock_ledger_entries_for_payout
CREATE OR REPLACE FUNCTION public.lock_ledger_entries_for_payout(
  p_user_id uuid, p_role text, p_amount_cents bigint, p_payout_request_id uuid
)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_total_locked bigint := 0;
  v_entry RECORD;
  v_entries_locked integer := 0;
BEGIN
  FOR v_entry IN
    SELECT id, amount_cents FROM earnings_ledger
    WHERE user_id = p_user_id AND role = p_role
      AND status = 'available' AND direction = 'credit'
    ORDER BY created_at ASC
    FOR UPDATE SKIP LOCKED
  LOOP
    EXIT WHEN v_total_locked >= p_amount_cents;
    UPDATE earnings_ledger
    SET status = 'locked', payout_request_id = p_payout_request_id, updated_at = now()
    WHERE id = v_entry.id;
    INSERT INTO payout_request_ledger_entries(payout_request_id, ledger_entry_id, amount_cents)
    VALUES (p_payout_request_id, v_entry.id, v_entry.amount_cents)
    ON CONFLICT (ledger_entry_id) DO NOTHING;
    v_total_locked := v_total_locked + v_entry.amount_cents;
    v_entries_locked := v_entries_locked + 1;
  END LOOP;

  IF v_total_locked < p_amount_cents THEN
    RAISE EXCEPTION 'Insufficient available balance. Available: %, Required: %', v_total_locked, p_amount_cents;
  END IF;

  RETURN jsonb_build_object('locked_cents', v_total_locked, 'entries_count', v_entries_locked);
END;
$$;

-- 3. unlock_ledger_entries_for_payout
CREATE OR REPLACE FUNCTION public.unlock_ledger_entries_for_payout(p_payout_request_id uuid)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count integer;
BEGIN
  UPDATE earnings_ledger
  SET status = 'available', payout_request_id = NULL, updated_at = now()
  WHERE payout_request_id = p_payout_request_id AND status = 'locked';
  GET DIAGNOSTICS v_count = ROW_COUNT;
  DELETE FROM payout_request_ledger_entries WHERE payout_request_id = p_payout_request_id;
  RETURN v_count;
END;
$$;

-- 4. mark_payout_paid
CREATE OR REPLACE FUNCTION public.mark_payout_paid(p_payout_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE stripe_payout_requests
  SET status = 'paid', updated_at = now()
  WHERE id = p_payout_request_id;

  UPDATE earnings_ledger
  SET status = 'withdrawn', updated_at = now()
  WHERE payout_request_id = p_payout_request_id AND status = 'locked';
END;
$$;

-- 5. mark_payout_failed
CREATE OR REPLACE FUNCTION public.mark_payout_failed(
  p_payout_request_id uuid, p_failure_code text, p_failure_message text
)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE stripe_payout_requests
  SET status = 'failed',
      failure_code = p_failure_code,
      failure_message = p_failure_message,
      updated_at = now()
  WHERE id = p_payout_request_id;

  UPDATE earnings_ledger
  SET status = 'available', payout_request_id = NULL, updated_at = now()
  WHERE payout_request_id = p_payout_request_id AND status = 'locked';
END;
$$;

-- ============================================================
-- updated_at triggers
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_stripe_connected_accounts_updated_at ON public.stripe_connected_accounts;
CREATE TRIGGER trg_stripe_connected_accounts_updated_at
  BEFORE UPDATE ON public.stripe_connected_accounts
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_earnings_ledger_updated_at ON public.earnings_ledger;
CREATE TRIGGER trg_earnings_ledger_updated_at
  BEFORE UPDATE ON public.earnings_ledger
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_stripe_payout_requests_updated_at ON public.stripe_payout_requests;
CREATE TRIGGER trg_stripe_payout_requests_updated_at
  BEFORE UPDATE ON public.stripe_payout_requests
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS trg_app_payout_settings_updated_at ON public.app_payout_settings;
CREATE TRIGGER trg_app_payout_settings_updated_at
  BEFORE UPDATE ON public.app_payout_settings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

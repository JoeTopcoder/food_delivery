-- Migration 065: Create loyalty tables, add_loyalty_points RPC, and missing RLS policies
-- Fixes: loyalty_accounts & loyalty_transactions tables were ALTERed/referenced but never CREATEd.
-- Also adds the add_loyalty_points RPC function used by Dart service + Edge Functions.

-- ============================================================
-- 1. LOYALTY ACCOUNTS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.loyalty_accounts (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  points      INTEGER NOT NULL DEFAULT 0,
  total_earned   INTEGER NOT NULL DEFAULT 0,
  total_redeemed INTEGER NOT NULL DEFAULT 0,
  tier        TEXT NOT NULL DEFAULT 'bronze'
                CHECK (tier IN ('bronze', 'silver', 'gold', 'platinum')),
  tier_updated_at TIMESTAMPTZ DEFAULT now(),
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_loyalty_accounts_user_id
  ON public.loyalty_accounts(user_id);

-- ============================================================
-- 2. LOYALTY TRANSACTIONS TABLE
-- ============================================================
CREATE TABLE IF NOT EXISTS public.loyalty_transactions (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  order_id    UUID REFERENCES public.orders(id) ON DELETE SET NULL,
  points      INTEGER NOT NULL,
  type        TEXT NOT NULL CHECK (type IN ('earn', 'redeem')),
  description TEXT DEFAULT '',
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_user_id
  ON public.loyalty_transactions(user_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_order_id
  ON public.loyalty_transactions(order_id);
CREATE INDEX IF NOT EXISTS idx_loyalty_transactions_created_at
  ON public.loyalty_transactions(created_at DESC);

-- ============================================================
-- 3. RLS POLICIES
-- ============================================================
ALTER TABLE public.loyalty_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.loyalty_transactions ENABLE ROW LEVEL SECURITY;

-- Users can read their own loyalty account
DROP POLICY IF EXISTS "users_select_own_loyalty_account" ON public.loyalty_accounts;
CREATE POLICY "users_select_own_loyalty_account"
  ON public.loyalty_accounts FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Users can insert their own loyalty account (getOrCreateAccount)
DROP POLICY IF EXISTS "users_insert_own_loyalty_account" ON public.loyalty_accounts;
CREATE POLICY "users_insert_own_loyalty_account"
  ON public.loyalty_accounts FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can read their own loyalty transactions
DROP POLICY IF EXISTS "users_select_own_loyalty_transactions" ON public.loyalty_transactions;
CREATE POLICY "users_select_own_loyalty_transactions"
  ON public.loyalty_transactions FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Admin policies (re-create safely)
DROP POLICY IF EXISTS "admin_select_all_loyalty_accounts" ON public.loyalty_accounts;
CREATE POLICY "admin_select_all_loyalty_accounts"
  ON public.loyalty_accounts FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

DROP POLICY IF EXISTS "admin_select_all_loyalty_transactions" ON public.loyalty_transactions;
CREATE POLICY "admin_select_all_loyalty_transactions"
  ON public.loyalty_transactions FOR SELECT TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Restaurant owners can read loyalty accounts for their customers (via orders)
DROP POLICY IF EXISTS "restaurant_select_customer_loyalty" ON public.loyalty_accounts;
CREATE POLICY "restaurant_select_customer_loyalty"
  ON public.loyalty_accounts FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.restaurants r ON r.id = o.restaurant_id
      WHERE o.user_id = loyalty_accounts.user_id
        AND r.owner_id = auth.uid()
    )
  );

-- Restaurant owners can read loyalty transactions for their orders
DROP POLICY IF EXISTS "restaurant_select_order_loyalty_txns" ON public.loyalty_transactions;
CREATE POLICY "restaurant_select_order_loyalty_txns"
  ON public.loyalty_transactions FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.orders o
      JOIN public.restaurants r ON r.id = o.restaurant_id
      WHERE o.id = loyalty_transactions.order_id
        AND r.owner_id = auth.uid()
    )
  );

-- ============================================================
-- 4. AUTO-UPDATE TIER TRIGGER (idempotent re-create)
-- ============================================================
CREATE OR REPLACE FUNCTION public.update_loyalty_tier()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.total_earned >= 5000 THEN
    NEW.tier := 'platinum';
  ELSIF NEW.total_earned >= 2000 THEN
    NEW.tier := 'gold';
  ELSIF NEW.total_earned >= 500 THEN
    NEW.tier := 'silver';
  ELSE
    NEW.tier := 'bronze';
  END IF;

  IF NEW.tier IS DISTINCT FROM OLD.tier THEN
    NEW.tier_updated_at := now();
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_update_loyalty_tier ON public.loyalty_accounts;
CREATE TRIGGER trigger_update_loyalty_tier
  BEFORE UPDATE OF total_earned ON public.loyalty_accounts
  FOR EACH ROW
  EXECUTE FUNCTION update_loyalty_tier();

-- ============================================================
-- 5. add_loyalty_points RPC FUNCTION
-- ============================================================
-- Called from Dart LoyaltyService and Edge Functions (process-loyalty).
-- Atomically:  1) inserts a transaction row
--              2) upserts loyalty_accounts (adjusting points, total_earned/redeemed)
--              3) tier trigger fires automatically on total_earned change

CREATE OR REPLACE FUNCTION public.add_loyalty_points(
  p_user_id     UUID,
  p_points      INTEGER,
  p_order_id    UUID DEFAULT NULL,
  p_type        TEXT DEFAULT 'earn',
  p_description TEXT DEFAULT ''
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_abs_points INTEGER := ABS(p_points);
BEGIN
  -- Insert the transaction record
  INSERT INTO loyalty_transactions (user_id, order_id, points, type, description)
  VALUES (p_user_id, p_order_id, v_abs_points, p_type, p_description);

  -- Upsert the loyalty account
  INSERT INTO loyalty_accounts (user_id, points, total_earned, total_redeemed, updated_at)
  VALUES (
    p_user_id,
    CASE WHEN p_type = 'earn' THEN v_abs_points ELSE 0 END,
    CASE WHEN p_type = 'earn' THEN v_abs_points ELSE 0 END,
    CASE WHEN p_type = 'redeem' THEN v_abs_points ELSE 0 END,
    now()
  )
  ON CONFLICT (user_id) DO UPDATE SET
    points = loyalty_accounts.points
             + CASE WHEN p_type = 'earn'   THEN v_abs_points
                    WHEN p_type = 'redeem' THEN -v_abs_points
                    ELSE 0 END,
    total_earned = loyalty_accounts.total_earned
                   + CASE WHEN p_type = 'earn' THEN v_abs_points ELSE 0 END,
    total_redeemed = loyalty_accounts.total_redeemed
                     + CASE WHEN p_type = 'redeem' THEN v_abs_points ELSE 0 END,
    updated_at = now();
END;
$$;

-- ============================================================
-- 6. ADMIN UPDATE POLICY ON app_config
-- ============================================================
-- Admin loyalty screen needs to update app_config rows
DROP POLICY IF EXISTS "admin_update_app_config" ON public.app_config;
CREATE POLICY "admin_update_app_config"
  ON public.app_config FOR UPDATE TO authenticated
  USING (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  )
  WITH CHECK (
    EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

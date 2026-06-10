-- =============================================================================
-- Performance: missing indexes + auto-updated_at triggers
-- Audit findings: H-DB-2, H-DB-3, M-DB-1, M-DB-2, M-DB-3
-- Safe to run multiple times (all DDL uses IF NOT EXISTS / OR REPLACE).
-- =============================================================================

-- ── 1. orders.order_group_id index (H-DB-2) ──────────────────────────────────
-- orderByIdOrGroupIdProvider does: .eq('order_group_id', orderId)
-- Without this index it scans the full orders table.
CREATE INDEX IF NOT EXISTS idx_orders_order_group_id
  ON public.orders (order_group_id)
  WHERE order_group_id IS NOT NULL;

-- ── 2. wallet_transactions composite index (M-DB-1) ──────────────────────────
-- getTransactions does: .eq('user_id', userId).order('created_at', desc).limit(50)
-- Composite index satisfies the filter + sort in one index scan.
CREATE INDEX IF NOT EXISTS idx_wallet_transactions_user_created
  ON public.wallet_transactions (user_id, created_at DESC);

-- ── 3. ride_requests.customer_id index (M-DB-2) ──────────────────────────────
CREATE INDEX IF NOT EXISTS idx_ride_requests_customer_id
  ON public.ride_requests (customer_id);

-- ── 4. laundry_bookings.updated_at auto-update trigger (H-DB-3) ──────────────
-- The column exists but no trigger fires SET updated_at = NOW() on UPDATE.

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- laundry_bookings
DROP TRIGGER IF EXISTS trg_laundry_bookings_updated_at ON public.laundry_bookings;
CREATE TRIGGER trg_laundry_bookings_updated_at
  BEFORE UPDATE ON public.laundry_bookings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- laundry_providers (already has updated_at column; add trigger as safety net)
DROP TRIGGER IF EXISTS trg_laundry_providers_updated_at ON public.laundry_providers;
CREATE TRIGGER trg_laundry_providers_updated_at
  BEFORE UPDATE ON public.laundry_providers
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- car_service_bookings (manual updated_at set in app; trigger as guard)
DROP TRIGGER IF EXISTS trg_car_service_bookings_updated_at ON public.car_service_bookings;
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'car_service_bookings'
      AND column_name = 'updated_at'
  ) THEN
    CREATE TRIGGER trg_car_service_bookings_updated_at
      BEFORE UPDATE ON public.car_service_bookings
      FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();
  END IF;
END $$;

-- ── 5. car_service_providers FK fix (C-DB-1) ─────────────────────────────────
-- car_service_providers.user_id currently references auth.users, not public.users.
-- This means orphaned rows when a public.users record is deleted independently,
-- and admin joins on public.users for provider names return NULL.
--
-- IMPACT: changing the FK is a DESTRUCTIVE DDL operation that requires:
--   a) All existing car_service_providers.user_id values exist in public.users
--   b) A table lock during the migration
--
-- ACTION REQUIRED: Run the verification query below FIRST, then apply the FK fix
-- in a separate maintenance window.
--
-- Step 1 — verify no orphans:
--   SELECT csp.id, csp.user_id
--   FROM car_service_providers csp
--   LEFT JOIN public.users pu ON pu.id = csp.user_id
--   WHERE pu.id IS NULL;
--
-- Step 2 (if query above returns 0 rows) — apply in next migration:
--   ALTER TABLE public.car_service_providers
--     DROP CONSTRAINT car_service_providers_user_id_fkey,
--     ADD CONSTRAINT car_service_providers_user_id_fkey
--       FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE CASCADE;
--
-- This script intentionally does NOT run the ALTER TABLE automatically
-- to avoid breaking existing data during an unscheduled deploy.

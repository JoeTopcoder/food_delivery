-- =============================================================================
-- Migration 111: Customer cancellation of multi-restaurant orders
--
-- Problem: master_orders and restaurant_orders only have SELECT policies for
-- customers.  UPDATE is blocked by RLS, so cancel calls silently return 0 rows.
--
-- Fix:
--   1. Add UPDATE policies so customers can cancel their own orders.
--   2. Extend fn_recalculate_master_status() to also stamp cancelled_at so the
--      client never needs to UPDATE master_orders directly just for the timestamp.
-- =============================================================================

-- ── 1. customer UPDATE on master_orders ──────────────────────────────────────
-- Allows the customer to set status / cancelled_at on their own master order.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'master_orders' AND policyname = 'mo_customer_update'
  ) THEN
    CREATE POLICY "mo_customer_update" ON master_orders
      FOR UPDATE
      USING    (customer_id = auth.uid())
      WITH CHECK (customer_id = auth.uid());
  END IF;
END $$;

-- ── 2. customer UPDATE on restaurant_orders ───────────────────────────────────
-- Allows the customer to cancel individual sub-orders that belong to their
-- master orders.  The existing SECURITY DEFINER trigger then rolls the master
-- status up automatically.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'restaurant_orders' AND policyname = 'ro_customer_update'
  ) THEN
    CREATE POLICY "ro_customer_update" ON restaurant_orders
      FOR UPDATE
      USING (
        master_order_id IN (
          SELECT id FROM master_orders WHERE customer_id = auth.uid()
        )
      )
      WITH CHECK (
        master_order_id IN (
          SELECT id FROM master_orders WHERE customer_id = auth.uid()
        )
      );
  END IF;
END $$;

-- ── 3. Extend the status-rollup trigger to stamp cancelled_at ────────────────
-- Previously the trigger only updated status + updated_at.  Now it also stamps
-- cancelled_at when the derived status becomes 'cancelled', so the Flutter
-- client doesn't have to do a separate UPDATE on master_orders just for that.
CREATE OR REPLACE FUNCTION fn_recalculate_master_status()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_statuses  TEXT[];
  v_new       TEXT;
BEGIN
  SELECT ARRAY_AGG(status) INTO v_statuses
  FROM   restaurant_orders
  WHERE  master_order_id = NEW.master_order_id;

  IF v_statuses IS NULL THEN RETURN NEW; END IF;

  -- Derive new master status from the aggregate of sub-order statuses
  IF NOT EXISTS (
    SELECT 1 FROM unnest(v_statuses) s(v) WHERE v <> 'cancelled'
  ) THEN
    v_new := 'cancelled';
  ELSIF 'cancelled' = ANY(v_statuses) THEN
    v_new := 'partially_cancelled';
  ELSIF NOT EXISTS (
    SELECT 1 FROM unnest(v_statuses) s(v)
    WHERE  v NOT IN ('ready', 'picked_up')
  ) THEN
    v_new := 'ready_for_pickup';
  ELSIF 'preparing' = ANY(v_statuses) THEN
    v_new := 'preparing';
  ELSIF 'accepted' = ANY(v_statuses) THEN
    v_new := 'accepted';
  ELSE
    v_new := 'pending';
  END IF;

  UPDATE master_orders
  SET
    status       = v_new,
    updated_at   = NOW(),
    -- Stamp cancelled_at when the order first becomes fully cancelled
    cancelled_at = CASE
                     WHEN v_new = 'cancelled' AND cancelled_at IS NULL
                     THEN NOW()
                     ELSE cancelled_at
                   END
  WHERE  id = NEW.master_order_id
    AND  status NOT IN ('out_for_delivery', 'delivered', 'cancelled');

  RETURN NEW;
END;
$$;

-- Re-attach the trigger (CREATE OR REPLACE on the function is enough; the
-- trigger definition itself doesn't change, but DROP + CREATE is idempotent).
DROP TRIGGER IF EXISTS trg_ro_status_rollup ON restaurant_orders;
CREATE TRIGGER trg_ro_status_rollup
  AFTER UPDATE OF status ON restaurant_orders
  FOR EACH ROW
  WHEN (OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION fn_recalculate_master_status();

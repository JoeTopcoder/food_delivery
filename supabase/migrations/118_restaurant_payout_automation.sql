-- 118_restaurant_payout_automation.sql
-- Restaurant payout automation (Option B):
--   • restaurant_transactions: ledger of credits (earned) and debits (paid out)
--   • restaurant_balance_view: available balance per restaurant
--   • fn/trigger: auto-credit restaurant when an order reaches 'delivered'

-- ── Ledger table ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS restaurant_transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id     UUID NOT NULL REFERENCES restaurants(id) ON DELETE CASCADE,
  order_id          UUID REFERENCES orders(id) ON DELETE SET NULL,
  payout_request_id UUID REFERENCES payout_requests(id) ON DELETE SET NULL,
  type              TEXT NOT NULL CHECK (type IN ('credit', 'debit')),
  amount            DOUBLE PRECISION NOT NULL,
  description       TEXT,
  created_at        TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_rest_txn_restaurant_id ON restaurant_transactions(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_rest_txn_type ON restaurant_transactions(type);
CREATE INDEX IF NOT EXISTS idx_rest_txn_order_id ON restaurant_transactions(order_id);

-- ── RLS ───────────────────────────────────────────────────────────────────────
ALTER TABLE restaurant_transactions ENABLE ROW LEVEL SECURITY;

CREATE POLICY rest_txn_select ON restaurant_transactions
  FOR SELECT USING (
    auth.uid() IN (
      SELECT user_id FROM restaurants WHERE id = restaurant_id
    )
    OR EXISTS (
      SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'
    )
  );

CREATE POLICY rest_txn_insert_service ON restaurant_transactions
  FOR INSERT WITH CHECK (true);  -- service-role only via edge functions / triggers

-- ── Balance view ──────────────────────────────────────────────────────────────
CREATE OR REPLACE VIEW restaurant_balance_view AS
SELECT
  r.id   AS restaurant_id,
  r.name AS restaurant_name,
  COALESCE(SUM(CASE WHEN rt.type = 'credit' THEN rt.amount ELSE 0 END), 0) AS total_earnings,
  COALESCE(SUM(CASE WHEN rt.type = 'debit'  THEN rt.amount ELSE 0 END), 0) AS total_paid_out,
  COALESCE(SUM(CASE WHEN rt.type = 'credit' THEN rt.amount ELSE 0 END), 0)
    - COALESCE(SUM(CASE WHEN rt.type = 'debit' THEN rt.amount ELSE 0 END), 0)
  AS available_balance
FROM restaurants r
LEFT JOIN restaurant_transactions rt ON rt.restaurant_id = r.id
GROUP BY r.id, r.name;

-- ── Trigger: auto-credit on delivery ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_credit_restaurant_on_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_earned DOUBLE PRECISION;
BEGIN
  -- Only fire on status transitions into 'delivered' or 'completed'
  IF NEW.status IN ('delivered', 'completed')
     AND OLD.status IS DISTINCT FROM NEW.status
     AND NEW.restaurant_id IS NOT NULL
  THEN
    v_earned := COALESCE(NEW.total_amount, 0)
                - COALESCE(NEW.delivery_fee, 0)
                - COALESCE(NEW.commission_amount, 0);

    -- Idempotency: only insert once per order
    IF NOT EXISTS (
      SELECT 1 FROM restaurant_transactions
      WHERE order_id = NEW.id AND type = 'credit'
    ) THEN
      INSERT INTO restaurant_transactions
        (restaurant_id, order_id, type, amount, description)
      VALUES
        (NEW.restaurant_id, NEW.id, 'credit', v_earned,
         'Order delivered: ' || NEW.id);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_credit_restaurant_on_delivery ON orders;
CREATE TRIGGER trg_credit_restaurant_on_delivery
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION fn_credit_restaurant_on_delivery();

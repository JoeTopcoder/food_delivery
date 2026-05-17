-- ── Payments table (single source of truth) ────────────────────────────────
CREATE TABLE IF NOT EXISTS payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES orders(id) ON DELETE CASCADE,
  provider TEXT NOT NULL DEFAULT 'ncb_powertranz',
  amount NUMERIC(10,2) NOT NULL,
  currency TEXT NOT NULL DEFAULT 'JMD',
  status TEXT NOT NULL DEFAULT 'pending', -- pending, paid, failed, declined
  gateway_reference TEXT,
  transaction_id TEXT UNIQUE,
  raw_response JSONB,
  verified_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Webhook audit log ──────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS ncb_webhook_logs (
  id BIGSERIAL PRIMARY KEY,
  payment_id UUID REFERENCES payments(id) ON DELETE CASCADE,
  transaction_id TEXT,
  approved BOOLEAN,
  payload JSONB,
  verified BOOLEAN DEFAULT FALSE,
  received_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ── Indexes ────────────────────────────────────────────────────────────────
CREATE INDEX idx_payments_order_id ON payments(order_id);
CREATE INDEX idx_payments_status ON payments(status);
CREATE INDEX idx_payments_transaction_id ON payments(transaction_id);
CREATE INDEX idx_ncb_webhook_logs_payment_id ON ncb_webhook_logs(payment_id);
CREATE INDEX idx_ncb_webhook_logs_transaction_id ON ncb_webhook_logs(transaction_id);

-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE ncb_webhook_logs ENABLE ROW LEVEL SECURITY;

-- Customers can view their own payments
CREATE POLICY payments_select_own ON payments FOR SELECT
  USING (order_id IN (SELECT id FROM orders WHERE customer_id = auth.uid()));

-- Admin/restaurant can view orders' payments
CREATE POLICY payments_select_admin ON payments FOR SELECT
  USING (order_id IN (
    SELECT id FROM orders WHERE restaurant_id IN (
      SELECT id FROM restaurants WHERE owner_id = auth.uid()
    )
  ) OR EXISTS(
    SELECT 1 FROM auth.users WHERE auth.users.id = auth.uid() AND 
    (auth.users.raw_user_meta_data->>'role')::TEXT = 'admin'
  ));

-- Service role only writes
CREATE POLICY ncb_webhook_logs_insert ON ncb_webhook_logs FOR INSERT
  WITH CHECK (true);

CREATE POLICY ncb_webhook_logs_select_admin ON ncb_webhook_logs FOR SELECT
  USING (EXISTS(
    SELECT 1 FROM auth.users WHERE auth.users.id = auth.uid() AND 
    (auth.users.raw_user_meta_data->>'role')::TEXT = 'admin'
  ));


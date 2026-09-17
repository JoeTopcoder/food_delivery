-- Driver restaurant-payment float
-- Drivers pay non-partner restaurants in cash out of their float. Fronting food
-- cost debits cash_float; a NEGATIVE cash_float means the platform owes the driver
-- (reimbursement for food they paid). Every change is logged for transparency.

-- Ledger of every float movement (audited money trail).
CREATE TABLE IF NOT EXISTS driver_float_transactions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id     uuid NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,
  order_id      uuid REFERENCES orders(id) ON DELETE SET NULL,
  type          text NOT NULL,               -- restaurant_payment | cod_collection | admin_adjust | settlement
  amount        double precision NOT NULL,   -- signed: negative = float reduced (driver fronted cash)
  balance_after double precision NOT NULL,
  note          text,
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_driver_float_tx_driver
  ON driver_float_transactions (driver_id, created_at DESC);

ALTER TABLE driver_float_transactions ENABLE ROW LEVEL SECURITY;

-- A driver can read their own float history.
DROP POLICY IF EXISTS driver_reads_own_float_tx ON driver_float_transactions;
CREATE POLICY driver_reads_own_float_tx ON driver_float_transactions
  FOR SELECT TO authenticated
  USING (driver_id IN (SELECT id FROM drivers WHERE user_id = auth.uid()));

-- Atomic float change + ledger row. Returns the new balance.
CREATE OR REPLACE FUNCTION apply_driver_float_change(
  p_driver_id uuid,
  p_amount    numeric,
  p_type      text,
  p_order_id  uuid  DEFAULT NULL,
  p_note      text  DEFAULT NULL
) RETURNS double precision AS $$
DECLARE
  v_new double precision;
BEGIN
  UPDATE drivers
     SET cash_float = COALESCE(cash_float, 0) + p_amount,
         updated_at = now()
   WHERE id = p_driver_id
  RETURNING cash_float INTO v_new;

  IF v_new IS NULL THEN
    RAISE EXCEPTION 'driver % not found', p_driver_id;
  END IF;

  INSERT INTO driver_float_transactions
    (driver_id, order_id, type, amount, balance_after, note)
  VALUES
    (p_driver_id, p_order_id, p_type, p_amount, v_new, p_note);

  RETURN v_new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION apply_driver_float_change(uuid, numeric, text, uuid, text) TO service_role;

NOTIFY pgrst, 'reload schema';

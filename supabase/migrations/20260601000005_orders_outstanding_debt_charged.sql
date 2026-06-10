-- Track how much outstanding debt was charged and cleared at checkout.
-- The order's total_amount stays as the food/fee total;
-- outstanding_debt_charged records the extra platform debt that was also
-- collected from the customer at the same time.

ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS outstanding_debt_charged
    DECIMAL(12,2) NOT NULL DEFAULT 0;

COMMENT ON COLUMN orders.outstanding_debt_charged IS
  'Admin-recorded outstanding debt collected from the customer at checkout, '
  'in addition to the regular order total_amount.';

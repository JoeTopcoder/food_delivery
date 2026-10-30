-- Display prices in JMD but charge card payments in USD, converted at an
-- admin-set rate (JMD per USD). usd_amount = jmd_total / usd_jmd_rate.
-- e.g. rate 160 → J$4000 charges US$25.00; rate 140 → US$28.57.

INSERT INTO app_config (key, value)
VALUES ('usd_jmd_rate', '160')
ON CONFLICT (key) DO NOTHING;

-- Record what was actually charged on the card for each order (for receipts
-- and reconciliation), alongside the JMD totals the order is stored in.
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS charged_currency    text,
  ADD COLUMN IF NOT EXISTS charged_amount_usd  numeric,
  ADD COLUMN IF NOT EXISTS fx_rate_jmd_per_usd numeric;

NOTIFY pgrst, 'reload schema';

-- Absorb payment-processor fees: do not pass card / bank-transfer fees on
-- to the customer. The merchant absorbs the Lunipay (or any other
-- processor) cost.

UPDATE public.app_config
SET value = '0'
WHERE key IN ('card_fee_percent', 'bank_transfer_fee_percent', 'cash_fee_percent');

-- Migration: redenominate the platform to Jamaican Dollars
--
-- RATE: 155 JMD per USD, stored in app_config as fx_usd_jmd so it can be
-- corrected in one place rather than hunted through data.
--
-- This is a REDENOMINATION, not a repricing: every monetary value moves by the
-- same factor so real value is preserved. That includes wallet balances AND
-- the transaction ledger — scaling one without the other would desync balance
-- from history, which is exactly the class of bug that made wallet transfers
-- fail earlier in this project.
--
-- Menu prices round to the nearest J$10 because Jamaican retail prices are not
-- quoted in cents; fees round to the nearest J$5.
--
-- NOT converted, deliberately:
--   * orders / order_items — historical records of what was actually charged
--     in USD. Rewriting them would falsify the books and break reconciliation
--     against Stripe's own records.

INSERT INTO public.app_config (key, value, description)
VALUES ('fx_usd_jmd', '155', 'JMD per USD used for the redenomination. Update here if the rate is corrected.')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

DO $$
DECLARE r NUMERIC := 155;
BEGIN
  -- Menu / product prices, to the nearest J$10.
  UPDATE public.menus
  SET price = ROUND((price * r) / 10.0) * 10
  WHERE price IS NOT NULL AND price > 0;

  -- Store-level fees, to the nearest J$5.
  UPDATE public.restaurants
  SET delivery_fee         = CASE WHEN delivery_fee IS NOT NULL
                                  THEN ROUND((delivery_fee * r) / 5.0) * 5 END,
      service_fee          = CASE WHEN service_fee IS NOT NULL
                                  THEN ROUND((service_fee * r) / 5.0) * 5 END,
      minimum_order_amount = CASE WHEN minimum_order_amount IS NOT NULL
                                  THEN ROUND((minimum_order_amount * r) / 5.0) * 5 END;

  -- Promotions: only fixed amounts scale. Percentage discounts are ratios and
  -- must be left alone, or a 15% promo would become a 2325% one.
  UPDATE public.promo_codes
  SET discount_value      = CASE WHEN discount_type <> 'percentage'
                                 THEN ROUND(discount_value * r) ELSE discount_value END,
      max_discount_amount = CASE WHEN max_discount_amount IS NOT NULL
                                 THEN ROUND(max_discount_amount * r) END,
      min_order_amount    = CASE WHEN min_order_amount IS NOT NULL
                                 THEN ROUND(min_order_amount * r) END;

  -- Wallets and their ledger move together so balances stay reconciled.
  UPDATE public.wallets
  SET balance          = ROUND((balance * r)::numeric, 2),
      cashback_balance = ROUND((cashback_balance * r)::numeric, 2),
      debt_balance     = ROUND((COALESCE(debt_balance,0) * r)::numeric, 2),
      reserved_balance = ROUND((COALESCE(reserved_balance,0) * r)::numeric, 2);

  UPDATE public.wallet_transactions
  SET amount = ROUND((amount * r)::numeric, 2);

  -- Money-valued configuration. Percentages, multipliers and rates are
  -- explicitly excluded — scaling a 2.9% rate by 155 would be nonsense.
  UPDATE public.app_config
  SET value = (ROUND((value::NUMERIC * r) / 5.0) * 5)::TEXT
  WHERE key IN (
    'default_delivery_fee','min_delivery_fee','delivery_base_fee',
    'delivery_per_km_fee','delivery_per_mile_fee','delivery_per_mile_fee_peak',
    'pickup_service_fee','car_service_service_fee','driver_fee_per_delivery',
    'biz_daily_fixed_costs','biz_variable_cost_order','biz_monthly_marketing',
    'biz_cash_reserve'
  )
  AND value ~ '^[0-9]+(\.[0-9]+)?$';

  -- Currency identity.
  UPDATE public.app_config SET value = 'JMD' WHERE key = 'currency_code';
  UPDATE public.app_config SET value = 'J$'  WHERE key = 'currency_symbol';
  UPDATE public.app_config SET value = 'Jamaican Dollar' WHERE key = 'currency_name';
END $$;

NOTIFY pgrst, 'reload schema';

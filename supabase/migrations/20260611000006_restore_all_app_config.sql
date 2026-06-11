-- =====================================================================
-- RESTORATION: Fix all ~130 app_config rows corrupted by mass UPDATE
-- Root cause: UPDATE without WHERE clause using to_jsonb() overwrote
-- every row's value with the Stripe publishable key.
-- Fix: Restore every key to its correct plain-text value.
-- app_config.value is TEXT — no JSON wrapping needed.
-- =====================================================================

-- ── Tax & Core Fees ──────────────────────────────────────────────────
UPDATE app_config SET value = '0.10',  updated_at = now() WHERE key = 'tax_rate';
UPDATE app_config SET value = '1',     updated_at = now() WHERE key = 'tax_enabled';
UPDATE app_config SET value = '5.0',   updated_at = now() WHERE key = 'default_delivery_fee';
UPDATE app_config SET value = '3.00',  updated_at = now() WHERE key = 'driver_fee_per_delivery';
UPDATE app_config SET value = '2.5',   updated_at = now() WHERE key = 'card_fee_percent';
UPDATE app_config SET value = '1.0',   updated_at = now() WHERE key = 'bank_transfer_fee_percent';
UPDATE app_config SET value = '0',     updated_at = now() WHERE key = 'cash_fee_percent';
UPDATE app_config SET value = '0.05',  updated_at = now() WHERE key = 'platform_service_fee_rate';
UPDATE app_config SET value = '0.10',  updated_at = now() WHERE key = 'platform_service_fee_pct';
UPDATE app_config SET value = '0.0',   updated_at = now() WHERE key = 'pickup_service_fee';
UPDATE app_config SET value = '0.85',  updated_at = now() WHERE key = 'platform_commission_cap';
UPDATE app_config SET value = '0.15',  updated_at = now() WHERE key = 'restaurant_commission_pct';
UPDATE app_config SET value = '0.15',  updated_at = now() WHERE key = 'default_commission_rate';

-- ── Delivery distance-based ──────────────────────────────────────────
UPDATE app_config SET value = '3.0',   updated_at = now() WHERE key = 'delivery_base_fee';
UPDATE app_config SET value = '0.93',  updated_at = now() WHERE key = 'delivery_per_km_fee';
UPDATE app_config SET value = '1.6',   updated_at = now() WHERE key = 'delivery_base_km';
UPDATE app_config SET value = '25.0',  updated_at = now() WHERE key = 'delivery_max_km';
UPDATE app_config SET value = '1.0',   updated_at = now() WHERE key = 'delivery_surge_multiplier';
UPDATE app_config SET value = '1.0',   updated_at = now() WHERE key = 'delivery_base_miles';
UPDATE app_config SET value = '2.00',  updated_at = now() WHERE key = 'delivery_per_mile_fee';
UPDATE app_config SET value = '2.50',  updated_at = now() WHERE key = 'delivery_per_mile_fee_peak';
UPDATE app_config SET value = '3.0',   updated_at = now() WHERE key = 'min_delivery_fee';
UPDATE app_config SET value = '0.80',  updated_at = now() WHERE key = 'driver_pay_percent';
UPDATE app_config SET value = '0.0',   updated_at = now() WHERE key = 'driver_bonus_per_order';

-- ── Peak pricing ─────────────────────────────────────────────────────
UPDATE app_config SET value = '1.0',   updated_at = now() WHERE key = 'peak_addon_fee';
UPDATE app_config SET value = '11',    updated_at = now() WHERE key = 'peak_hours_start';
UPDATE app_config SET value = '14',    updated_at = now() WHERE key = 'peak_hours_end';
UPDATE app_config SET value = '18',    updated_at = now() WHERE key = 'peak_hours_start_2';
UPDATE app_config SET value = '21',    updated_at = now() WHERE key = 'peak_hours_end_2';

-- ── Surge pricing ────────────────────────────────────────────────────
UPDATE app_config SET value = '1.0',   updated_at = now() WHERE key = 'surge_base_multiplier';
UPDATE app_config SET value = '10',    updated_at = now() WHERE key = 'surge_high_demand_threshold';
UPDATE app_config SET value = '2.5',   updated_at = now() WHERE key = 'surge_max_multiplier';

-- ── Driver pay rates ─────────────────────────────────────────────────
UPDATE app_config SET value = '1.50',  updated_at = now() WHERE key = 'driver_rate_per_mile';
UPDATE app_config SET value = '0.93',  updated_at = now() WHERE key = 'driver_rate_per_km';
UPDATE app_config SET value = '0.15',  updated_at = now() WHERE key = 'driver_rate_per_minute';
UPDATE app_config SET value = '0.10',  updated_at = now() WHERE key = 'driver_wait_pay_per_minute';
UPDATE app_config SET value = '3.00',  updated_at = now() WHERE key = 'driver_base_pay_minimum';
UPDATE app_config SET value = '20.00', updated_at = now() WHERE key = 'driver_earnings_floor';
UPDATE app_config SET value = '0.00',  updated_at = now() WHERE key = 'driver_boost_amount';

-- ── Driver stack & tier scoring ──────────────────────────────────────
UPDATE app_config SET value = '3',     updated_at = now() WHERE key = 'driver_max_stack_orders';
UPDATE app_config SET value = '2.0',   updated_at = now() WHERE key = 'driver_stack_distance_km';
UPDATE app_config SET value = '0.30',  updated_at = now() WHERE key = 'driver_stack_min_increase';
UPDATE app_config SET value = '10',    updated_at = now() WHERE key = 'driver_stack_max_delay';
UPDATE app_config SET value = '60',    updated_at = now() WHERE key = 'driver_tier_silver_score';
UPDATE app_config SET value = '75',    updated_at = now() WHERE key = 'driver_tier_gold_score';
UPDATE app_config SET value = '90',    updated_at = now() WHERE key = 'driver_tier_elite_score';
UPDATE app_config SET value = '10',    updated_at = now() WHERE key = 'driver_location_interval_seconds';
UPDATE app_config SET value = '1.50',  updated_at = now() WHERE key = 'driver_extra_stop_pay';

-- ── Loyalty program ───────────────────────────────────────────────────
UPDATE app_config SET value = '0.10',  updated_at = now() WHERE key = 'loyalty_point_value';
UPDATE app_config SET value = '0.20',  updated_at = now() WHERE key = 'loyalty_max_redemption_percent';
UPDATE app_config SET value = '10',    updated_at = now() WHERE key = 'loyalty_points_per_100';
UPDATE app_config SET value = '0',     updated_at = now() WHERE key = 'loyalty_tier_bronze_threshold';
UPDATE app_config SET value = '500',   updated_at = now() WHERE key = 'loyalty_tier_silver_threshold';
UPDATE app_config SET value = '2000',  updated_at = now() WHERE key = 'loyalty_tier_gold_threshold';
UPDATE app_config SET value = '5000',  updated_at = now() WHERE key = 'loyalty_tier_platinum_threshold';
UPDATE app_config SET value = '1.0',   updated_at = now() WHERE key = 'loyalty_multiplier_bronze';
UPDATE app_config SET value = '1.25',  updated_at = now() WHERE key = 'loyalty_multiplier_silver';
UPDATE app_config SET value = '1.5',   updated_at = now() WHERE key = 'loyalty_multiplier_gold';
UPDATE app_config SET value = '2.0',   updated_at = now() WHERE key = 'loyalty_multiplier_platinum';

-- ── Referral / Earning credits ────────────────────────────────────────
UPDATE app_config SET value = '2.00',   updated_at = now() WHERE key = 'earning_referrer_signup_bonus';
UPDATE app_config SET value = '3.00',   updated_at = now() WHERE key = 'earning_referred_first_order';
UPDATE app_config SET value = '0.30',   updated_at = now() WHERE key = 'earning_direct_order_rate';
UPDATE app_config SET value = '0.10',   updated_at = now() WHERE key = 'earning_indirect_order_rate';
UPDATE app_config SET value = '5',      updated_at = now() WHERE key = 'earning_builder_min_refs';
UPDATE app_config SET value = '50',     updated_at = now() WHERE key = 'earning_builder_min_orders';
UPDATE app_config SET value = '15',     updated_at = now() WHERE key = 'earning_leader_min_refs';
UPDATE app_config SET value = '150',    updated_at = now() WHERE key = 'earning_leader_min_orders';
UPDATE app_config SET value = '25.00',  updated_at = now() WHERE key = 'earning_volume_bonus_300';
UPDATE app_config SET value = '100.00', updated_at = now() WHERE key = 'earning_volume_bonus_1000';
UPDATE app_config SET value = '250.00', updated_at = now() WHERE key = 'earning_volume_bonus_3000';
UPDATE app_config SET value = '300.00', updated_at = now() WHERE key = 'earning_monthly_cap';
UPDATE app_config SET value = '21',     updated_at = now() WHERE key = 'earning_credit_expiry_days';
UPDATE app_config SET value = '10.00',  updated_at = now() WHERE key = 'earning_min_order_to_use';
UPDATE app_config SET value = '0.50',   updated_at = now() WHERE key = 'earning_max_credit_pct';
UPDATE app_config SET value = '50.00',  updated_at = now() WHERE key = 'earning_restaurant_ref_credits';
UPDATE app_config SET value = '0.02',   updated_at = now() WHERE key = 'earning_restaurant_ref_commission_discount';

-- ── Tips ─────────────────────────────────────────────────────────────
UPDATE app_config SET value = '[2,3,5,10]', updated_at = now() WHERE key = 'preset_tips';
UPDATE app_config SET value = '24',      updated_at = now() WHERE key = 'post_tip_window_hours';

-- ── Orders / System timeouts ─────────────────────────────────────────
UPDATE app_config SET value = '30',    updated_at = now() WHERE key = 'api_timeout';
UPDATE app_config SET value = '10',    updated_at = now() WHERE key = 'connection_timeout';
UPDATE app_config SET value = '20',    updated_at = now() WHERE key = 'page_size';
UPDATE app_config SET value = '30',    updated_at = now() WHERE key = 'order_assignment_cutoff_minutes';
UPDATE app_config SET value = '25',    updated_at = now() WHERE key = 'default_prep_minutes';
UPDATE app_config SET value = '10',    updated_at = now() WHERE key = 'eta_buffer_minutes';
UPDATE app_config SET value = 'false', updated_at = now() WHERE key = 'maintenance_mode';

-- ── Subscriptions (MealHub+) ─────────────────────────────────────────
UPDATE app_config SET value = '12.00', updated_at = now() WHERE key = 'subscription_basic_price';
UPDATE app_config SET value = '9',     updated_at = now() WHERE key = 'subscription_basic_deliveries';
UPDATE app_config SET value = '24.00', updated_at = now() WHERE key = 'subscription_pro_price';
UPDATE app_config SET value = '22',    updated_at = now() WHERE key = 'subscription_pro_deliveries';
UPDATE app_config SET value = '15.0',  updated_at = now() WHERE key = 'subscription_min_cart';
UPDATE app_config SET value = '0.50',  updated_at = now() WHERE key = 'subscription_service_fee_discount';
UPDATE app_config SET value = '7',     updated_at = now() WHERE key = 'subscription_trial_days';

-- ── Payments / Card ───────────────────────────────────────────────────
UPDATE app_config SET value = '0',    updated_at = now() WHERE key = 'card_verification_charge_min';
UPDATE app_config SET value = '3',    updated_at = now() WHERE key = 'card_verification_charge_max';

-- ── Group orders ─────────────────────────────────────────────────────
UPDATE app_config SET value = '10',   updated_at = now() WHERE key = 'group_order_max_participants';
UPDATE app_config SET value = '60',   updated_at = now() WHERE key = 'group_order_deadline_minutes';

-- ── Receipts ─────────────────────────────────────────────────────────
UPDATE app_config SET value = 'MealHub',        updated_at = now() WHERE key = 'receipt_company_name';
UPDATE app_config SET value = 'Cayman Islands', updated_at = now() WHERE key = 'receipt_company_address';
UPDATE app_config SET value = '',               updated_at = now() WHERE key = 'receipt_company_trn';

-- ── Currency (USD) ───────────────────────────────────────────────────
UPDATE app_config SET value = 'USD',            updated_at = now() WHERE key = 'currency_code';
UPDATE app_config SET value = '$',              updated_at = now() WHERE key = 'currency_symbol';
UPDATE app_config SET value = 'US Dollar',      updated_at = now() WHERE key = 'currency_name';
UPDATE app_config SET value = 'Cayman Islands', updated_at = now() WHERE key = 'country_name';

-- ── Support contact ───────────────────────────────────────────────────
UPDATE app_config SET value = '+18765551234',      updated_at = now() WHERE key = 'support_phone';
UPDATE app_config SET value = 'support@7dash.app', updated_at = now() WHERE key = 'support_email';
UPDATE app_config SET value = '+18765551234',      updated_at = now() WHERE key = 'support_whatsapp';

-- ── Rides ─────────────────────────────────────────────────────────────
UPDATE app_config SET value = '10.0',  updated_at = now() WHERE key = 'airport_surcharge_jmd';
UPDATE app_config SET value = '30',    updated_at = now() WHERE key = 'ride_booking_advance_days';
UPDATE app_config SET value = '1',     updated_at = now() WHERE key = 'scheduled_ride_buffer_hours';
UPDATE app_config SET value = '30.0',  updated_at = now() WHERE key = 'ride_max_search_radius_km';
UPDATE app_config SET value = '90',    updated_at = now() WHERE key = 'ride_driver_offer_timeout_secs';
UPDATE app_config SET value = '72',    updated_at = now() WHERE key = 'ride_driver_sched_advance_hours';

-- ── Ride promo banners ────────────────────────────────────────────────
UPDATE app_config SET value = 'true',                                    updated_at = now() WHERE key = 'ride_promo_first_ride_enabled';
UPDATE app_config SET value = 'First ride free!',                        updated_at = now() WHERE key = 'ride_promo_first_ride_title';
UPDATE app_config SET value = 'Use code FIRSTRIDE at checkout',          updated_at = now() WHERE key = 'ride_promo_first_ride_subtitle';
UPDATE app_config SET value = 'FIRSTRIDE',                               updated_at = now() WHERE key = 'ride_promo_first_ride_code';
UPDATE app_config SET value = 'Book now',                                updated_at = now() WHERE key = 'ride_promo_first_ride_cta';
UPDATE app_config SET value = 'Ready for your next ride?',               updated_at = now() WHERE key = 'ride_promo_returning_title';
UPDATE app_config SET value = 'Fast, reliable rides at your fingertips', updated_at = now() WHERE key = 'ride_promo_returning_subtitle';
UPDATE app_config SET value = 'Book a ride',                             updated_at = now() WHERE key = 'ride_promo_returning_cta';

-- ── Car services ──────────────────────────────────────────────────────
UPDATE app_config SET value = '15.00', updated_at = now() WHERE key = 'car_service_mobile_fee';
UPDATE app_config SET value = '0.20',  updated_at = now() WHERE key = 'car_service_platform_fee_pct';
UPDATE app_config SET value = '2.50',  updated_at = now() WHERE key = 'car_service_service_fee';

-- ── Multi-restaurant ──────────────────────────────────────────────────
UPDATE app_config SET value = 'true',  updated_at = now() WHERE key = 'enable_multi_restaurant_orders';
UPDATE app_config SET value = '3',     updated_at = now() WHERE key = 'max_restaurants_per_order';
UPDATE app_config SET value = '15',    updated_at = now() WHERE key = 'multi_restaurant_radius_km';
UPDATE app_config SET value = '2.00',  updated_at = now() WHERE key = 'extra_stop_fee';
UPDATE app_config SET value = '8.0',   updated_at = now() WHERE key = 'max_restaurants_distance_km';
UPDATE app_config SET value = '15',    updated_at = now() WHERE key = 'multi_restaurant_extra_minutes';

-- ── Service toggles (admin-controlled feature flags) ────────────────
UPDATE app_config SET value = 'true', updated_at = now() WHERE key = 'service_food_enabled';
UPDATE app_config SET value = 'true', updated_at = now() WHERE key = 'service_grocery_enabled';
UPDATE app_config SET value = 'true', updated_at = now() WHERE key = 'service_rides_enabled';
UPDATE app_config SET value = 'true', updated_at = now() WHERE key = 'service_laundry_enabled';
UPDATE app_config SET value = 'true', updated_at = now() WHERE key = 'service_car_service_enabled';

-- ── NCB/PowerTranz (disabled — Stripe-only since migration 20260509) ────
UPDATE app_config SET value = '0',                                  updated_at = now() WHERE key = 'ncb_enabled';
UPDATE app_config SET value = '2.5',                                updated_at = now() WHERE key = 'ncb_fee_percent';
UPDATE app_config SET value = '1',                                  updated_at = now() WHERE key = 'ncb_use_sandbox';
UPDATE app_config SET value = 'test_merchant',                      updated_at = now() WHERE key = 'ncb_merchant_id';
UPDATE app_config SET value = 'test_powertranz_id',                 updated_at = now() WHERE key = 'ncb_powertranz_id';
UPDATE app_config SET value = 'test_password',                      updated_at = now() WHERE key = 'ncb_powertranz_password';
UPDATE app_config SET value = 'https://ptranz.com/api/spi',         updated_at = now() WHERE key = 'ncb_production_api_url';
UPDATE app_config SET value = 'https://staging.ptranz.com/api/spi', updated_at = now() WHERE key = 'ncb_sandbox_api_url';
UPDATE app_config SET value = 'pk_test_9bkNh0KkY850L2PyQQXiqhNfVbb6WiS4hdS4lMYA', updated_at = now() WHERE key = 'lunipay_publishable_key';

-- ── Stripe publishable key ────────────────────────────────────────────
-- Stored as plain text (no JSON quotes). _str() in app_config_service.dart handles both.
UPDATE app_config
SET value      = 'pk_live_51TMsI4IxFR3jJr2ajK6WRDk3qwgoWdeQ9OuHMlZwBcEj3O8LvFsOXcBkzq7OBhL5YooUFk7ERF1dGgnAerQcRGzI00bV3je0f5',
    updated_at = now()
WHERE key = 'stripe_publishable_key';

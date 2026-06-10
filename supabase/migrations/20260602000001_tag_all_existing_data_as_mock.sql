-- =============================================================================
-- Tag every existing row in every data table as mock / test data.
--
-- How it works:
--   1. Adds  is_mock_data BOOLEAN NOT NULL DEFAULT false  to each table.
--   2. Sets  is_mock_data = true  on ALL currently existing rows.
--   3. All rows created AFTER this migration default to false (real data).
--
-- To delete all mock data when going live, run:
--   supabase/delete_mock_data.sql
-- =============================================================================

-- Helper: add the column and immediately flag all current rows.
-- Wrapped in DO blocks so the migration is safe if re-run.

DO $$
DECLARE
  tbl TEXT;
  tables TEXT[] := ARRAY[
    -- Core user data
    'users',
    'user_addresses',
    'user_preferences',
    'user_events',
    'user_intelligence_profiles',
    'user_metrics',
    'sessions',

    -- Wallet & payments
    'wallets',
    'wallet_transactions',
    'payments',
    'saved_cards',
    'card_verifications',
    'earning_accounts',
    'earning_transactions',
    'payout_requests',
    'payout_history',

    -- Loyalty & promos
    'loyalty_accounts',
    'loyalty_transactions',
    'user_coupons',
    'promo_codes',
    'promotions',
    'scheduled_promotions',
    'promotion_results',
    'referrals',
    'favorites',
    'apology_coupon_log',

    -- Food delivery
    'restaurants',
    'restaurant_documents',
    'restaurant_ads',
    'restaurant_embeddings',
    'restaurant_prep_stats',
    'food_categories',
    'menus',
    'menu_items',
    'menu_item_sides',
    'orders',
    'order_items',
    'order_item_sides',
    'order_stacks',
    'order_scores',
    'order_issues',
    'reviews',
    'driver_declined_orders',

    -- Grocery
    'grocery_categories',

    -- Drivers
    'drivers',
    'driver_vehicles',
    'driver_licenses',
    'driver_insurance',
    'driver_identity_documents',
    'driver_verification_logs',
    'driver_consents',
    'driver_earnings',
    'driver_stats',
    'driver_transactions',
    'driver_payout_methods',

    -- Notifications & comms
    'notifications',
    'chat_messages',
    'conversations',
    'typing_indicators',
    'calls',

    -- Rides module
    'ride_requests',
    'ride_driver_requests',
    'ride_locations',
    'ride_messages',

    -- Package delivery
    'package_delivery_requests',
    'package_delivery_locations',
    'package_records',
    'package_scans',
    'shipping_companies',
    'shipping_company_webhooks',

    -- Laundry module
    'laundry_providers',
    'laundry_provider_services',
    'laundry_pricing',
    'laundry_bookings',
    'laundry_booking_items',
    'laundry_status_history',
    'laundry_photos',
    'laundry_weights',
    'laundry_driver_assignments',
    'laundry_reviews',
    'laundry_disputes',

    -- Car services module
    'car_service_providers',
    'car_service_provider_images',
    'car_service_provider_availability',
    'car_service_offerings',
    'car_service_bookings',
    'service_booking_items',
    'car_service_reviews',
    'car_service_payouts',
    'customer_vehicles',

    -- Multi-restaurant / master orders
    'master_orders',
    'restaurant_orders',
    'restaurant_order_items',
    'order_groups',

    -- AI / analytics
    'ai_recommendations',
    'daily_metrics',
    'retention_metrics',
    'experiments',
    'user_promotions',

    -- Hotels
    'hotel_bookings',
    'hotel_booking_attempts',
    'hotel_booking_events',
    'hotel_search_logs',
    'hotel_content_cache',

    -- Contracts & docs
    'contracts',

    -- Disputes & issues
    'disputes'
  ];
BEGIN
  FOREACH tbl IN ARRAY tables LOOP
    -- Skip if table doesn't exist in this project
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE  table_schema = 'public'
        AND  table_name   = tbl
    ) THEN
      RAISE NOTICE 'Table % does not exist — skipping', tbl;
      CONTINUE;
    END IF;

    -- Add the column if missing
    IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE  table_schema = 'public'
        AND  table_name   = tbl
        AND  column_name  = 'is_mock_data'
    ) THEN
      EXECUTE format(
        'ALTER TABLE public.%I ADD COLUMN is_mock_data BOOLEAN NOT NULL DEFAULT false',
        tbl
      );
      RAISE NOTICE 'Added is_mock_data to %', tbl;
    END IF;

    -- Mark every existing row as mock
    EXECUTE format(
      'UPDATE public.%I SET is_mock_data = true WHERE is_mock_data = false',
      tbl
    );
    RAISE NOTICE 'Flagged all rows in % as mock data', tbl;
  END LOOP;
END $$;

-- ─── Summary ─────────────────────────────────────────────────────────────────
DO $$
DECLARE
  tbl  TEXT;
  cnt  BIGINT;
  total BIGINT := 0;
BEGIN
  FOR tbl IN
    SELECT table_name FROM information_schema.columns
    WHERE  table_schema = 'public'
      AND  column_name  = 'is_mock_data'
    ORDER BY table_name
  LOOP
    EXECUTE format('SELECT COUNT(*) FROM public.%I WHERE is_mock_data = true', tbl)
      INTO cnt;
    IF cnt > 0 THEN
      RAISE NOTICE '  %-40s  %s mock rows', tbl, cnt;
      total := total + cnt;
    END IF;
  END LOOP;
  RAISE NOTICE '─────────────────────────────────';
  RAISE NOTICE '  TOTAL mock rows tagged: %', total;
  RAISE NOTICE '  Run supabase/delete_mock_data.sql to remove them before launch.';
END $$;

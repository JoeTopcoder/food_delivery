-- =============================================================================
-- DELETE ALL MOCK DATA — Run ONCE before going live in production.
--
-- Prerequisite: run migration 20260602000001_tag_all_existing_data_as_mock.sql
-- first so every test row has is_mock_data = true.
--
-- Deletes in FK-safe order (children before parents).
-- =============================================================================

BEGIN;

-- ── Preview (uncomment to check counts before deleting) ──────────────────────
/*
SELECT table_name,
       (xpath('/row/c/text()',
              query_to_xml(format('SELECT COUNT(*) AS c FROM public.%I WHERE is_mock_data', table_name), false, true, ''))
       )[1]::text::int AS mock_rows
FROM information_schema.columns
WHERE table_schema = 'public' AND column_name = 'is_mock_data'
ORDER BY table_name;
*/

-- ── Children first ────────────────────────────────────────────────────────────

DELETE FROM public.hotel_booking_events    WHERE is_mock_data = true;
DELETE FROM public.hotel_booking_attempts  WHERE is_mock_data = true;
DELETE FROM public.hotel_bookings          WHERE is_mock_data = true;
DELETE FROM public.hotel_search_logs       WHERE is_mock_data = true;
DELETE FROM public.hotel_content_cache     WHERE is_mock_data = true;

DELETE FROM public.package_scans               WHERE is_mock_data = true;
DELETE FROM public.package_delivery_locations  WHERE is_mock_data = true;
DELETE FROM public.package_delivery_requests   WHERE is_mock_data = true;
DELETE FROM public.package_records             WHERE is_mock_data = true;
DELETE FROM public.shipping_company_webhooks   WHERE is_mock_data = true;
DELETE FROM public.shipping_companies          WHERE is_mock_data = true;

DELETE FROM public.laundry_disputes            WHERE is_mock_data = true;
DELETE FROM public.laundry_reviews             WHERE is_mock_data = true;
DELETE FROM public.laundry_driver_assignments  WHERE is_mock_data = true;
DELETE FROM public.laundry_weights             WHERE is_mock_data = true;
DELETE FROM public.laundry_photos              WHERE is_mock_data = true;
DELETE FROM public.laundry_status_history      WHERE is_mock_data = true;
DELETE FROM public.laundry_booking_items       WHERE is_mock_data = true;
DELETE FROM public.laundry_bookings            WHERE is_mock_data = true;
DELETE FROM public.laundry_pricing             WHERE is_mock_data = true;
DELETE FROM public.laundry_provider_services   WHERE is_mock_data = true;
DELETE FROM public.laundry_providers           WHERE is_mock_data = true;

DELETE FROM public.service_booking_items       WHERE is_mock_data = true;
DELETE FROM public.car_service_reviews         WHERE is_mock_data = true;
DELETE FROM public.car_service_payouts         WHERE is_mock_data = true;
DELETE FROM public.car_service_bookings        WHERE is_mock_data = true;
DELETE FROM public.car_service_offerings       WHERE is_mock_data = true;
DELETE FROM public.car_service_provider_availability WHERE is_mock_data = true;
DELETE FROM public.car_service_provider_images WHERE is_mock_data = true;
DELETE FROM public.car_service_providers       WHERE is_mock_data = true;
DELETE FROM public.customer_vehicles           WHERE is_mock_data = true;

DELETE FROM public.ride_messages               WHERE is_mock_data = true;
DELETE FROM public.ride_locations              WHERE is_mock_data = true;
DELETE FROM public.ride_driver_requests        WHERE is_mock_data = true;
DELETE FROM public.ride_requests               WHERE is_mock_data = true;

DELETE FROM public.typing_indicators           WHERE is_mock_data = true;
DELETE FROM public.chat_messages               WHERE is_mock_data = true;
DELETE FROM public.conversations               WHERE is_mock_data = true;
DELETE FROM public.calls                       WHERE is_mock_data = true;
DELETE FROM public.notifications               WHERE is_mock_data = true;

DELETE FROM public.order_issues                WHERE is_mock_data = true;
DELETE FROM public.order_stacks                WHERE is_mock_data = true;
DELETE FROM public.order_scores                WHERE is_mock_data = true;
DELETE FROM public.restaurant_order_items      WHERE is_mock_data = true;
DELETE FROM public.restaurant_orders           WHERE is_mock_data = true;
DELETE FROM public.master_orders               WHERE is_mock_data = true;
DELETE FROM public.order_item_sides            WHERE is_mock_data = true;
DELETE FROM public.order_items                 WHERE is_mock_data = true;
DELETE FROM public.order_groups                WHERE is_mock_data = true;
DELETE FROM public.payments                    WHERE is_mock_data = true;
DELETE FROM public.driver_declined_orders      WHERE is_mock_data = true;
DELETE FROM public.orders                      WHERE is_mock_data = true;

DELETE FROM public.reviews                     WHERE is_mock_data = true;
DELETE FROM public.restaurant_ads              WHERE is_mock_data = true;
DELETE FROM public.restaurant_embeddings       WHERE is_mock_data = true;
DELETE FROM public.restaurant_prep_stats       WHERE is_mock_data = true;
DELETE FROM public.restaurant_documents        WHERE is_mock_data = true;
DELETE FROM public.menu_item_sides             WHERE is_mock_data = true;
DELETE FROM public.menus                       WHERE is_mock_data = true;
DELETE FROM public.menu_items                  WHERE is_mock_data = true;
DELETE FROM public.restaurants                 WHERE is_mock_data = true;

DELETE FROM public.driver_transactions         WHERE is_mock_data = true;
DELETE FROM public.driver_earnings             WHERE is_mock_data = true;
DELETE FROM public.driver_stats                WHERE is_mock_data = true;
DELETE FROM public.driver_payout_methods       WHERE is_mock_data = true;
DELETE FROM public.driver_verification_logs    WHERE is_mock_data = true;
DELETE FROM public.driver_consents             WHERE is_mock_data = true;
DELETE FROM public.driver_identity_documents   WHERE is_mock_data = true;
DELETE FROM public.driver_insurance            WHERE is_mock_data = true;
DELETE FROM public.driver_licenses             WHERE is_mock_data = true;
DELETE FROM public.driver_vehicles             WHERE is_mock_data = true;
DELETE FROM public.drivers                     WHERE is_mock_data = true;

DELETE FROM public.earning_transactions        WHERE is_mock_data = true;
DELETE FROM public.earning_accounts            WHERE is_mock_data = true;
DELETE FROM public.payout_history              WHERE is_mock_data = true;
DELETE FROM public.payout_requests             WHERE is_mock_data = true;
DELETE FROM public.wallet_transactions         WHERE is_mock_data = true;
DELETE FROM public.wallets                     WHERE is_mock_data = true;
DELETE FROM public.saved_cards                 WHERE is_mock_data = true;
DELETE FROM public.card_verifications          WHERE is_mock_data = true;

DELETE FROM public.loyalty_transactions        WHERE is_mock_data = true;
DELETE FROM public.loyalty_accounts            WHERE is_mock_data = true;
DELETE FROM public.user_coupons                WHERE is_mock_data = true;
DELETE FROM public.apology_coupon_log          WHERE is_mock_data = true;
DELETE FROM public.promotion_results           WHERE is_mock_data = true;
DELETE FROM public.user_promotions             WHERE is_mock_data = true;
DELETE FROM public.scheduled_promotions        WHERE is_mock_data = true;
DELETE FROM public.promotions                  WHERE is_mock_data = true;
DELETE FROM public.promo_codes                 WHERE is_mock_data = true;
DELETE FROM public.referrals                   WHERE is_mock_data = true;
DELETE FROM public.favorites                   WHERE is_mock_data = true;

DELETE FROM public.contracts                   WHERE is_mock_data = true;
DELETE FROM public.disputes                    WHERE is_mock_data = true;

DELETE FROM public.ai_recommendations          WHERE is_mock_data = true;
DELETE FROM public.user_intelligence_profiles  WHERE is_mock_data = true;
DELETE FROM public.user_events                 WHERE is_mock_data = true;
DELETE FROM public.user_metrics                WHERE is_mock_data = true;
DELETE FROM public.daily_metrics               WHERE is_mock_data = true;
DELETE FROM public.retention_metrics           WHERE is_mock_data = true;
DELETE FROM public.experiments                 WHERE is_mock_data = true;
DELETE FROM public.sessions                    WHERE is_mock_data = true;

DELETE FROM public.user_addresses              WHERE is_mock_data = true;
DELETE FROM public.user_preferences            WHERE is_mock_data = true;
DELETE FROM public.users                       WHERE is_mock_data = true;

COMMIT;

-- ── Verify — every count should be 0 ─────────────────────────────────────────
SELECT table_name, 'still has mock rows!' AS status
FROM   information_schema.columns
WHERE  table_schema = 'public'
  AND  column_name  = 'is_mock_data'
  AND  EXISTS (
    SELECT 1
    FROM   information_schema.tables t
    WHERE  t.table_schema = 'public'
      AND  t.table_name   = columns.table_name
  )
  -- only return tables that still have mock rows
ORDER BY table_name;
-- (run separately per table for exact counts if needed)

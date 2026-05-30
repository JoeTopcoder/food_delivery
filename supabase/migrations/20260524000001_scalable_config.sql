-- Migration: Scalable DB-driven configuration
-- Adds: airports table, feature_flags table, comprehensive app_config seeds.
-- Fills every gap needed for 80-95% of app settings to be DB-controlled.

-- ── airports ──────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.airports (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code         TEXT NOT NULL UNIQUE,            -- IATA code e.g. KIN, MBJ, OCJ
  name         TEXT NOT NULL,
  city         TEXT NOT NULL,
  address      TEXT NOT NULL DEFAULT '',
  latitude     DOUBLE PRECISION NOT NULL,
  longitude    DOUBLE PRECISION NOT NULL,
  surcharge    DOUBLE PRECISION NOT NULL DEFAULT 1500.0,  -- local currency flat fee
  terminals    TEXT[] NOT NULL DEFAULT '{}',              -- terminal names/codes
  is_active    BOOLEAN NOT NULL DEFAULT true,
  sort_order   INT NOT NULL DEFAULT 0,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.airports ENABLE ROW LEVEL SECURITY;

CREATE POLICY airports_select ON public.airports FOR SELECT USING (true);
CREATE POLICY airports_admin  ON public.airports FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

-- Jamaica airports seed
INSERT INTO public.airports
  (code, name, city, address, latitude, longitude, surcharge, terminals, sort_order)
VALUES
  ('KIN', 'Norman Manley International', 'Kingston',    'Norman Manley International Airport, Kingston',     17.9357, -76.7875, 1500.0, ARRAY['Main Terminal'],          1),
  ('MBJ', 'Sangster International',      'Montego Bay', 'Sangster International Airport, Montego Bay',       18.5037, -77.9133, 1500.0, ARRAY['Terminal 1','Terminal 2'], 2),
  ('OCJ', 'Ian Fleming International',   'Ocho Rios',   'Ian Fleming International Airport, Ocho Rios',      18.4049, -77.1002, 1500.0, ARRAY['Main Terminal'],          3)
ON CONFLICT (code) DO NOTHING;

-- ── feature_flags ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.feature_flags (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name         TEXT NOT NULL UNIQUE,
  enabled      BOOLEAN NOT NULL DEFAULT true,
  description  TEXT,
  roles        TEXT[] NOT NULL DEFAULT '{}',  -- empty array = all roles
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE public.feature_flags ENABLE ROW LEVEL SECURITY;

CREATE POLICY feature_flags_select ON public.feature_flags FOR SELECT USING (true);
CREATE POLICY feature_flags_admin  ON public.feature_flags FOR ALL
  USING (EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'admin'));

INSERT INTO public.feature_flags (name, enabled, description, roles) VALUES
  ('ride_sharing',           true,  'Ride sharing module (taxi/ridehail)',            ARRAY['user','driver','admin']),
  ('food_delivery',          true,  'Food delivery module',                           ARRAY[]::TEXT[]),
  ('grocery_delivery',       true,  'Grocery delivery module',                        ARRAY[]::TEXT[]),
  ('car_services',           true,  'Car wash and service bookings',                  ARRAY['user','service_provider','admin']),
  ('package_delivery',       true,  'Package / courier delivery module',              ARRAY[]::TEXT[]),
  ('loyalty_program',        true,  'Points-based loyalty rewards',                   ARRAY[]::TEXT[]),
  ('group_orders',           true,  'Group ordering feature',                         ARRAY['user','admin']),
  ('subscriptions',          true,  'MealHub+ subscription plans',                    ARRAY['user','admin']),
  ('airport_rides',          true,  'Airport pickup/dropoff for ride sharing',        ARRAY['user','driver','admin']),
  ('scheduled_rides',        true,  'Schedule rides in advance',                      ARRAY['user','driver','admin']),
  ('driver_cash_float',      true,  'Cash float management for drivers',              ARRAY['driver','admin']),
  ('surge_pricing',          true,  'Surge pricing zones',                            ARRAY[]::TEXT[]),
  ('ai_recommendations',     true,  'AI-powered food recommendations',                ARRAY['user','admin']),
  ('promos_and_coupons',     true,  'Promotions and coupon codes',                    ARRAY[]::TEXT[]),
  ('referral_program',       true,  'Referral rewards program',                       ARRAY[]::TEXT[]),
  ('stripe_payments',        true,  'Stripe card payment gateway',                    ARRAY[]::TEXT[]),
  ('wallet_payments',        true,  'In-app wallet balance payments',                 ARRAY[]::TEXT[]),
  ('cash_payments',          true,  'Cash on delivery / pickup',                      ARRAY[]::TEXT[]),
  ('maintenance_mode',       false, 'Block all logins and show maintenance page',     ARRAY[]::TEXT[]),
  ('driver_intelligence',    true,  'Driver performance AI insights',                 ARRAY['driver','admin']),
  ('demand_heatmap',         true,  'Driver demand heatmap screen',                   ARRAY['driver','admin']),
  ('stripe_connect_payouts', true,  'Stripe Connect driver/restaurant payouts',       ARRAY['driver','restaurant','admin']),
  ('restaurant_ads',         true,  'Sponsored restaurant ads shown to customers',    ARRAY['restaurant','admin']),
  ('group_delivery',         true,  'Group delivery (batch orders) optimisation',     ARRAY[]::TEXT[]),
  ('ai_ad_generator',        true,  'AI-generated ad copy for restaurants',           ARRAY['restaurant','admin'])
ON CONFLICT (name) DO NOTHING;

-- ── app_config: fill every remaining gap ─────────────────────────────────────
INSERT INTO app_config (key, value, value_type, category, description) VALUES

  -- Currency (Jamaica)
  ('currency_symbol',                 'J$',               'string',  'currency',     'Currency symbol shown in UI'),
  ('currency_code',                   'JMD',              'string',  'currency',     'ISO 4217 currency code'),
  ('currency_name',                   'Jamaican Dollar',  'string',  'currency',     'Full currency name'),
  ('country_name',                    'Jamaica',          'string',  'general',      'Country the app operates in'),

  -- Support contact
  ('support_phone',                   '+18765551234',     'string',  'support',      'Customer support phone number'),
  ('support_email',                   'support@7dash.app','string',  'support',      'Customer support email address'),
  ('support_whatsapp',                '+18765551234',     'string',  'support',      'WhatsApp support number'),

  -- Platform fees
  ('platform_service_fee_rate',       '0.05',             'number',  'fees',         'Platform service fee rate applied to subtotal (5%)'),
  ('pickup_service_fee',              '0.0',              'number',  'fees',         'Fee charged for customer pickup orders'),

  -- Ride sharing
  ('airport_surcharge_jmd',           '1500.0',           'number',  'rides',        'Flat surcharge for airport pickup or dropoff in JMD'),
  ('ride_booking_advance_days',       '30',               'number',  'rides',        'How many days ahead a customer can schedule a ride'),
  ('scheduled_ride_buffer_hours',     '1',                'number',  'rides',        'Minimum hours before pickup time for scheduled rides'),
  ('ride_max_search_radius_km',       '30.0',             'number',  'rides',        'Maximum radius km when searching for nearby drivers'),
  ('ride_driver_offer_timeout_secs',  '90',               'number',  'rides',        'Seconds before a driver offer card auto-expires'),
  ('ride_driver_sched_advance_hours', '72',               'number',  'rides',        'Hours ahead that drivers are notified of scheduled rides'),

  -- Ride promo banners
  ('ride_promo_first_ride_enabled',   'true',             'boolean', 'rides',        'Show first-ride promo banner on ride home screen'),
  ('ride_promo_first_ride_title',     'First ride free!', 'string',  'rides',        'First ride promo banner heading'),
  ('ride_promo_first_ride_subtitle',  'Use code FIRSTRIDE at checkout', 'string', 'rides', 'First ride promo banner subheading'),
  ('ride_promo_first_ride_code',      'FIRSTRIDE',        'string',  'rides',        'Promo code for first-ride discount'),
  ('ride_promo_first_ride_cta',       'Book now',         'string',  'rides',        'CTA button text on first-ride banner'),
  ('ride_promo_returning_title',      'Ready for your next ride?', 'string', 'rides','Returning customer banner heading'),
  ('ride_promo_returning_subtitle',   'Fast, reliable rides at your fingertips', 'string', 'rides', 'Returning customer banner subheading'),
  ('ride_promo_returning_cta',        'Book a ride',      'string',  'rides',        'CTA button text on returning customer banner'),

  -- Car services
  ('car_service_mobile_fee',          '15.00',            'number',  'car_services', 'Mobile car wash service fee in currency'),
  ('car_service_platform_fee_pct',    '0.20',             'number',  'car_services', 'Platform commission on car service jobs (20%)'),
  ('car_service_service_fee',         '2.50',             'number',  'car_services', 'Booking fee per car service job'),

  -- Delivery detail
  ('delivery_base_miles',             '1.0',              'number',  'delivery',     'Miles included in base delivery fee'),
  ('delivery_base_km',                '1.6',              'number',  'delivery',     'km included in base delivery fee (~1 mile)'),
  ('delivery_per_mile_fee',           '2.00',             'number',  'delivery',     'Standard per-mile delivery fee'),
  ('delivery_per_mile_fee_peak',      '2.50',             'number',  'delivery',     'Peak-hours per-mile delivery fee'),
  ('min_delivery_fee',                '3.0',              'number',  'delivery',     'Minimum delivery fee charged to customer'),
  ('driver_pay_percent',              '0.80',             'number',  'delivery',     'Fraction of delivery fee paid to driver (80%)'),
  ('driver_bonus_per_order',          '0.0',              'number',  'delivery',     'Extra bonus paid to driver per completed order'),
  ('driver_rate_per_mile',            '1.50',             'number',  'delivery',     'Driver pay rate per mile'),
  ('driver_rate_per_km',              '0.93',             'number',  'delivery',     'Driver pay rate per km (~$1.50/mile)'),
  ('driver_base_pay_minimum',         '3.0',              'number',  'delivery',     'Minimum driver pay per delivery regardless of distance'),
  ('peak_addon_fee',                  '1.0',              'number',  'delivery',     'Extra fee added to delivery during peak hours'),
  ('peak_hours_start',                '11',               'number',  'delivery',     'Peak window 1 start hour (24-hour clock)'),
  ('peak_hours_end',                  '14',               'number',  'delivery',     'Peak window 1 end hour (24-hour clock)'),
  ('peak_hours_start_2',              '18',               'number',  'delivery',     'Peak window 2 start hour (24-hour clock)'),
  ('peak_hours_end_2',                '21',               'number',  'delivery',     'Peak window 2 end hour (24-hour clock)'),

  -- Subscriptions (MealHub+)
  ('subscription_basic_price',        '12.0',             'number',  'subscription', 'Basic plan monthly price'),
  ('subscription_basic_deliveries',   '9',                'number',  'subscription', 'Free deliveries per month on basic plan'),
  ('subscription_pro_price',          '24.0',             'number',  'subscription', 'Pro plan monthly price'),
  ('subscription_pro_deliveries',     '22',               'number',  'subscription', 'Free deliveries per month on pro plan'),
  ('subscription_min_cart',           '15.0',             'number',  'subscription', 'Minimum cart value to use subscription benefit'),
  ('subscription_service_fee_discount','0.50',            'number',  'subscription', 'Fraction of service fee discounted for subscribers'),

  -- Payments
  ('card_verification_charge_min',    '0',                'number',  'payments',     'Minimum Stripe verification hold amount'),
  ('card_verification_charge_max',    '3',                'number',  'payments',     'Maximum Stripe verification hold amount'),

  -- System / maintenance
  ('maintenance_mode',                'false',            'boolean', 'system',       'Set true to block all logins and show maintenance screen')

ON CONFLICT (key) DO NOTHING;

-- =============================================================================
-- Seed: 7 Car Service Providers for 7Dash Services
-- Creates auth users, provider profiles, service offerings, and availability.
-- =============================================================================

DO $$
DECLARE
  -- Fixed UUIDs so this migration is idempotent
  p1_id UUID := 'a0000001-0000-0000-0000-000000000001';
  p2_id UUID := 'a0000001-0000-0000-0000-000000000002';
  p3_id UUID := 'a0000001-0000-0000-0000-000000000003';
  p4_id UUID := 'a0000001-0000-0000-0000-000000000004';
  p5_id UUID := 'a0000001-0000-0000-0000-000000000005';
  p6_id UUID := 'a0000001-0000-0000-0000-000000000006';
  p7_id UUID := 'a0000001-0000-0000-0000-000000000007';

  -- Category IDs (seeded by the main migration)
  cat_exterior UUID;
  cat_interior UUID;
  cat_full     UUID;
  cat_wax      UUID;
  cat_engine   UUID;

  -- Provider record IDs
  prov1_id UUID;
  prov2_id UUID;
  prov3_id UUID;
  prov4_id UUID;
  prov5_id UUID;
  prov6_id UUID;
  prov7_id UUID;

BEGIN

  -- ── 1. Look up category IDs ──────────────────────────────────────────────
  SELECT id INTO cat_exterior FROM public.car_service_categories WHERE name = 'Exterior Wash'  LIMIT 1;
  SELECT id INTO cat_interior FROM public.car_service_categories WHERE name = 'Interior Detail' LIMIT 1;
  SELECT id INTO cat_full     FROM public.car_service_categories WHERE name = 'Full Detail'     LIMIT 1;
  SELECT id INTO cat_wax      FROM public.car_service_categories WHERE name = 'Wax & Polish'    LIMIT 1;
  SELECT id INTO cat_engine   FROM public.car_service_categories WHERE name = 'Engine Clean'    LIMIT 1;

  -- ── 2. Create auth.users entries (minimal — for FK satisfaction only) ────
  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data,
    is_super_admin, confirmation_token, recovery_token,
    email_change_token_new, email_change
  ) VALUES
    (p1_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'gleamprowash@7dash.local',  '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{"name":"Gleam Pro Wash"}',
     false, '', '', '', ''),
    (p2_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'shineshielddetail@7dash.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{"name":"Shine Shield Detailing"}',
     false, '', '', '', ''),
    (p3_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'sparkleautocare@7dash.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{"name":"Sparkle Auto Care"}',
     false, '', '', '', ''),
    (p4_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'prestige_mobile_wash@7dash.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{"name":"Prestige Mobile Wash"}',
     false, '', '', '', ''),
    (p5_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'crystalcleardetail@7dash.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{"name":"Crystal Clear Detail"}',
     false, '', '', '', ''),
    (p6_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'eliteshine_auto@7dash.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{"name":"Elite Shine Auto"}',
     false, '', '', '', ''),
    (p7_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
     'rapidwashpro@7dash.local', '', now(), now(), now(),
     '{"provider":"email","providers":["email"]}', '{"name":"Rapid Wash Pro"}',
     false, '', '', '', '')
  ON CONFLICT (id) DO NOTHING;

  -- ── 3. Create car_service_providers ─────────────────────────────────────
  INSERT INTO public.car_service_providers (
    user_id, business_name, bio,
    profile_image_url, banner_image_url,
    rating, total_reviews, total_bookings,
    is_active, is_verified,
    service_area_radius_km,
    base_location_lat, base_location_lng, base_location_address,
    stripe_payouts_enabled
  ) VALUES
    -- 1: Gleam Pro Wash
    (p1_id, 'Gleam Pro Wash',
     'Kingston''s top-rated exterior wash service. We come to you — driveway, office, or anywhere in between.',
     'https://images.unsplash.com/photo-1558618666-fcd25c85cd64?w=400',
     'https://images.unsplash.com/photo-1619642751034-765dfdf7c58e?w=800',
     4.8, 142, 218, true, true, 20,
     18.0095, -76.7936, 'Half Way Tree, Kingston 10', true),

    -- 2: Shine Shield Detailing
    (p2_id, 'Shine Shield Detailing',
     'Premium interior and exterior detailing. We use only professional-grade products for a showroom finish.',
     'https://images.unsplash.com/photo-1607860108855-64acf2078ed9?w=400',
     'https://images.unsplash.com/photo-1542362567-b07e54358753?w=800',
     4.7, 98, 175, true, true, 25,
     18.0168, -76.7660, 'Liguanea, Kingston 6', false),

    -- 3: Sparkle Auto Care
    (p3_id, 'Sparkle Auto Care',
     'Affordable, reliable, and thorough. Full details, engine cleans, and everything in between.',
     'https://images.unsplash.com/photo-1578662996442-48f60103fc96?w=400',
     'https://images.unsplash.com/photo-1563720223185-11003d516935?w=800',
     4.6, 67, 134, true, false, 15,
     18.0069, -76.7832, 'New Kingston, Kingston 5', false),

    -- 4: Prestige Mobile Wash
    (p4_id, 'Prestige Mobile Wash',
     'Luxury mobile detailing for discerning car owners. Ceramic coating, paint correction, and full interior restoration.',
     'https://images.unsplash.com/photo-1616432043562-3671ea2e5242?w=400',
     'https://images.unsplash.com/photo-1520340356584-f9917d1eea6f?w=800',
     4.9, 213, 389, true, true, 30,
     18.0132, -76.7699, 'Hope Road, Kingston 6', true),

    -- 5: Crystal Clear Detail
    (p5_id, 'Crystal Clear Detail',
     'Specialising in wax, polish, and paint protection. Your car will look better than when you bought it.',
     'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?w=400',
     'https://images.unsplash.com/photo-1494976388531-d1058494cdd8?w=800',
     4.5, 54, 89, true, false, 20,
     18.0180, -76.8000, 'Molynes Road, Kingston 10', false),

    -- 6: Elite Shine Auto
    (p6_id, 'Elite Shine Auto',
     'Family-run detailing business serving Kingston since 2018. Trusted by hundreds of happy customers.',
     'https://images.unsplash.com/photo-1605559424843-9e4c228bf1c2?w=400',
     'https://images.unsplash.com/photo-1549317661-bd32c8ce0db2?w=800',
     4.7, 176, 302, true, true, 20,
     18.0350, -76.8050, 'Red Hills Road, Kingston 10', true),

    -- 7: Rapid Wash Pro
    (p7_id, 'Rapid Wash Pro',
     'Fast, efficient, and eco-friendly. We use waterless wash technology — great for the environment and your paint.',
     'https://images.unsplash.com/photo-1592198084033-aade902d1aae?w=400',
     'https://images.unsplash.com/photo-1536152470836-b943b246224c?w=800',
     4.4, 41, 63, true, false, 15,
     18.0297, -76.7778, 'Manor Park, Kingston 8', false)
  ON CONFLICT (user_id) DO NOTHING;

  -- Re-fetch provider IDs (since RETURNING only gives the last inserted row)
  SELECT id INTO prov1_id FROM public.car_service_providers WHERE user_id = p1_id;
  SELECT id INTO prov2_id FROM public.car_service_providers WHERE user_id = p2_id;
  SELECT id INTO prov3_id FROM public.car_service_providers WHERE user_id = p3_id;
  SELECT id INTO prov4_id FROM public.car_service_providers WHERE user_id = p4_id;
  SELECT id INTO prov5_id FROM public.car_service_providers WHERE user_id = p5_id;
  SELECT id INTO prov6_id FROM public.car_service_providers WHERE user_id = p6_id;
  SELECT id INTO prov7_id FROM public.car_service_providers WHERE user_id = p7_id;

  -- ── 4. Service offerings per provider ───────────────────────────────────

  -- Provider 1: Gleam Pro Wash — exterior focus
  INSERT INTO public.car_service_offerings (provider_id, category_id, name, description, duration_minutes, base_price, is_active)
  VALUES
    (prov1_id, cat_exterior, 'Basic Exterior Wash',      'Hand wash, rinse, and dry. Wheel clean included.',              45,  25.00, true),
    (prov1_id, cat_exterior, 'Premium Exterior Detail',  'Hand wash + clay bar + streak-free glass treatment.',           75,  55.00, true),
    (prov1_id, cat_wax,      'Express Wax & Shine',      'Single-stage machine polish and carnauba wax coat.',            60,  65.00, true)
  ON CONFLICT DO NOTHING;

  -- Provider 2: Shine Shield Detailing — interior focus
  INSERT INTO public.car_service_offerings (provider_id, category_id, name, description, duration_minutes, base_price, is_active)
  VALUES
    (prov2_id, cat_interior, 'Interior Deep Clean',      'Full vacuum, steam clean, leather/fabric treatment, odour removal.', 90,  80.00, true),
    (prov2_id, cat_full,     'Signature Full Detail',    'Complete interior + exterior — our most popular package.',         180, 150.00, true),
    (prov2_id, cat_exterior, 'Quick Exterior Wash',      'Fast and thorough exterior hand wash.',                             45,  30.00, true)
  ON CONFLICT DO NOTHING;

  -- Provider 3: Sparkle Auto Care — budget-friendly range
  INSERT INTO public.car_service_offerings (provider_id, category_id, name, description, duration_minutes, base_price, is_active)
  VALUES
    (prov3_id, cat_exterior, 'Economy Wash',             'Basic exterior hand wash — quick and affordable.',                 30,  18.00, true),
    (prov3_id, cat_interior, 'Interior Vacuum & Wipe',   'Full vacuum plus dashboard and console wipe-down.',               45,  35.00, true),
    (prov3_id, cat_engine,   'Engine Bay Clean',         'Degrease and rinse engine bay. Protectant applied.',              60,  50.00, true)
  ON CONFLICT DO NOTHING;

  -- Provider 4: Prestige Mobile Wash — luxury / premium
  INSERT INTO public.car_service_offerings (provider_id, category_id, name, description, duration_minutes, base_price, is_active)
  VALUES
    (prov4_id, cat_full,     'Prestige Full Detail',     'The works — paint decontamination, interior restoration, wax.',  240, 220.00, true),
    (prov4_id, cat_wax,      'Ceramic Coating Prep',     'Paint correction + ceramic coat application (1 layer).',         300, 350.00, true),
    (prov4_id, cat_interior, 'Luxury Interior Restore',  'Leather conditioning, deep steam, headliner clean.',             120, 120.00, true)
  ON CONFLICT DO NOTHING;

  -- Provider 5: Crystal Clear Detail — wax specialists
  INSERT INTO public.car_service_offerings (provider_id, category_id, name, description, duration_minutes, base_price, is_active)
  VALUES
    (prov5_id, cat_wax,      'Single-Stage Polish',      'Machine polish removes light swirls and oxidation.',             90,  85.00, true),
    (prov5_id, cat_wax,      'Two-Stage Paint Correction','Heavy correction + finishing polish for mirror shine.',          180, 160.00, true),
    (prov5_id, cat_exterior, 'Wash & Wax Combo',         'Hand wash followed by hand-applied carnauba wax.',               75,  60.00, true)
  ON CONFLICT DO NOTHING;

  -- Provider 6: Elite Shine Auto — full-service
  INSERT INTO public.car_service_offerings (provider_id, category_id, name, description, duration_minutes, base_price, is_active)
  VALUES
    (prov6_id, cat_exterior, 'Standard Wash',            'Thorough exterior wash with tyre shine.',                        45,  28.00, true),
    (prov6_id, cat_full,     'Elite Full Valet',         'Complete inside and out — our family favourite.',               180, 140.00, true),
    (prov6_id, cat_engine,   'Engine Detail',            'Professional engine clean with protectant spray.',              60,  55.00, true),
    (prov6_id, cat_interior, 'Interior Express Detail',  'Vacuum, wipe, glass clean, fresh scent.',                       60,  45.00, true)
  ON CONFLICT DO NOTHING;

  -- Provider 7: Rapid Wash Pro — eco-friendly
  INSERT INTO public.car_service_offerings (provider_id, category_id, name, description, duration_minutes, base_price, is_active)
  VALUES
    (prov7_id, cat_exterior, 'Waterless Eco Wash',       'Eco-friendly waterless wash — safe on paint, zero runoff.',      30,  22.00, true),
    (prov7_id, cat_exterior, 'Waterless Wash & Detail',  'Waterless wash + interior wipe + tyre dressing.',               50,  40.00, true),
    (prov7_id, cat_wax,      'Quick Spray Wax',          'Spray sealant applied after waterless wash — 30-day protection.',40,  45.00, true)
  ON CONFLICT DO NOTHING;

  -- ── 5. Weekly availability (Mon–Sat, 8am–6pm) ───────────────────────────
  -- Day 0=Sun, 1=Mon, 2=Tue, 3=Wed, 4=Thu, 5=Fri, 6=Sat

  INSERT INTO public.car_service_provider_availability
    (provider_id, day_of_week, start_time, end_time, is_active)
  SELECT * FROM (VALUES
    -- Provider 1
    (prov1_id, 1, '08:00'::time, '18:00'::time, true),
    (prov1_id, 2, '08:00'::time, '18:00'::time, true),
    (prov1_id, 3, '08:00'::time, '18:00'::time, true),
    (prov1_id, 4, '08:00'::time, '18:00'::time, true),
    (prov1_id, 5, '08:00'::time, '18:00'::time, true),
    (prov1_id, 6, '09:00'::time, '14:00'::time, true),
    -- Provider 2
    (prov2_id, 1, '09:00'::time, '17:00'::time, true),
    (prov2_id, 2, '09:00'::time, '17:00'::time, true),
    (prov2_id, 3, '09:00'::time, '17:00'::time, true),
    (prov2_id, 4, '09:00'::time, '17:00'::time, true),
    (prov2_id, 5, '09:00'::time, '17:00'::time, true),
    (prov2_id, 6, '09:00'::time, '13:00'::time, true),
    -- Provider 3
    (prov3_id, 1, '07:00'::time, '19:00'::time, true),
    (prov3_id, 2, '07:00'::time, '19:00'::time, true),
    (prov3_id, 3, '07:00'::time, '19:00'::time, true),
    (prov3_id, 4, '07:00'::time, '19:00'::time, true),
    (prov3_id, 5, '07:00'::time, '19:00'::time, true),
    (prov3_id, 6, '08:00'::time, '16:00'::time, true),
    (prov3_id, 0, '10:00'::time, '14:00'::time, true),
    -- Provider 4 — weekdays only, premium hours
    (prov4_id, 1, '09:00'::time, '17:00'::time, true),
    (prov4_id, 2, '09:00'::time, '17:00'::time, true),
    (prov4_id, 3, '09:00'::time, '17:00'::time, true),
    (prov4_id, 4, '09:00'::time, '17:00'::time, true),
    (prov4_id, 5, '09:00'::time, '17:00'::time, true),
    -- Provider 5
    (prov5_id, 1, '08:00'::time, '18:00'::time, true),
    (prov5_id, 2, '08:00'::time, '18:00'::time, true),
    (prov5_id, 3, '08:00'::time, '18:00'::time, true),
    (prov5_id, 4, '08:00'::time, '18:00'::time, true),
    (prov5_id, 5, '08:00'::time, '18:00'::time, true),
    (prov5_id, 6, '09:00'::time, '15:00'::time, true),
    -- Provider 6
    (prov6_id, 1, '08:00'::time, '17:00'::time, true),
    (prov6_id, 2, '08:00'::time, '17:00'::time, true),
    (prov6_id, 3, '08:00'::time, '17:00'::time, true),
    (prov6_id, 4, '08:00'::time, '17:00'::time, true),
    (prov6_id, 5, '08:00'::time, '17:00'::time, true),
    (prov6_id, 6, '09:00'::time, '14:00'::time, true),
    (prov6_id, 0, '10:00'::time, '13:00'::time, true),
    -- Provider 7 — all 7 days (eco-friendly, flexible hours)
    (prov7_id, 0, '09:00'::time, '16:00'::time, true),
    (prov7_id, 1, '07:00'::time, '18:00'::time, true),
    (prov7_id, 2, '07:00'::time, '18:00'::time, true),
    (prov7_id, 3, '07:00'::time, '18:00'::time, true),
    (prov7_id, 4, '07:00'::time, '18:00'::time, true),
    (prov7_id, 5, '07:00'::time, '18:00'::time, true),
    (prov7_id, 6, '08:00'::time, '15:00'::time, true)
  ) AS t(provider_id, day_of_week, start_time, end_time, is_active)
  ON CONFLICT DO NOTHING;

  RAISE NOTICE '7Dash: Seeded 7 car service providers successfully.';
END $$;

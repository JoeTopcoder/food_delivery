-- =============================================================================
-- LAUNDRY MODULE — Seed Data (4 sample providers)
-- Run AFTER the main migration: 20260529_laundry_module.sql
--
-- The user_id below uses the first admin user in your system.
-- If you want each provider to have its own login, create user accounts first
-- and replace the subquery with the actual UUID.
-- =============================================================================

do $$
declare
  admin_uid uuid;
  p1_id     uuid := '11111111-1111-1111-1111-000000000001';
  p2_id     uuid := '11111111-1111-1111-1111-000000000002';
  p3_id     uuid := '11111111-1111-1111-1111-000000000003';
  p4_id     uuid := '11111111-1111-1111-1111-000000000004';
begin
  -- Use the first admin user as the owner of these demo providers
  select id into admin_uid from public.users where role = 'admin' limit 1;

  if admin_uid is null then
    raise notice 'No admin user found — skipping laundry seed.';
    return;
  end if;

  -- ── Provider 1: FreshWave Laundry ─────────────────────────────────────────
  insert into laundry_providers (
    id, user_id, business_name, description,
    address, latitude, longitude,
    pickup_radius_km, status, is_active, is_verified,
    rating, review_count, commission_rate,
    operating_hours
  ) values (
    p1_id, admin_uid,
    'FreshWave Laundry',
    'Premium wash & fold service with same-day express options. We handle everything from everyday clothes to delicate fabrics with care.',
    '14 Harbour Drive, George Town, Cayman Islands',
    19.2950, -81.3810,
    15, 'active', true, true,
    4.8, 127, 0.15,
    '{"mon":{"open":"07:00","close":"20:00"},"tue":{"open":"07:00","close":"20:00"},"wed":{"open":"07:00","close":"20:00"},"thu":{"open":"07:00","close":"20:00"},"fri":{"open":"07:00","close":"21:00"},"sat":{"open":"08:00","close":"18:00"},"sun":{"open":"09:00","close":"15:00"}}'::jsonb
  ) on conflict (id) do nothing;

  -- ── Provider 2: SpinCycle Pro ─────────────────────────────────────────────
  insert into laundry_providers (
    id, user_id, business_name, description,
    address, latitude, longitude,
    pickup_radius_km, status, is_active, is_verified,
    rating, review_count, commission_rate,
    operating_hours
  ) values (
    p2_id, admin_uid,
    'SpinCycle Pro',
    'Industrial-grade cleaning for homes and businesses. Specialising in bedding, uniforms and bulk laundry at competitive rates.',
    '8 Eastern Avenue, Bodden Town, Cayman Islands',
    19.2840, -81.2560,
    20, 'active', true, true,
    4.5, 89, 0.15,
    '{"mon":{"open":"06:00","close":"22:00"},"tue":{"open":"06:00","close":"22:00"},"wed":{"open":"06:00","close":"22:00"},"thu":{"open":"06:00","close":"22:00"},"fri":{"open":"06:00","close":"22:00"},"sat":{"open":"07:00","close":"20:00"},"sun":{"open":"08:00","close":"17:00"}}'::jsonb
  ) on conflict (id) do nothing;

  -- ── Provider 3: Crystal Clean ─────────────────────────────────────────────
  insert into laundry_providers (
    id, user_id, business_name, description,
    address, latitude, longitude,
    pickup_radius_km, status, is_active, is_verified,
    rating, review_count, commission_rate,
    operating_hours
  ) values (
    p3_id, admin_uid,
    'Crystal Clean',
    'Eco-friendly dry cleaning and delicates specialist. All garments treated with biodegradable solvents. Suits, gowns and luxury items welcome.',
    '22 West Bay Road, Seven Mile Beach, Cayman Islands',
    19.3320, -81.3900,
    12, 'active', true, true,
    4.9, 214, 0.15,
    '{"mon":{"open":"08:00","close":"19:00"},"tue":{"open":"08:00","close":"19:00"},"wed":{"open":"08:00","close":"19:00"},"thu":{"open":"08:00","close":"19:00"},"fri":{"open":"08:00","close":"19:00"},"sat":{"open":"09:00","close":"17:00"},"sun":null}'::jsonb
  ) on conflict (id) do nothing;

  -- ── Provider 4: QuickSuds Express ────────────────────────────────────────
  insert into laundry_providers (
    id, user_id, business_name, description,
    address, latitude, longitude,
    pickup_radius_km, status, is_active, is_verified,
    rating, review_count, commission_rate,
    operating_hours
  ) values (
    p4_id, admin_uid,
    'QuickSuds Express',
    '2-hour express turnaround for busy professionals. Wash, dry and fold delivered back within hours. Open 7 days.',
    '5 Shedden Road, George Town, Cayman Islands',
    19.2890, -81.3780,
    10, 'active', true, true,
    4.6, 73, 0.15,
    '{"mon":{"open":"06:00","close":"23:00"},"tue":{"open":"06:00","close":"23:00"},"wed":{"open":"06:00","close":"23:00"},"thu":{"open":"06:00","close":"23:00"},"fri":{"open":"06:00","close":"23:00"},"sat":{"open":"07:00","close":"22:00"},"sun":{"open":"08:00","close":"20:00"}}'::jsonb
  ) on conflict (id) do nothing;

  -- ── Pricing for each provider ─────────────────────────────────────────────
  insert into laundry_pricing (provider_id, pickup_fee, delivery_fee, min_order_fee)
  values
    (p1_id, 2.50, 2.50, 10.00),
    (p2_id, 0.00, 0.00, 15.00),
    (p3_id, 3.00, 3.00, 20.00),
    (p4_id, 5.00, 5.00, 12.00)
  on conflict (provider_id) do nothing;

  -- ── Services for each provider ────────────────────────────────────────────
  insert into laundry_provider_services (
    provider_id, service_id, is_available,
    price_per_kg, minimum_order_fee, express_fee, ironing_fee, dry_cleaning_fee, estimated_hours
  )
  select
    ps.provider_id,
    ls.id,
    true,
    ps.ppkg,
    ps.min_fee,
    ps.express,
    ps.ironing,
    ps.dry_clean,
    ps.hours
  from (values
    -- FreshWave
    (p1_id, 'Wash & Fold',     3.50, 10.00,  5.00, 2.00,  0.00, 24),
    (p1_id, 'Wash Only',       2.50,  8.00,  4.00, 0.00,  0.00, 12),
    (p1_id, 'Ironing',         2.00,  8.00,  3.00, 3.00,  0.00, 6),
    (p1_id, 'Express Laundry', 5.00, 12.00,  0.00, 0.00,  0.00, 2),
    (p1_id, 'Bedding Cleaning',4.00, 15.00,  5.00, 2.00,  0.00, 24),
    -- SpinCycle
    (p2_id, 'Wash & Fold',     2.80, 12.00,  4.00, 1.50,  0.00, 24),
    (p2_id, 'Dry Only',        1.50,  6.00,  3.00, 0.00,  0.00, 4),
    (p2_id, 'Uniform Cleaning',3.00, 10.00,  4.00, 2.00,  0.00, 12),
    (p2_id, 'Bedding Cleaning',3.50, 15.00,  5.00, 2.00,  0.00, 24),
    -- Crystal Clean
    (p3_id, 'Dry Cleaning',    0.00, 15.00,  0.00, 0.00, 12.00, 48),
    (p3_id, 'Delicates Cleaning',4.50, 20.00,0.00, 0.00,  0.00, 36),
    (p3_id, 'Wash & Fold',     4.00, 12.00,  6.00, 3.00,  0.00, 24),
    (p3_id, 'Ironing',         3.00, 10.00,  4.00, 4.00,  0.00, 8),
    -- QuickSuds
    (p4_id, 'Wash & Fold',     4.00, 10.00,  0.00, 2.50,  0.00, 2),
    (p4_id, 'Express Laundry', 6.00, 12.00,  0.00, 0.00,  0.00, 2),
    (p4_id, 'Wash Only',       3.00,  8.00,  0.00, 0.00,  0.00, 2),
    (p4_id, 'Dry Only',        2.00,  6.00,  0.00, 0.00,  0.00, 1)
  ) as ps(provider_id, svc_name, ppkg, min_fee, express, ironing, dry_clean, hours)
  join laundry_services ls on ls.name = ps.svc_name
  on conflict (provider_id, service_id) do nothing;

  raise notice 'Seeded 4 laundry providers successfully.';
end $$;

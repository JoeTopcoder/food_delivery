-- Seed the Applizone Central grocery store so the customer grocery section
-- has at least one verified grocery store to display. The existing
-- seed_grocery_200.sql inserts 200 products referencing this exact UUID,
-- but no matching row was ever created in restaurants.

DO $$
DECLARE
  grocery_id   CONSTANT UUID := 'b2f105d1-b5dc-426b-8a04-56204ff8a490';
  owner_uuid   UUID;
BEGIN
  -- Pick any existing user to own the system grocery store.
  -- Prefer admin, then restaurant, then the first user we can find.
  SELECT id INTO owner_uuid FROM public.users WHERE role = 'admin' LIMIT 1;
  IF owner_uuid IS NULL THEN
    SELECT id INTO owner_uuid FROM public.users WHERE role = 'restaurant' LIMIT 1;
  END IF;
  IF owner_uuid IS NULL THEN
    SELECT id INTO owner_uuid FROM public.users LIMIT 1;
  END IF;

  -- If the users table is empty, create a system owner so the foreign key holds.
  IF owner_uuid IS NULL THEN
    owner_uuid := gen_random_uuid();
    INSERT INTO public.users (id, email, name, role, is_active)
    VALUES (owner_uuid, 'grocery-system@mealhub.local', 'Grocery System', 'admin', true)
    ON CONFLICT (id) DO NOTHING;
  END IF;

  -- Upsert the grocery store.
  INSERT INTO public.restaurants (
    id, owner_id, name, description, image_url,
    phone, email, address, latitude, longitude,
    cuisine_type, rating, review_count, delivery_fee,
    estimated_delivery_time, minimum_order_amount, is_open,
    opening_time, closing_time, tags, is_verified, store_type
  ) VALUES (
    grocery_id,
    owner_uuid,
    'Applizone Central',
    'Your one-stop grocery store — fresh produce, pantry staples, and everyday essentials delivered fast.',
    'https://images.unsplash.com/photo-1534723452862-4c874018d66d?w=800',
    '+1 345 555 0100',
    'central@applizone.local',
    'Cayman Islands',
    19.3133,
    -81.2546,
    'Grocery',
    4.7,
    128,
    2.99,
    30,
    0,
    true,
    '07:00',
    '22:00',
    ARRAY['grocery','essentials','fresh'],
    true,
    'grocery'
  )
  ON CONFLICT (id) DO UPDATE SET
    store_type   = EXCLUDED.store_type,
    is_verified  = true,
    is_open      = true,
    name         = EXCLUDED.name,
    description  = EXCLUDED.description,
    image_url    = EXCLUDED.image_url,
    updated_at   = NOW();
END $$;

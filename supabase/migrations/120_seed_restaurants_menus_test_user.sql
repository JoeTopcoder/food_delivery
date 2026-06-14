-- Migration 120: Seed restaurants, menu items, and test customer user
-- ============================================================

DO $$
DECLARE
  -- Fixed UUIDs for restaurant owners (public.users only, no auth entry needed)
  v_owner1 UUID := 'feed0001-0000-0000-0000-000000000001';
  v_owner2 UUID := 'feed0001-0000-0000-0000-000000000002';
  v_owner3 UUID := 'feed0001-0000-0000-0000-000000000003';
  v_owner4 UUID := 'feed0001-0000-0000-0000-000000000004';
  v_owner5 UUID := 'feed0001-0000-0000-0000-000000000005';

  -- Fixed UUID for test customer (also gets an auth.users entry)
  v_test_id UUID := 'decade00-0000-0000-0000-000000000001';

  -- Restaurant IDs
  v_r1 UUID := 'cafe0001-0000-0000-0000-000000000001';
  v_r2 UUID := 'cafe0001-0000-0000-0000-000000000002';
  v_r3 UUID := 'cafe0001-0000-0000-0000-000000000003';
  v_r4 UUID := 'cafe0001-0000-0000-0000-000000000004';
  v_r5 UUID := 'cafe0001-0000-0000-0000-000000000005';

  v_operating_hours JSONB := '{
    "monday":    {"open": "10:00", "close": "22:00", "is_open": true},
    "tuesday":   {"open": "10:00", "close": "22:00", "is_open": true},
    "wednesday": {"open": "10:00", "close": "22:00", "is_open": true},
    "thursday":  {"open": "10:00", "close": "22:00", "is_open": true},
    "friday":    {"open": "10:00", "close": "23:00", "is_open": true},
    "saturday":  {"open": "11:00", "close": "23:00", "is_open": true},
    "sunday":    {"open": "11:00", "close": "21:00", "is_open": true}
  }'::JSONB;

BEGIN

  -- ================================================================
  -- 1. TEST AUTH USER (trigger will auto-create public.users entry)
  -- ================================================================
  INSERT INTO auth.users (
    id, instance_id, aud, role,
    email, encrypted_password,
    email_confirmed_at, created_at, updated_at,
    raw_app_meta_data, raw_user_meta_data, is_super_admin
  ) VALUES (
    v_test_id,
    '00000000-0000-0000-0000-000000000000',
    'authenticated', 'authenticated',
    'testcustomer@mealhub.com',
    crypt('Test1234!', gen_salt('bf', 10)),
    NOW(), NOW(), NOW(),
    '{"provider":"email","providers":["email"]}',
    '{"name":"Test Customer","role":"customer"}',
    false
  ) ON CONFLICT (id) DO NOTHING;

  -- Fix role to 'customer' (trigger may insert 'user')
  UPDATE public.users
  SET role = 'customer',
      phone = '+1 345-555-0100',
      address = 'George Town, Grand Cayman, KY1-1001',
      latitude = 19.2869,
      longitude = -81.3674,
      updated_at = NOW()
  WHERE id = v_test_id;

  -- ================================================================
  -- 2. RESTAURANT OWNER USERS (public.users only)
  -- ================================================================
  INSERT INTO public.users (id, email, name, role, is_active, created_at, updated_at) VALUES
    (v_owner1, 'owner.burgers@mealhub.com',  'Marcus Reid',    'restaurant', true, NOW(), NOW()),
    (v_owner2, 'owner.pizza@mealhub.com',    'Sofia Esposito', 'restaurant', true, NOW(), NOW()),
    (v_owner3, 'owner.spice@mealhub.com',    'Priya Sharma',   'restaurant', true, NOW(), NOW()),
    (v_owner4, 'owner.sushi@mealhub.com',    'Kenji Tanaka',   'restaurant', true, NOW(), NOW()),
    (v_owner5, 'owner.tacos@mealhub.com',    'Diego Morales',  'restaurant', true, NOW(), NOW())
  ON CONFLICT (id) DO NOTHING;

  -- ================================================================
  -- 3. RESTAURANTS
  -- ================================================================
  INSERT INTO public.restaurants (
    id, owner_id, name, description, image_url,
    phone, email, address, latitude, longitude,
    cuisine_type, rating, review_count,
    delivery_fee, estimated_delivery_time,
    is_open, is_verified, status,
    commission_rate, service_fee, operating_hours,
    opening_time, closing_time,
    tags, created_at, updated_at
  ) VALUES

  -- 1. The Burger Joint
  (v_r1, v_owner1,
   'The Burger Joint',
   'Juicy handcrafted smash burgers made with premium Cayman beef. A local favourite since 2018.',
   'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=800&q=80',
   '+1 345-555-0201', 'burgers@theburgerjoint.ky',
   '94 West Bay Road, Seven Mile Beach, Grand Cayman, KY1-1202',
   19.3254, -81.3924,
   'Fast Food', 4.7, 142,
   3.00, 25,
   true, true, 'approved',
   0.15, 1.50, v_operating_hours,
   '10:00', '23:00',
   ARRAY['burger','fast food','american','smash burger','wings'],
   NOW(), NOW()),

  -- 2. Pizza Palace
  (v_r2, v_owner2,
   'Pizza Palace',
   'Authentic wood-fired Neapolitan pizza with imported Italian ingredients. Dine-in, takeaway & delivery.',
   'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=800&q=80',
   '+1 345-555-0202', 'hello@pizzapalace.ky',
   '15 Eastern Avenue, George Town, Grand Cayman, KY1-1005',
   19.2877, -81.3753,
   'Pizza', 4.5, 98,
   3.00, 30,
   true, true, 'approved',
   0.15, 1.50, v_operating_hours,
   '11:00', '22:30',
   ARRAY['pizza','italian','pasta','wood-fired','calzone'],
   NOW(), NOW()),

  -- 3. Spice Garden
  (v_r3, v_owner3,
   'Spice Garden',
   'Authentic North Indian cuisine featuring aromatic curries, fresh-baked naan and tandoori specialties.',
   'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=800&q=80',
   '+1 345-555-0203', 'info@spicegarden.ky',
   '7 Shedden Road, George Town, Grand Cayman, KY1-1001',
   19.2892, -81.3802,
   'Indian', 4.6, 87,
   3.00, 35,
   true, true, 'approved',
   0.15, 1.50, v_operating_hours,
   '11:30', '22:00',
   ARRAY['indian','curry','halal','vegetarian','biryani'],
   NOW(), NOW()),

  -- 4. Sushi World
  (v_r4, v_owner4,
   'Sushi World',
   'Premium fresh sushi, sashimi and Japanese cuisine. Locally sourced seafood. Omakase available on request.',
   'https://images.unsplash.com/photo-1553621042-f6e147245754?w=800&q=80',
   '+1 345-555-0204', 'reservations@sushiworld.ky',
   '32 Harbour Drive, George Town, Grand Cayman, KY1-1003',
   19.2905, -81.3855,
   'Japanese', 4.8, 211,
   3.00, 40,
   true, true, 'approved',
   0.15, 1.50, v_operating_hours,
   '12:00', '22:00',
   ARRAY['sushi','japanese','seafood','sashimi','ramen'],
   NOW(), NOW()),

  -- 5. Taco Fiesta
  (v_r5, v_owner5,
   'Taco Fiesta',
   'Vibrant Mexican street food — tacos, burritos, and fresh-made guacamole. Happy hour Mon–Fri 4–7 pm.',
   'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=800&q=80',
   '+1 345-555-0205', 'hola@tacofiesta.ky',
   '56 North Church Street, George Town, Grand Cayman, KY1-1103',
   19.2918, -81.3741,
   'Mexican', 4.4, 76,
   3.00, 25,
   true, true, 'approved',
   0.15, 1.50, v_operating_hours,
   '10:00', '22:00',
   ARRAY['mexican','tacos','burritos','nachos','latin'],
   NOW(), NOW())

  ON CONFLICT (id) DO NOTHING;

  -- ================================================================
  -- 4. MENU ITEMS — The Burger Joint
  -- ================================================================
  INSERT INTO public.menus (restaurant_id, name, description, price, category, image_url, is_available, preparation_time, tags) VALUES

  (v_r1, 'Classic Smash Burger',
   'Double smash patty, American cheese, pickles, onions, special sauce on a brioche bun.',
   14.99, 'Burgers',
   'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400&q=80',
   true, 12, ARRAY['bestseller','beef','classic']),

  (v_r1, 'Bacon Double Cheeseburger',
   'Double beef patties, crispy bacon, double cheddar, lettuce, tomato, jalapeño aioli.',
   17.99, 'Burgers',
   'https://images.unsplash.com/photo-1553979459-d2229ba7433b?w=400&q=80',
   true, 14, ARRAY['bacon','cheese','spicy']),

  (v_r1, 'Crispy Chicken Sandwich',
   'Buttermilk-fried chicken breast, coleslaw, pickles, honey mustard on a toasted bun.',
   13.99, 'Burgers',
   'https://images.unsplash.com/photo-1606755962773-d324e0a13086?w=400&q=80',
   true, 14, ARRAY['chicken','crispy']),

  (v_r1, 'Veggie Smash Burger',
   'House-made black bean & quinoa patty, avocado, tomato, lettuce, vegan mayo.',
   12.99, 'Burgers',
   NULL,
   true, 12, ARRAY['vegetarian','vegan','healthy']),

  (v_r1, 'Loaded Cheese Fries',
   'Crispy seasoned fries topped with cheddar sauce, bacon bits and jalapeños.',
   8.99, 'Sides',
   'https://images.unsplash.com/photo-1573080496219-bb080dd4f877?w=400&q=80',
   true, 8, ARRAY['fries','cheesy','sharing']),

  (v_r1, 'Onion Rings',
   'Beer-battered onion rings served with smoky BBQ dipping sauce.',
   6.99, 'Sides',
   NULL,
   true, 8, ARRAY['vegetarian','side']),

  (v_r1, 'Buffalo Wings (8pc)',
   'Crispy chicken wings tossed in hot buffalo sauce. Served with blue cheese dip.',
   14.99, 'Starters',
   'https://images.unsplash.com/photo-1527477396000-e27163b481c2?w=400&q=80',
   true, 15, ARRAY['wings','spicy','sharing']),

  (v_r1, 'Chocolate Milkshake',
   'Thick-blended premium chocolate ice cream milkshake topped with whipped cream.',
   7.50, 'Drinks',
   NULL,
   true, 5, ARRAY['cold','dessert','sweet']),

  (v_r1, 'Fresh Lemonade',
   'Hand-squeezed lemonade with mint, served over ice.',
   4.50, 'Drinks',
   NULL,
   true, 3, ARRAY['cold','fresh','non-alcoholic']);

  -- ================================================================
  -- 5. MENU ITEMS — Pizza Palace
  -- ================================================================
  INSERT INTO public.menus (restaurant_id, name, description, price, category, image_url, is_available, preparation_time, tags) VALUES

  (v_r2, 'Margherita Pizza',
   'San Marzano tomato sauce, fresh mozzarella di bufala, basil, extra virgin olive oil. (12")',
   15.99, 'Pizza',
   'https://images.unsplash.com/photo-1574071318508-1cdbab80d002?w=400&q=80',
   true, 18, ARRAY['vegetarian','classic','bestseller']),

  (v_r2, 'Pepperoni Pizza',
   'Generous layer of premium pepperoni, mozzarella, tomato sauce. (12")',
   17.99, 'Pizza',
   'https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=400&q=80',
   true, 18, ARRAY['meat','bestseller']),

  (v_r2, 'BBQ Chicken Pizza',
   'Smoky BBQ base, grilled chicken, red onions, mozzarella, fresh coriander. (12")',
   18.99, 'Pizza',
   NULL,
   true, 20, ARRAY['chicken','bbq']),

  (v_r2, 'Four Cheese Pizza',
   'Mozzarella, gorgonzola, parmesan and ricotta on a white cream base. (12")',
   16.99, 'Pizza',
   NULL,
   true, 18, ARRAY['vegetarian','cheese','premium']),

  (v_r2, 'Pasta Carbonara',
   'Al dente spaghetti, guanciale, egg yolk, pecorino romano, black pepper.',
   14.99, 'Pasta',
   'https://images.unsplash.com/photo-1612874742237-6526221588e3?w=400&q=80',
   true, 15, ARRAY['pasta','cream','italian']),

  (v_r2, 'Penne Arrabbiata',
   'Penne pasta in spicy San Marzano tomato sauce with garlic and chilli.',
   12.99, 'Pasta',
   NULL,
   true, 15, ARRAY['pasta','spicy','vegan']),

  (v_r2, 'Caesar Salad',
   'Romaine lettuce, croutons, parmesan, anchovies, house Caesar dressing.',
   9.99, 'Salads',
   NULL,
   true, 8, ARRAY['salad','healthy','starter']),

  (v_r2, 'Garlic Bread',
   'Wood-fired ciabatta with garlic butter and fresh parsley. (4 slices)',
   5.99, 'Sides',
   NULL,
   true, 8, ARRAY['vegetarian','bread','side']),

  (v_r2, 'Tiramisu',
   'Classic Italian tiramisu — mascarpone, espresso-soaked ladyfingers, cocoa dust.',
   7.99, 'Desserts',
   'https://images.unsplash.com/photo-1571877227200-a0d98ea607e9?w=400&q=80',
   true, 5, ARRAY['dessert','italian','sweet']);

  -- ================================================================
  -- 6. MENU ITEMS — Spice Garden
  -- ================================================================
  INSERT INTO public.menus (restaurant_id, name, description, price, category, image_url, is_available, preparation_time, tags) VALUES

  (v_r3, 'Chicken Tikka Masala',
   'Tender grilled chicken in a rich, creamy tomato-cashew sauce. Served with basmati rice.',
   16.99, 'Mains',
   'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=400&q=80',
   true, 20, ARRAY['bestseller','chicken','creamy']),

  (v_r3, 'Butter Chicken',
   'Classic murgh makhani — slow-cooked chicken in a velvety buttery tomato gravy.',
   15.99, 'Mains',
   NULL,
   true, 20, ARRAY['chicken','mild','bestseller']),

  (v_r3, 'Lamb Biryani',
   'Fragrant basmati rice layered with slow-cooked spiced lamb, saffron and fried onions.',
   18.99, 'Mains',
   'https://images.unsplash.com/photo-1563379091339-03b21ab4a4f8?w=400&q=80',
   true, 25, ARRAY['lamb','rice','aromatic']),

  (v_r3, 'Dal Makhani',
   'Slow-cooked black lentils and kidney beans in a smoky, buttery tomato sauce.',
   13.99, 'Mains',
   NULL,
   true, 20, ARRAY['vegetarian','vegan','lentils']),

  (v_r3, 'Paneer Tikka',
   'Marinated Indian cottage cheese grilled in the tandoor. Served with mint chutney.',
   13.99, 'Starters',
   NULL,
   true, 15, ARRAY['vegetarian','paneer','starter']),

  (v_r3, 'Samosa Platter (4pc)',
   'Crispy pastry filled with spiced potato and peas. Served with tamarind & mint chutneys.',
   8.99, 'Starters',
   'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=400&q=80',
   true, 10, ARRAY['vegetarian','starter','sharing']),

  (v_r3, 'Garlic Naan',
   'Soft, buttery naan bread brushed with garlic butter, baked in a clay tandoor.',
   3.99, 'Breads',
   NULL,
   true, 8, ARRAY['vegetarian','bread','side']),

  (v_r3, 'Mango Lassi',
   'Chilled yoghurt drink blended with fresh Alphonso mango and a pinch of cardamom.',
   5.99, 'Drinks',
   NULL,
   true, 3, ARRAY['cold','sweet','non-alcoholic']),

  (v_r3, 'Gulab Jamun (3pc)',
   'Soft milk-solid dumplings soaked in rose and cardamom sugar syrup.',
   6.99, 'Desserts',
   NULL,
   true, 5, ARRAY['dessert','sweet','traditional']);

  -- ================================================================
  -- 7. MENU ITEMS — Sushi World
  -- ================================================================
  INSERT INTO public.menus (restaurant_id, name, description, price, category, image_url, is_available, preparation_time, tags) VALUES

  (v_r4, 'California Roll (8pc)',
   'Crab stick, avocado and cucumber inside-out roll topped with sesame seeds.',
   12.99, 'Rolls',
   'https://images.unsplash.com/photo-1553621042-f6e147245754?w=400&q=80',
   true, 15, ARRAY['classic','beginner-friendly','bestseller']),

  (v_r4, 'Salmon Sashimi (6pc)',
   'Premium fresh Atlantic salmon, hand-sliced. Served with wasabi, pickled ginger and soy.',
   16.99, 'Sashimi',
   'https://images.unsplash.com/photo-1617196034183-421b4040ed20?w=400&q=80',
   true, 12, ARRAY['raw','gluten-free','premium']),

  (v_r4, 'Spicy Tuna Roll (8pc)',
   'Sushi-grade tuna with spicy sriracha mayo, cucumber, and crispy tempura flakes.',
   14.99, 'Rolls',
   NULL,
   true, 15, ARRAY['spicy','tuna','popular']),

  (v_r4, 'Dragon Roll (8pc)',
   'Shrimp tempura inside, avocado on top with eel sauce and sesame. A signature creation.',
   15.99, 'Rolls',
   NULL,
   true, 18, ARRAY['premium','avocado','signature']),

  (v_r4, 'Rainbow Roll (8pc)',
   'California roll topped with alternating slices of salmon, tuna, and avocado.',
   17.99, 'Rolls',
   NULL,
   true, 18, ARRAY['premium','colourful','sharing']),

  (v_r4, 'Chicken Teriyaki Bowl',
   'Grilled teriyaki chicken over steamed Japanese rice, broccoli, with sesame and spring onion.',
   18.99, 'Mains',
   NULL,
   true, 18, ARRAY['cooked','chicken','bowl']),

  (v_r4, 'Miso Soup',
   'Traditional dashi-based miso broth with silken tofu, wakame seaweed and spring onion.',
   4.99, 'Soups',
   NULL,
   true, 5, ARRAY['vegan','soup','warm']),

  (v_r4, 'Edamame',
   'Steamed salted soybean pods. Light and healthy starter.',
   5.99, 'Starters',
   NULL,
   true, 5, ARRAY['vegan','healthy','starter']),

  (v_r4, 'Green Tea Ice Cream',
   'Creamy matcha gelato made with ceremonial-grade Japanese green tea.',
   6.99, 'Desserts',
   NULL,
   true, 3, ARRAY['dessert','matcha','sweet']);

  -- ================================================================
  -- 8. MENU ITEMS — Taco Fiesta
  -- ================================================================
  INSERT INTO public.menus (restaurant_id, name, description, price, category, image_url, is_available, preparation_time, tags) VALUES

  (v_r5, 'Beef Tacos (3pc)',
   'Seasoned ground beef, shredded lettuce, pico de gallo, cheddar and sour cream in corn tortillas.',
   12.99, 'Tacos',
   'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=400&q=80',
   true, 12, ARRAY['beef','bestseller','classic']),

  (v_r5, 'Shrimp Tacos (3pc)',
   'Crispy battered shrimp, mango slaw, avocado crema and chipotle sauce in flour tortillas.',
   14.99, 'Tacos',
   NULL,
   true, 14, ARRAY['shrimp','seafood','popular']),

  (v_r5, 'Chicken Burrito',
   'Large flour tortilla filled with grilled chicken, cilantro rice, black beans, cheese and salsa.',
   13.99, 'Burritos',
   'https://images.unsplash.com/photo-1626700051175-6818013e1d4f?w=400&q=80',
   true, 14, ARRAY['chicken','filling','bestseller']),

  (v_r5, 'Veggie Burrito',
   'Grilled peppers and onions, black beans, cilantro rice, avocado, pico de gallo.',
   12.99, 'Burritos',
   NULL,
   true, 12, ARRAY['vegetarian','vegan','healthy']),

  (v_r5, 'Nachos Supreme',
   'Corn tortilla chips loaded with melted cheese, jalapeños, guacamole, sour cream and salsa.',
   11.99, 'Starters',
   'https://images.unsplash.com/photo-1513456852971-30c0b8199d4d?w=400&q=80',
   true, 10, ARRAY['vegetarian','sharing','snack']),

  (v_r5, 'Guacamole & Chips',
   'Fresh hand-mashed avocado with lime, coriander, red onion and tomato. Served with tortilla chips.',
   8.99, 'Starters',
   NULL,
   true, 8, ARRAY['vegetarian','vegan','fresh']),

  (v_r5, 'Chicken Quesadilla',
   'Grilled flour tortilla stuffed with spiced chicken, peppers, onions and melted Monterey Jack.',
   12.99, 'Mains',
   NULL,
   true, 12, ARRAY['chicken','cheesy','crispy']),

  (v_r5, 'Churros (4pc)',
   'Crispy fried dough sticks dusted in cinnamon sugar, served with warm chocolate dipping sauce.',
   6.99, 'Desserts',
   NULL,
   true, 8, ARRAY['dessert','sweet','sharing']),

  (v_r5, 'Horchata',
   'Traditional Mexican rice milk drink with cinnamon and vanilla, served over ice.',
   4.99, 'Drinks',
   NULL,
   true, 3, ARRAY['cold','traditional','non-alcoholic']);

END $$;

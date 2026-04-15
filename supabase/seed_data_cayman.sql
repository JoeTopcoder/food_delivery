-- ====================================================================
-- MEALHUB CAYMAN - SEED DATA
-- Cayman Islands restaurants with KYD pricing
-- Run this AFTER the main schema (complete_schema.sql) is created
-- ====================================================================

-- ====================================================================
-- 1. INSERT SAMPLE USERS (Cayman Islands)
-- ====================================================================
-- Customers
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('customer1@example.com', 'James Bodden', '3459491001', 'user', '15 South Church St, George Town', 19.2869, -81.3812, TRUE),
  ('customer2@example.com', 'Tanya Ebanks', '3459491002', 'user', '22 West Bay Rd, Seven Mile Beach', 19.3299, -81.3880, TRUE),
  ('customer3@example.com', 'Marcus Thompson', '3459491003', 'user', '8 Shamrock Rd, Prospect', 19.2785, -81.3650, TRUE),
  ('customer4@example.com', 'Alicia McLaughlin', '3459491004', 'user', '45 Eastern Ave, George Town', 19.2950, -81.3750, TRUE),
  ('customer5@example.com', 'Devon Rankine', '3459491005', 'user', '12 Walkers Rd, George Town', 19.3000, -81.3800, TRUE);

-- Restaurant Owners
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('owner1@example.com', 'Ricardo Ebanks', '3459492001', 'restaurant', 'George Town, Grand Cayman', 19.2869, -81.3812, TRUE),
  ('owner2@example.com', 'Sophia Campbell', '3459492002', 'restaurant', 'West Bay Road, Grand Cayman', 19.3299, -81.3880, TRUE),
  ('owner3@example.com', 'Brandon Connolly', '3459492003', 'restaurant', 'Camana Bay, Grand Cayman', 19.3250, -81.3790, TRUE),
  ('owner4@example.com', 'Natasha Rivers', '3459492004', 'restaurant', 'Seven Mile Beach, Grand Cayman', 19.3400, -81.3920, TRUE),
  ('owner5@example.com', 'Keith Watler', '3459492005', 'restaurant', 'Rum Point, Grand Cayman', 19.3590, -81.2730, TRUE),
  ('owner6@example.com', 'Crystal Hurlston', '3459492006', 'restaurant', 'East End, Grand Cayman', 19.3010, -81.1520, TRUE),
  ('owner7@example.com', 'Andre Jackson', '3459492007', 'restaurant', 'Bodden Town, Grand Cayman', 19.2830, -81.2520, TRUE),
  ('owner8@example.com', 'Lisa Powery', '3459492008', 'restaurant', 'Cayman Brac', 19.7180, -79.8020, TRUE),
  ('owner9@example.com', 'David McLean', '3459492009', 'restaurant', 'West Bay, Grand Cayman', 19.3650, -81.4050, TRUE),
  ('owner10@example.com', 'Maria Gonzalez', '3459492010', 'restaurant', 'George Town, Grand Cayman', 19.2900, -81.3830, TRUE);

-- Drivers
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('driver1@example.com', 'Adrian Bush', '3459493001', 'driver', 'George Town, Grand Cayman', 19.2870, -81.3810, TRUE),
  ('driver2@example.com', 'Kevin Scott', '3459493002', 'driver', 'West Bay Rd, Grand Cayman', 19.3300, -81.3880, TRUE),
  ('driver3@example.com', 'Shawn Forbes', '3459493003', 'driver', 'Bodden Town, Grand Cayman', 19.2830, -81.2520, TRUE),
  ('driver4@example.com', 'Darren Whittaker', '3459493004', 'driver', 'Prospect, Grand Cayman', 19.2790, -81.3650, TRUE);

-- Admin User
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('admin@example.com', 'Admin User', '3459490001', 'admin', '1 Elgin Ave, George Town, Grand Cayman', 19.2869, -81.3812, TRUE);

-- ====================================================================
-- 2. INSERT 30 CAYMAN ISLANDS RESTAURANTS
-- ====================================================================

-- ── George Town ───────────────────────────────────────────────────────
INSERT INTO public.restaurants (owner_id, name, description, phone, email, address, latitude, longitude, cuisine_type, rating, review_count, delivery_fee, estimated_delivery_time, is_open, opening_time, closing_time, is_verified) VALUES

-- 1. Guy Harvey's Island Grill
((SELECT id FROM public.users WHERE email='owner1@example.com'),
 'Guy Harvey''s Island Grill',
 'Fresh seafood and island-inspired dishes overlooking the waterfront',
 '3459461000',
 'guyharveys@example.com',
 '55 South Church St, George Town',
 19.2868, -81.3813,
 'Seafood',
 4.6, 312,
 5.00, 30,
 TRUE, '11:00', '22:00', TRUE),

-- 2. The Brasserie
((SELECT id FROM public.users WHERE email='owner1@example.com'),
 'The Brasserie',
 'Farm-to-table dining with Caribbean and European influences',
 '3459461001',
 'brasserie@example.com',
 '171 Elgin Ave, George Town',
 19.2920, -81.3780,
 'Caribbean Fusion',
 4.7, 285,
 5.00, 35,
 TRUE, '07:00', '22:00', TRUE),

-- 3. Bread & Chocolate
((SELECT id FROM public.users WHERE email='owner10@example.com'),
 'Bread & Chocolate',
 'Artisan bakery and cafe with fresh pastries and sandwiches',
 '3459461002',
 'breadchocolate@example.com',
 'Elgin Ave, George Town',
 19.2910, -81.3790,
 'Bakery & Cafe',
 4.5, 198,
 4.00, 25,
 TRUE, '06:30', '17:00', TRUE),

-- 4. Singh''s Roti Shop
((SELECT id FROM public.users WHERE email='owner10@example.com'),
 'Singh''s Roti Shop',
 'Authentic Caribbean roti and curry specialties',
 '3459461003',
 'singhs@example.com',
 'Eastern Ave, George Town',
 19.2940, -81.3760,
 'Caribbean',
 4.4, 420,
 4.00, 20,
 TRUE, '10:00', '21:00', TRUE),

-- 5. Casanova Restaurant
((SELECT id FROM public.users WHERE email='owner1@example.com'),
 'Casanova Restaurant',
 'Authentic Italian cuisine in an elegant waterfront setting',
 '3459461004',
 'casanova@example.com',
 '65 South Church St, George Town',
 19.2860, -81.3820,
 'Italian',
 4.5, 189,
 5.00, 35,
 TRUE, '11:30', '22:30', TRUE),

-- ── Camana Bay ───────────────────────────────────────────────────────

-- 6. Abacus
((SELECT id FROM public.users WHERE email='owner3@example.com'),
 'Abacus',
 'Contemporary farm-to-table dining in Camana Bay',
 '3456231150',
 'abacus@example.com',
 'The Crescent, Camana Bay',
 19.3255, -81.3785,
 'Modern American',
 4.6, 267,
 5.00, 30,
 TRUE, '11:30', '22:00', TRUE),

-- 7. Mizu Asian Bistro
((SELECT id FROM public.users WHERE email='owner3@example.com'),
 'Mizu Asian Bistro',
 'Japanese and Asian fusion cuisine with fresh sushi and sashimi',
 '3456231160',
 'mizu@example.com',
 'Camana Bay, Grand Cayman',
 19.3248, -81.3790,
 'Japanese',
 4.7, 345,
 5.00, 30,
 TRUE, '11:30', '22:00', TRUE),

-- 8. Tillie''s
((SELECT id FROM public.users WHERE email='owner3@example.com'),
 'Tillie''s',
 'Casual Caribbean and comfort food on the Camana Bay waterfront',
 '3456231170',
 'tillies@example.com',
 'Camana Bay Waterfront, Grand Cayman',
 19.3260, -81.3780,
 'Caribbean',
 4.3, 156,
 5.00, 25,
 TRUE, '11:00', '21:30', TRUE),

-- ── Seven Mile Beach ─────────────────────────────────────────────────

-- 9. Yoshi Sushi
((SELECT id FROM public.users WHERE email='owner2@example.com'),
 'Yoshi Sushi',
 'Premium sushi and Japanese dining on Seven Mile Beach',
 '3459451001',
 'yoshisushi@example.com',
 'Falls Centre, West Bay Rd',
 19.3310, -81.3870,
 'Japanese',
 4.8, 510,
 5.00, 30,
 TRUE, '11:30', '22:00', TRUE),

-- 10. Chicken! Chicken!
((SELECT id FROM public.users WHERE email='owner2@example.com'),
 'Chicken! Chicken!',
 'Caribbean-style jerk and rotisserie chicken with all the fixings',
 '3459451002',
 'chickenchicken@example.com',
 'West Shore Centre, West Bay Rd',
 19.3320, -81.3875,
 'Caribbean',
 4.3, 678,
 4.00, 20,
 TRUE, '11:00', '21:00', TRUE),

-- 11. Thai Orchid
((SELECT id FROM public.users WHERE email='owner2@example.com'),
 'Thai Orchid',
 'Authentic Thai cuisine with fresh local ingredients',
 '3459451003',
 'thaiorchid@example.com',
 'Queens Court, West Bay Rd',
 19.3350, -81.3890,
 'Thai',
 4.5, 234,
 5.00, 30,
 TRUE, '11:30', '22:00', TRUE),

-- 12. Agua Restaurant
((SELECT id FROM public.users WHERE email='owner4@example.com'),
 'Agua Restaurant',
 'Oceanfront fine dining with Latin and Caribbean flavors',
 '3459451004',
 'agua@example.com',
 'Galleria Plaza, West Bay Rd',
 19.3380, -81.3900,
 'Latin American',
 4.7, 189,
 6.00, 35,
 TRUE, '17:00', '23:00', TRUE),

-- 13. Luca Restaurant
((SELECT id FROM public.users WHERE email='owner4@example.com'),
 'Luca Restaurant',
 'Italian fine dining on the beach with handmade pasta',
 '3456231200',
 'luca@example.com',
 'Caribbean Club, Seven Mile Beach',
 19.3420, -81.3930,
 'Italian',
 4.8, 298,
 6.00, 35,
 TRUE, '17:30', '22:30', TRUE),

-- 14. The Wharf Restaurant
((SELECT id FROM public.users WHERE email='owner4@example.com'),
 'The Wharf Restaurant',
 'Iconic waterfront dining with fresh seafood and steaks',
 '3459452231',
 'wharf@example.com',
 '43 West Bay Rd',
 19.3150, -81.3860,
 'Seafood',
 4.5, 567,
 5.00, 30,
 TRUE, '17:00', '22:00', TRUE),

-- 15. Lone Star Bar & Grill
((SELECT id FROM public.users WHERE email='owner2@example.com'),
 'Lone Star Bar & Grill',
 'Tex-Mex favourites, burgers and cold drinks on Seven Mile Beach',
 '3459451005',
 'lonestar@example.com',
 'West Bay Rd, Seven Mile Beach',
 19.3340, -81.3885,
 'American',
 4.2, 389,
 4.00, 25,
 TRUE, '11:00', '23:00', TRUE),

-- 16. Tukka Restaurant
((SELECT id FROM public.users WHERE email='owner6@example.com'),
 'Tukka Restaurant',
 'Australian-Caribbean fusion on the oceanfront in East End',
 '3459471100',
 'tukka@example.com',
 'Austin Conolly Dr, East End',
 19.3020, -81.1530,
 'Australian-Caribbean',
 4.6, 145,
 8.00, 45,
 TRUE, '11:30', '21:30', TRUE),

-- ── West Bay ─────────────────────────────────────────────────────────

-- 17. Heritage Kitchen
((SELECT id FROM public.users WHERE email='owner9@example.com'),
 'Heritage Kitchen',
 'Traditional Caymanian fish fry and local dishes on the beach',
 '3459461500',
 'heritagekitchen@example.com',
 'Boggy Sand Rd, West Bay',
 19.3680, -81.4090,
 'Caymanian',
 4.7, 456,
 5.00, 25,
 TRUE, '11:00', '19:00', TRUE),

-- 18. Calypso Grill
((SELECT id FROM public.users WHERE email='owner9@example.com'),
 'Calypso Grill',
 'Caribbean waterfront fine dining with the freshest catches',
 '3459491900',
 'calypsogrill@example.com',
 'Morgan''s Harbour, West Bay',
 19.3590, -81.4010,
 'Seafood',
 4.8, 378,
 6.00, 30,
 TRUE, '11:30', '22:00', TRUE),

-- 19. Ristorante Pappagallo
((SELECT id FROM public.users WHERE email='owner9@example.com'),
 'Ristorante Pappagallo',
 'Italian fine dining in a thatched-roof setting on a bird sanctuary lagoon',
 '3459491100',
 'pappagallo@example.com',
 'Barkers, West Bay',
 19.3620, -81.4120,
 'Italian',
 4.6, 267,
 6.00, 35,
 TRUE, '17:00', '22:00', TRUE),

-- ── Bodden Town ──────────────────────────────────────────────────────

-- 20. Grape Tree Cafe
((SELECT id FROM public.users WHERE email='owner7@example.com'),
 'Grape Tree Cafe',
 'Casual Caymanian and international comfort food in Bodden Town',
 '3459471001',
 'grapetree@example.com',
 'Bodden Town Rd, Bodden Town',
 19.2840, -81.2540,
 'Caymanian',
 4.3, 123,
 5.00, 30,
 TRUE, '07:00', '15:00', TRUE),

-- 21. Rankin''s Jerk Centre
((SELECT id FROM public.users WHERE email='owner7@example.com'),
 'Rankin''s Jerk Centre',
 'Smoky jerk chicken, pork, and fish with all the island sides',
 '3459471002',
 'rankinsjerk@example.com',
 'Shamrock Rd, Bodden Town',
 19.2820, -81.2500,
 'Caribbean',
 4.5, 567,
 5.00, 20,
 TRUE, '11:00', '21:00', TRUE),

-- ── More George Town / South Sound ───────────────────────────────────

-- 22. Lobster Pot
((SELECT id FROM public.users WHERE email='owner1@example.com'),
 'Lobster Pot',
 'Classic seafood restaurant with the best Cayman-style lobster',
 '3459491234',
 'lobsterpot@example.com',
 'North Church St, George Town',
 19.2890, -81.3830,
 'Seafood',
 4.6, 489,
 5.00, 30,
 TRUE, '11:30', '22:00', TRUE),

-- 23. Grand Old House
((SELECT id FROM public.users WHERE email='owner10@example.com'),
 'Grand Old House',
 'Historic plantation house waterfront fine dining',
 '3459492333',
 'grandoldhouse@example.com',
 'South Church St, George Town',
 19.2800, -81.3850,
 'Continental',
 4.7, 234,
 6.00, 35,
 TRUE, '17:00', '22:00', TRUE),

-- 24. Craft Food & Beverage Co
((SELECT id FROM public.users WHERE email='owner3@example.com'),
 'Craft Food & Beverage Co',
 'Gourmet burgers, craft cocktails, and comfort food',
 '3459491188',
 'craftfb@example.com',
 'Camana Bay, Grand Cayman',
 19.3245, -81.3795,
 'American',
 4.4, 189,
 5.00, 25,
 TRUE, '11:00', '23:00', TRUE),

-- 25. Catch Restaurant
((SELECT id FROM public.users WHERE email='owner4@example.com'),
 'Catch Restaurant',
 'Fresh sushi and Asian fusion right on Seven Mile Beach',
 '3459451077',
 'catchrestaurant@example.com',
 'Morgan''s Seafood, West Bay Rd',
 19.3360, -81.3895,
 'Asian Fusion',
 4.5, 234,
 5.00, 30,
 TRUE, '12:00', '22:00', TRUE),

-- 26. Coconut Joe''s
((SELECT id FROM public.users WHERE email='owner2@example.com'),
 'Coconut Joe''s',
 'Beach bar and grill with laid-back vibes and island flavours',
 '3459451078',
 'coconutjoes@example.com',
 'West Bay Rd, Seven Mile Beach',
 19.3330, -81.3880,
 'Caribbean',
 4.2, 345,
 4.00, 20,
 TRUE, '10:00', '23:00', TRUE),

-- ── Rum Point & North Side ───────────────────────────────────────────

-- 27. Rum Point Club Restaurant
((SELECT id FROM public.users WHERE email='owner5@example.com'),
 'Rum Point Club Restaurant',
 'Beachfront dining in the tranquil North Side with Caribbean fare',
 '3459471111',
 'rumpoint@example.com',
 'Rum Point Dr, North Side',
 19.3590, -81.2720,
 'Caribbean',
 4.4, 234,
 8.00, 45,
 TRUE, '11:00', '21:00', TRUE),

-- 28. Kaibo Beach Bar & Grill
((SELECT id FROM public.users WHERE email='owner5@example.com'),
 'Kaibo Beach Bar & Grill',
 'Casual beach dining and upstairs fine dining at Cayman Kai',
 '3459471112',
 'kaibo@example.com',
 'Kaibo Rd, North Side',
 19.3570, -81.2750,
 'Seafood',
 4.5, 312,
 8.00, 40,
 TRUE, '11:00', '22:00', TRUE),

-- ── Cayman Brac ──────────────────────────────────────────────────────

-- 29. Captain''s Table
((SELECT id FROM public.users WHERE email='owner8@example.com'),
 'Captain''s Table',
 'Sister Islands dining with fresh catch and Caymanian favourites',
 '3459481001',
 'captainstable@example.com',
 'South Side Rd, Cayman Brac',
 19.7150, -79.8050,
 'Caymanian',
 4.3, 89,
 6.00, 30,
 TRUE, '07:00', '21:00', TRUE),

-- 30. Star Island Restaurant
((SELECT id FROM public.users WHERE email='owner8@example.com'),
 'Star Island Restaurant',
 'Brac Island casual dining with seafood and Caribbean plates',
 '3459481002',
 'starisland@example.com',
 'West End, Cayman Brac',
 19.7200, -79.8100,
 'Caribbean',
 4.2, 67,
 6.00, 35,
 TRUE, '11:00', '21:00', TRUE);

-- ====================================================================
-- 3. INSERT MENU ITEMS (KYD Pricing)
-- ====================================================================

-- ── 1. Guy Harvey's Island Grill ─────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Guy Harvey''s Island Grill'),
 'Fish Tacos', 'Blackened mahi-mahi with mango salsa and slaw', 14.00, 'Appetizers', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Guy Harvey''s Island Grill'),
 'Coconut Shrimp', 'Crispy coconut-crusted shrimp with sweet chili dip', 16.00, 'Appetizers', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Guy Harvey''s Island Grill'),
 'Conch Fritters', 'Traditional Cayman conch fritters with dipping sauce', 13.00, 'Appetizers', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Guy Harvey''s Island Grill'),
 'Grilled Snapper', 'Fresh red snapper grilled with lemon butter', 28.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Guy Harvey''s Island Grill'),
 'Jerk Chicken Plate', 'Smoky jerk chicken with rice & peas and plantain', 22.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Guy Harvey''s Island Grill'),
 'Key Lime Pie', 'Classic Key lime pie with whipped cream', 10.00, 'Desserts', TRUE, 0, 5);

-- ── 2. The Brasserie ─────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='The Brasserie'),
 'Farm Egg Breakfast', 'Local eggs, bacon, toast, roasted tomatoes', 16.00, 'Breakfast', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='The Brasserie'),
 'Lobster Mac & Cheese', 'Cayman lobster in creamy truffle mac & cheese', 32.00, 'Entrees', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='The Brasserie'),
 'Grilled Wahoo', 'Local wahoo with seasonal vegetables', 30.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='The Brasserie'),
 'Brasserie Burger', 'Angus beef patty, aged cheddar, truffle aioli', 20.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='The Brasserie'),
 'Tropical Fruit Tart', 'Seasonal fruit on almond pastry cream', 12.00, 'Desserts', TRUE, 0, 5);

-- ── 3. Bread & Chocolate ─────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Bread & Chocolate'),
 'Croissant Sandwich', 'Ham, gruyère and arugula on butter croissant', 12.00, 'Sandwiches', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Bread & Chocolate'),
 'Acai Bowl', 'Blended acai topped with granola, banana and honey', 14.00, 'Breakfast', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Bread & Chocolate'),
 'Chocolate Croissant', 'Buttery croissant with Belgian chocolate', 6.00, 'Pastries', TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Bread & Chocolate'),
 'Avocado Toast', 'Smashed avocado, poached egg, chili flakes on sourdough', 14.00, 'Breakfast', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Bread & Chocolate'),
 'Iced Latte', 'Double-shot espresso over ice with milk', 6.00, 'Beverages', TRUE, 0, 3);

-- ── 4. Singh's Roti Shop ─────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Singh''s Roti Shop'),
 'Chicken Curry Roti', 'Tender chicken curry wrapped in fresh dhalpuri roti', 12.00, 'Roti', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Singh''s Roti Shop'),
 'Goat Curry Roti', 'Slow-cooked curried goat in soft roti', 14.00, 'Roti', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Singh''s Roti Shop'),
 'Veggie Roti', 'Mixed vegetable curry with channa in dhalpuri', 10.00, 'Roti', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Singh''s Roti Shop'),
 'Doubles', 'Fried bara with curried channa and pepper sauce', 5.00, 'Snacks', TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Singh''s Roti Shop'),
 'Sorrel Drink', 'Traditional hibiscus spice drink', 4.00, 'Beverages', TRUE, 0, 2);

-- ── 5. Casanova Restaurant ───────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Casanova Restaurant'),
 'Bruschetta', 'Grilled ciabatta with tomato, basil and balsamic', 12.00, 'Appetizers', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Casanova Restaurant'),
 'Lobster Linguine', 'Fresh Cayman lobster in garlic white wine sauce', 38.00, 'Pasta', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='Casanova Restaurant'),
 'Margherita Pizza', 'San Marzano tomato, fresh mozzarella, basil', 18.00, 'Pizza', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Casanova Restaurant'),
 'Chicken Parmigiana', 'Breaded chicken with marinara and melted mozzarella', 24.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Casanova Restaurant'),
 'Tiramisu', 'Classic Italian coffee-soaked ladyfinger dessert', 12.00, 'Desserts', TRUE, 0, 5);

-- ── 6. Abacus ────────────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Abacus'),
 'Tuna Tartare', 'Sushi-grade tuna with avocado, sesame and ponzu', 18.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Abacus'),
 'Abacus Burger', 'Wagyu blend patty, caramelized onion, aged cheddar', 22.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Abacus'),
 'Pan-Seared Grouper', 'Local grouper with herb butter and island slaw', 32.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Abacus'),
 'Duck Confit', 'Crispy duck leg with sweet potato puree', 30.00, 'Entrees', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='Abacus'),
 'Crème Brûlée', 'Classic vanilla bean crème brûlée', 12.00, 'Desserts', TRUE, 0, 5);

-- ── 7. Mizu Asian Bistro ─────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Mizu Asian Bistro'),
 'Spicy Tuna Roll', 'Fresh tuna, spicy mayo, cucumber and tobiko', 16.00, 'Sushi', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Mizu Asian Bistro'),
 'Dragon Roll', 'Shrimp tempura, avocado, eel sauce', 18.00, 'Sushi', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Mizu Asian Bistro'),
 'Chicken Teriyaki', 'Grilled chicken glazed with house teriyaki', 20.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Mizu Asian Bistro'),
 'Pad Thai', 'Rice noodles with shrimp, peanuts and tamarind', 18.00, 'Noodles', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Mizu Asian Bistro'),
 'Mochi Ice Cream', 'Assorted Japanese mochi (3 pieces)', 8.00, 'Desserts', TRUE, 0, 3);

-- ── 8. Tillie's ──────────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Tillie''s'),
 'Jerk Pork Sliders', 'Mini jerk pork burgers with coleslaw', 14.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Tillie''s'),
 'Fish & Chips', 'Beer-battered snapper with crispy fries', 18.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Tillie''s'),
 'Cayman-Style Beef Patty', 'Seasoned beef in flaky pastry', 6.00, 'Snacks', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Tillie''s'),
 'Island Salad', 'Mixed greens, mango, avocado, lime vinaigrette', 14.00, 'Salads', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Tillie''s'),
 'Rum Cake', 'Traditional Cayman rum cake slice', 8.00, 'Desserts', TRUE, 0, 3);

-- ── 9. Yoshi Sushi ───────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Yoshi Sushi'),
 'Sashimi Platter', 'Chef''s selection of premium sashimi (12 pcs)', 32.00, 'Sashimi', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Yoshi Sushi'),
 'Volcano Roll', 'Spicy baked crab and shrimp with sriracha mayo', 20.00, 'Sushi', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Yoshi Sushi'),
 'Edamame', 'Steamed soybeans with sea salt', 7.00, 'Appetizers', TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Yoshi Sushi'),
 'Wagyu Beef Tataki', 'Seared wagyu with ponzu and crispy garlic', 28.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Yoshi Sushi'),
 'Green Tea Ice Cream', 'Matcha ice cream (2 scoops)', 8.00, 'Desserts', TRUE, 0, 3);

-- ── 10. Chicken! Chicken! ────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Chicken! Chicken!'),
 'Quarter Jerk Chicken', 'Quarter rotisserie jerk chicken with 2 sides', 10.00, 'Chicken', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Chicken! Chicken!'),
 'Half Jerk Chicken', 'Half rotisserie jerk chicken with 2 sides', 16.00, 'Chicken', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Chicken! Chicken!'),
 'Whole Jerk Chicken', 'Whole rotisserie jerk chicken with 4 sides', 25.00, 'Chicken', TRUE, 5, 15),
((SELECT id FROM public.restaurants WHERE name='Chicken! Chicken!'),
 'Rice & Peas', 'Coconut rice with kidney beans', 4.00, 'Sides', TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Chicken! Chicken!'),
 'Coleslaw', 'Creamy Caribbean coleslaw', 3.00, 'Sides', TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Chicken! Chicken!'),
 'Festival', 'Fried sweet cornbread dumplings (4 pcs)', 4.00, 'Sides', TRUE, 0, 8);

-- ── 11. Thai Orchid ──────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Thai Orchid'),
 'Tom Yum Soup', 'Spicy lemongrass shrimp soup', 12.00, 'Soups', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Thai Orchid'),
 'Green Curry', 'Thai green curry with coconut milk and basil', 18.00, 'Curries', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Thai Orchid'),
 'Pad See Ew', 'Wide noodles with chicken, egg and Chinese broccoli', 16.00, 'Noodles', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Thai Orchid'),
 'Mango Sticky Rice', 'Sweet sticky rice with fresh mango and coconut cream', 10.00, 'Desserts', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Thai Orchid'),
 'Thai Iced Tea', 'Classic sweet Thai tea with cream', 5.00, 'Beverages', TRUE, 0, 3);

-- ── 12. Agua Restaurant ──────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Agua Restaurant'),
 'Ceviche', 'Fresh fish cured in lime with chili and cilantro', 18.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Agua Restaurant'),
 'Braised Short Ribs', 'Slow-cooked beef short ribs with chimichurri', 34.00, 'Entrees', TRUE, 0, 25),
((SELECT id FROM public.restaurants WHERE name='Agua Restaurant'),
 'Grilled Octopus', 'Charred octopus with romesco and potatoes', 28.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Agua Restaurant'),
 'Tres Leches Cake', 'Three-milk soaked sponge cake', 12.00, 'Desserts', TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Agua Restaurant'),
 'Churros', 'Cinnamon sugar churros with chocolate sauce', 10.00, 'Desserts', TRUE, 0, 8);

-- ── 13. Luca Restaurant ──────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Luca Restaurant'),
 'Burrata Salad', 'Creamy burrata with heirloom tomatoes and basil oil', 18.00, 'Appetizers', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Luca Restaurant'),
 'Lobster Risotto', 'Arborio rice with Cayman lobster and saffron', 42.00, 'Entrees', TRUE, 0, 25),
((SELECT id FROM public.restaurants WHERE name='Luca Restaurant'),
 'Veal Milanese', 'Crispy breaded veal cutlet with arugula salad', 36.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Luca Restaurant'),
 'Truffle Tagliatelle', 'Fresh pasta with black truffle cream sauce', 34.00, 'Pasta', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Luca Restaurant'),
 'Panna Cotta', 'Vanilla panna cotta with berry compote', 14.00, 'Desserts', TRUE, 0, 5);

-- ── 14. The Wharf Restaurant ─────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='The Wharf Restaurant'),
 'Calamari', 'Lightly fried calamari with marinara', 14.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='The Wharf Restaurant'),
 'Grilled Lobster Tail', 'Caribbean lobster tail with drawn butter', 45.00, 'Entrees', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='The Wharf Restaurant'),
 'Filet Mignon', '8oz premium filet with red wine jus', 42.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='The Wharf Restaurant'),
 'Seafood Chowder', 'Rich creamy chowder with lobster, shrimp and fish', 14.00, 'Soups', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='The Wharf Restaurant'),
 'Chocolate Lava Cake', 'Warm chocolate cake with molten centre', 14.00, 'Desserts', TRUE, 0, 12);

-- ── 15. Lone Star Bar & Grill ────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Lone Star Bar & Grill'),
 'Nachos Grande', 'Loaded nachos with cheese, jalapeños and guac', 14.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Lone Star Bar & Grill'),
 'BBQ Bacon Burger', 'Angus beef, crispy bacon, BBQ sauce, cheddar', 18.00, 'Burgers', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Lone Star Bar & Grill'),
 'Fish Sandwich', 'Grilled mahi-mahi with tartar on brioche', 16.00, 'Sandwiches', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Lone Star Bar & Grill'),
 'Buffalo Wings', 'Crispy wings tossed in hot sauce (10 pcs)', 14.00, 'Appetizers', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Lone Star Bar & Grill'),
 'Brownie Sundae', 'Warm brownie with vanilla ice cream and fudge', 10.00, 'Desserts', TRUE, 0, 8);

-- ── 16. Tukka Restaurant ─────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Tukka Restaurant'),
 'Kangaroo Loin', 'Grilled kangaroo with bush tomato chutney', 32.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Tukka Restaurant'),
 'Barramundi', 'Pan-seared barramundi with lemon myrtle butter', 30.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Tukka Restaurant'),
 'Aussie Meat Pie', 'Traditional beef and gravy pie with mushy peas', 14.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Tukka Restaurant'),
 'Lamington', 'Sponge cake coated in chocolate and coconut', 8.00, 'Desserts', TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Tukka Restaurant'),
 'Flat White', 'Australian-style espresso with velvety milk', 6.00, 'Beverages', TRUE, 0, 5);

-- ── 17. Heritage Kitchen ─────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Heritage Kitchen'),
 'Fried Fish & Fritters', 'Whole fried snapper with Johnny cakes', 18.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Heritage Kitchen'),
 'Turtle Stew', 'Traditional Caymanian turtle stew with breadfruit', 16.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Heritage Kitchen'),
 'Conch Stew', 'Slow-simmered conch in tomato-based broth', 14.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Heritage Kitchen'),
 'Heavy Cake', 'Traditional Caymanian cassava cake', 6.00, 'Desserts', TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Heritage Kitchen'),
 'Lemonade', 'Fresh-squeezed island lemonade', 4.00, 'Beverages', TRUE, 0, 3);

-- ── 18. Calypso Grill ────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Calypso Grill'),
 'Conch Ceviche', 'Fresh conch cured in citrus with scotch bonnet', 16.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Calypso Grill'),
 'Blackened Mahi-Mahi', 'Cajun-spiced mahi with mango chutney', 30.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Calypso Grill'),
 'Rack of Lamb', 'Herb-crusted lamb rack with rosemary jus', 38.00, 'Entrees', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='Calypso Grill'),
 'Grilled Cayman Lobster', 'Local lobster with garlic butter and island sides', 48.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Calypso Grill'),
 'Coconut Crème Brûlée', 'Coconut-infused crème brûlée', 12.00, 'Desserts', TRUE, 0, 5);

-- ── 19. Ristorante Pappagallo ────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Ristorante Pappagallo'),
 'Caprese Salad', 'Buffalo mozzarella, tomato, basil and aged balsamic', 16.00, 'Appetizers', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Ristorante Pappagallo'),
 'Osso Buco', 'Braised veal shank with saffron risotto', 38.00, 'Entrees', TRUE, 0, 25),
((SELECT id FROM public.restaurants WHERE name='Ristorante Pappagallo'),
 'Seafood Linguine', 'Linguine with lobster, shrimp and mussels', 36.00, 'Pasta', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Ristorante Pappagallo'),
 'Veal Piccata', 'Pan-fried veal with lemon caper butter sauce', 32.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Ristorante Pappagallo'),
 'Cannoli', 'Crispy Sicilian pastry with ricotta cream', 10.00, 'Desserts', TRUE, 0, 5);

-- ── 20. Grape Tree Cafe ──────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Grape Tree Cafe'),
 'Caymanian Breakfast', 'Ackee, saltfish, breadfruit and Johnny cakes', 14.00, 'Breakfast', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Grape Tree Cafe'),
 'Oxtail Stew', 'Slow-braised oxtail with butter beans', 16.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Grape Tree Cafe'),
 'Club Sandwich', 'Triple-decker with turkey, bacon and avocado', 14.00, 'Sandwiches', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Grape Tree Cafe'),
 'Banana Fritters', 'Fried banana fritters with cinnamon sugar', 6.00, 'Desserts', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Grape Tree Cafe'),
 'Bush Tea', 'Traditional Caymanian herbal tea', 3.00, 'Beverages', TRUE, 0, 5);

-- ── 21. Rankin's Jerk Centre ─────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Rankin''s Jerk Centre'),
 'Jerk Chicken', 'Smoky pimento-wood jerk chicken with sides', 14.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Rankin''s Jerk Centre'),
 'Jerk Pork', 'Slow-smoked jerk pork with rice & peas', 16.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Rankin''s Jerk Centre'),
 'Jerk Fish', 'Whole jerk snapper with festival and slaw', 18.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Rankin''s Jerk Centre'),
 'Breadfruit Chips', 'Crispy fried breadfruit chips with dip', 5.00, 'Sides', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Rankin''s Jerk Centre'),
 'Ginger Beer', 'Homemade spicy ginger beer', 4.00, 'Beverages', TRUE, 0, 2);

-- ── 22. Lobster Pot ──────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Lobster Pot'),
 'Lobster Bisque', 'Creamy lobster bisque with cognac', 14.00, 'Soups', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Lobster Pot'),
 'Whole Roasted Lobster', 'Cayman lobster roasted with herb butter', 50.00, 'Entrees', TRUE, 0, 25),
((SELECT id FROM public.restaurants WHERE name='Lobster Pot'),
 'Seafood Platter', 'Lobster, shrimp, conch, fish and crab', 55.00, 'Entrees', TRUE, 0, 25),
((SELECT id FROM public.restaurants WHERE name='Lobster Pot'),
 'Blackened Snapper', 'Cajun-spiced red snapper with plantain', 28.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Lobster Pot'),
 'Coconut Ice Cream', 'Homemade coconut ice cream with rum caramel', 10.00, 'Desserts', TRUE, 0, 5);

-- ── 23. Grand Old House ──────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Grand Old House'),
 'Escargot', 'Garlic herb butter baked escargot', 18.00, 'Appetizers', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Grand Old House'),
 'Rack of Lamb', 'New Zealand lamb with mint pesto', 42.00, 'Entrees', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='Grand Old House'),
 'Beef Wellington', 'Prime tenderloin wrapped in puff pastry', 48.00, 'Entrees', TRUE, 0, 30),
((SELECT id FROM public.restaurants WHERE name='Grand Old House'),
 'Caesar Salad', 'Tableside Caesar with anchovy dressing', 16.00, 'Salads', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Grand Old House'),
 'Bananas Foster', 'Flambéed bananas with rum and vanilla ice cream', 14.00, 'Desserts', TRUE, 0, 8);

-- ── 24. Craft Food & Beverage Co ─────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Craft Food & Beverage Co'),
 'Truffle Fries', 'Hand-cut fries with truffle oil and parmesan', 10.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Craft Food & Beverage Co'),
 'Craft Burger', 'Double smash burger with secret sauce', 18.00, 'Burgers', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Craft Food & Beverage Co'),
 'Pulled Pork Sandwich', 'Slow-smoked pork with tangy BBQ slaw', 16.00, 'Sandwiches', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Craft Food & Beverage Co'),
 'Fried Chicken Sandwich', 'Crispy chicken, pickles and spicy mayo', 16.00, 'Sandwiches', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Craft Food & Beverage Co'),
 'Milkshake', 'Handspun milkshake (vanilla, chocolate or strawberry)', 8.00, 'Beverages', TRUE, 0, 5);

-- ── 25. Catch Restaurant ─────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Catch Restaurant'),
 'Crispy Gyoza', 'Pan-fried pork and ginger dumplings (6 pcs)', 14.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Catch Restaurant'),
 'Rainbow Roll', 'California roll topped with assorted sashimi', 20.00, 'Sushi', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Catch Restaurant'),
 'Korean BBQ Short Ribs', 'Gochujang-glazed beef short ribs', 28.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Catch Restaurant'),
 'Ramen Bowl', 'Rich pork bone broth with chashu and soft egg', 18.00, 'Noodles', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Catch Restaurant'),
 'Matcha Cheesecake', 'Green tea cheesecake with yuzu glaze', 12.00, 'Desserts', TRUE, 0, 5);

-- ── 26. Coconut Joe's ────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Coconut Joe''s'),
 'Conch Fritters', 'Crispy conch fritters with spicy aioli', 12.00, 'Appetizers', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Coconut Joe''s'),
 'Fish Tacos', 'Grilled mahi tacos with pineapple salsa', 14.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Coconut Joe''s'),
 'Coconut Shrimp Plate', 'Coconut-crusted shrimp with fries and slaw', 18.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Coconut Joe''s'),
 'Jerk Chicken Wings', 'Grilled jerk wings with blue cheese dip (8 pcs)', 14.00, 'Appetizers', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Coconut Joe''s'),
 'Piña Colada Smoothie', 'Non-alcoholic coconut pineapple smoothie', 7.00, 'Beverages', TRUE, 0, 5);

-- ── 27. Rum Point Club Restaurant ────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Rum Point Club Restaurant'),
 'Jerk Shrimp Skewers', 'Grilled jerk shrimp on bamboo skewers', 16.00, 'Appetizers', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Rum Point Club Restaurant'),
 'Grilled Grouper', 'Fresh grouper with island butter sauce', 28.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Rum Point Club Restaurant'),
 'BBQ Ribs', 'Fall-off-the-bone pork ribs with island BBQ glaze', 24.00, 'Entrees', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='Rum Point Club Restaurant'),
 'Caesar Wrap', 'Grilled chicken Caesar in a flour tortilla', 14.00, 'Sandwiches', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Rum Point Club Restaurant'),
 'Mudslide', 'Non-alcoholic chocolate coffee frozen drink', 8.00, 'Beverages', TRUE, 0, 5);

-- ── 28. Kaibo Beach Bar & Grill ──────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Kaibo Beach Bar & Grill'),
 'Smoked Fish Dip', 'House-smoked fish dip with crackers', 12.00, 'Appetizers', TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Kaibo Beach Bar & Grill'),
 'Lionfish Tacos', 'Fried lionfish with Caribbean slaw', 16.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Kaibo Beach Bar & Grill'),
 'Coconut Curry Chicken', 'Chicken in coconut curry with basmati rice', 20.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Kaibo Beach Bar & Grill'),
 'Surf & Turf', 'Lobster tail and grilled sirloin', 45.00, 'Entrees', TRUE, 0, 22),
((SELECT id FROM public.restaurants WHERE name='Kaibo Beach Bar & Grill'),
 'Mango Sorbet', 'Fresh Cayman mango sorbet', 8.00, 'Desserts', TRUE, 0, 3);

-- ── 29. Captain's Table ──────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Captain''s Table'),
 'Brac Breakfast', 'Eggs, saltfish fritters, breadfruit and plantain', 12.00, 'Breakfast', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Captain''s Table'),
 'Curried Goat', 'Slow-cooked Cayman-style curried goat', 18.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Captain''s Table'),
 'Fried Snapper', 'Whole fried snapper with bammy and pickled onion', 22.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Captain''s Table'),
 'Stew Conch', 'Traditional stewed conch with provisions', 16.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Captain''s Table'),
 'Cassava Cake', 'Brac-style cassava cake with coconut', 6.00, 'Desserts', TRUE, 0, 5);

-- ── 30. Star Island Restaurant ───────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
((SELECT id FROM public.restaurants WHERE name='Star Island Restaurant'),
 'Pepper Shrimp', 'Spicy sautéed shrimp with scotch bonnet', 16.00, 'Appetizers', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Star Island Restaurant'),
 'Brac Fish Fry', 'Catch of the day fried with seasoning and sides', 20.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Star Island Restaurant'),
 'Brown Stew Chicken', 'Caymanian-style braised chicken', 16.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Star Island Restaurant'),
 'Fried Plantain', 'Sweet fried plantain slices', 5.00, 'Sides', TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Star Island Restaurant'),
 'Sea Grape Punch', 'Refreshing island sea grape juice', 5.00, 'Beverages', TRUE, 0, 3);

-- ====================================================================
-- 4. INSERT SAMPLE DRIVERS (Cayman)
-- ====================================================================
INSERT INTO public.drivers (user_id, vehicle_type, vehicle_number, license_number, rating, completed_deliveries, is_available, current_latitude, current_longitude, is_verified, documents_status) VALUES
  ((SELECT id FROM public.users WHERE email='driver1@example.com'),
   'car', 'CI-1234', 'CYM-DL-001',
   4.8, 245,
   TRUE,
   19.2870, -81.3810,
   TRUE,
   '{"license": "verified", "registration": "verified", "insurance": "verified"}'),
  ((SELECT id FROM public.users WHERE email='driver2@example.com'),
   'car', 'CI-5678', 'CYM-DL-002',
   4.6, 189,
   TRUE,
   19.3300, -81.3880,
   TRUE,
   '{"license": "verified", "registration": "verified", "insurance": "verified"}'),
  ((SELECT id FROM public.users WHERE email='driver3@example.com'),
   'scooter', 'CI-9012', 'CYM-DL-003',
   4.4, 156,
   FALSE,
   19.2830, -81.2520,
   FALSE,
   '{"license": "verified", "registration": "pending", "insurance": "pending"}'),
  ((SELECT id FROM public.users WHERE email='driver4@example.com'),
   'car', 'CI-3456', 'CYM-DL-004',
   4.9, 312,
   TRUE,
   19.2790, -81.3650,
   TRUE,
   '{"license": "verified", "registration": "verified", "insurance": "verified"}');

-- ====================================================================
-- 5. INSERT SAMPLE ORDERS (KYD pricing)
-- ====================================================================
INSERT INTO public.orders (user_id, restaurant_id, driver_id, subtotal, tax_amount, delivery_fee, discount, total_amount, status, delivery_address, delivery_latitude, delivery_longitude, notes, payment_method, payment_status, ordered_at, confirmed_at, completed_at) VALUES
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Yoshi Sushi'),
   (SELECT id FROM public.drivers WHERE license_number='CYM-DL-001'),
   52.00, 0.00, 5.00, 0.00, 57.00,
   'delivered',
   '15 South Church St, George Town',
   19.2869, -81.3812,
   'Extra wasabi please',
   'card',
   'completed',
   NOW() - INTERVAL '2 days',
   NOW() - INTERVAL '2 days' + INTERVAL '10 minutes',
   NOW() - INTERVAL '2 days' + INTERVAL '45 minutes'),
  ((SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Heritage Kitchen'),
   (SELECT id FROM public.drivers WHERE license_number='CYM-DL-002'),
   34.00, 0.00, 5.00, 0.00, 39.00,
   'delivered',
   '22 West Bay Rd, Seven Mile Beach',
   19.3299, -81.3880,
   NULL,
   'card',
   'completed',
   NOW() - INTERVAL '1 day',
   NOW() - INTERVAL '1 day' + INTERVAL '12 minutes',
   NOW() - INTERVAL '1 day' + INTERVAL '40 minutes'),
  ((SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Luca Restaurant'),
   (SELECT id FROM public.drivers WHERE license_number='CYM-DL-004'),
   76.00, 0.00, 6.00, 5.00, 77.00,
   'delivered',
   '8 Shamrock Rd, Prospect',
   19.2785, -81.3650,
   'No nuts please',
   'wallet',
   'completed',
   NOW() - INTERVAL '6 hours',
   NOW() - INTERVAL '6 hours' + INTERVAL '15 minutes',
   NOW() - INTERVAL '6 hours' + INTERVAL '50 minutes'),
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Chicken! Chicken!'),
   NULL,
   26.00, 0.00, 4.00, 0.00, 30.00,
   'confirmed',
   '15 South Church St, George Town',
   19.2869, -81.3812,
   'Extra rice & peas',
   'card',
   'pending',
   NOW() - INTERVAL '10 minutes',
   NOW() - INTERVAL '5 minutes',
   NULL),
  ((SELECT id FROM public.users WHERE email='customer4@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Singh''s Roti Shop'),
   NULL,
   26.00, 0.00, 4.00, 0.00, 30.00,
   'pending',
   '45 Eastern Ave, George Town',
   19.2950, -81.3750,
   NULL,
   'cash',
   'pending',
   NOW() - INTERVAL '3 minutes',
   NULL,
   NULL);

-- ====================================================================
-- 6. INSERT SAMPLE ORDER ITEMS
-- ====================================================================
INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 4),
   (SELECT id FROM public.menus WHERE name='Sashimi Platter' LIMIT 1),
   'Sashimi Platter', 32.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 4),
   (SELECT id FROM public.menus WHERE name='Volcano Roll' LIMIT 1),
   'Volcano Roll', 20.00, 1, NULL);

INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 3),
   (SELECT id FROM public.menus WHERE name='Fried Fish & Fritters' LIMIT 1),
   'Fried Fish & Fritters', 18.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 3),
   (SELECT id FROM public.menus WHERE name='Conch Stew' LIMIT 1),
   'Conch Stew', 14.00, 1, NULL);

INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 2),
   (SELECT id FROM public.menus WHERE name='Lobster Risotto' LIMIT 1),
   'Lobster Risotto', 42.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 2),
   (SELECT id FROM public.menus WHERE name='Truffle Tagliatelle' LIMIT 1),
   'Truffle Tagliatelle', 34.00, 1, NULL);

INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.menus WHERE name='Half Jerk Chicken' LIMIT 1),
   'Half Jerk Chicken', 16.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.menus WHERE name='Rice & Peas' LIMIT 1),
   'Rice & Peas', 4.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.menus WHERE name='Festival' LIMIT 1),
   'Festival', 4.00, 1, NULL);

INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1),
   (SELECT id FROM public.menus WHERE name='Chicken Curry Roti' LIMIT 1),
   'Chicken Curry Roti', 12.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1),
   (SELECT id FROM public.menus WHERE name='Goat Curry Roti' LIMIT 1),
   'Goat Curry Roti', 14.00, 1, NULL);

-- ====================================================================
-- 7. INSERT SAMPLE PAYMENTS (KYD)
-- ====================================================================
INSERT INTO public.payments (order_id, user_id, amount, method, status, transaction_id) VALUES
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.users WHERE email='customer1@example.com'),
   57.00, 'card', 'completed', 'TXN-001-CARD'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer2@example.com'),
   39.00, 'card', 'completed', 'TXN-002-CARD'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer3@example.com'),
   77.00, 'wallet', 'completed', 'TXN-003-WALLET');

-- ====================================================================
-- 8. INSERT SAMPLE REVIEWS
-- ====================================================================
INSERT INTO public.reviews (order_id, user_id, restaurant_id, rating, review_text) VALUES
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Yoshi Sushi'),
   4.5, 'Best sushi on island! The sashimi was incredibly fresh.'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Heritage Kitchen'),
   5.0, 'Authentic Caymanian food at its best. The fried fish was perfect!'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Luca Restaurant'),
   4.0, 'Beautiful setting and great pasta. Delivery was quick.');

-- ====================================================================
-- 9. INSERT SAMPLE NOTIFICATIONS
-- ====================================================================
INSERT INTO public.notifications (user_id, order_id, type, title, body, data, is_read) VALUES
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   'order_status', 'Order Confirmed', 'Your order has been confirmed by Yoshi Sushi',
   '{"status": "confirmed"}', TRUE),
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   'order_status', 'Order Delivered', 'Your order has been delivered',
   '{"status": "delivered"}', TRUE),
  ((SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') LIMIT 1),
   'order_status', 'Order Ready', 'Your order from Heritage Kitchen is ready',
   '{"status": "ready"}', TRUE),
  ((SELECT id FROM public.users WHERE email='driver1@example.com'),
   NULL,
   'delivery_assigned', 'New Delivery Assigned', 'You have been assigned a new delivery in George Town',
   '{"priority": "high"}', FALSE),
  ((SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') LIMIT 1),
   'order_status', 'Order On The Way', 'Your order from Luca is on the way',
   '{"driver_rating": 4.9}', TRUE);

-- ====================================================================
-- CAYMAN ISLANDS SEED DATA COMPLETE
-- 30 restaurants with full menus (KYD pricing)
-- All coordinates are Grand Cayman & Cayman Brac
-- ====================================================================

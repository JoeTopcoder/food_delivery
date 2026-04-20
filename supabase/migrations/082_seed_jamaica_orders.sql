-- ====================================================================
-- 082: Seed 59 orders in Kingston, Jamaica
-- Creates Jamaican users, restaurants, menus, drivers, and 59 orders
-- ====================================================================

-- ── Jamaican Customers ─────────────────────────────────────────────
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('jm_cust1@example.com', 'Andre Williams',    '8769261001', 'user', '12 Hope Road, Kingston 6',              18.0132, -76.7699, TRUE),
  ('jm_cust2@example.com', 'Keisha Brown',      '8769261002', 'user', '45 Old Hope Road, Liguanea',            18.0168, -76.7660, TRUE),
  ('jm_cust3@example.com', 'Damion Campbell',   '8769261003', 'user', '8 Constant Spring Road, Kingston 10',   18.0315, -76.7900, TRUE),
  ('jm_cust4@example.com', 'Shanna-Kay Thomas', '8769261004', 'user', '22 Red Hills Road, Kingston 10',        18.0350, -76.8050, TRUE),
  ('jm_cust5@example.com', 'Tyrone Morgan',     '8769261005', 'user', '67 Molynes Road, Kingston 10',          18.0180, -76.8000, TRUE),
  ('jm_cust6@example.com', 'Simone Edwards',    '8769261006', 'user', '3 Barbican Road, Kingston 6',           18.0230, -76.7650, TRUE),
  ('jm_cust7@example.com', 'Omar Johnson',      '8769261007', 'user', '15 Trafalgar Road, New Kingston',       18.0069, -76.7832, TRUE),
  ('jm_cust8@example.com', 'Tanesha Reid',      '8769261008', 'user', '90 Half Way Tree Rd, Kingston 10',      18.0095, -76.7936, TRUE),
  ('jm_cust9@example.com', 'Ricardo Clarke',    '8769261009', 'user', '5 Papine Square, Kingston 7',           18.0195, -76.7419, TRUE),
  ('jm_cust10@example.com','Marcia Stewart',    '8769261010', 'user', '28 Manor Park Plaza, Kingston 8',       18.0297, -76.7778, TRUE)
ON CONFLICT (email) DO NOTHING;

-- ── Jamaican Restaurant Owners ─────────────────────────────────────
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('jm_owner1@example.com',  'Patrick Chin',       '8769262001', 'restaurant', 'Half Way Tree, Kingston 10',    18.0095, -76.7936, TRUE),
  ('jm_owner2@example.com',  'Michelle Henry',     '8769262002', 'restaurant', 'New Kingston, Kingston 5',      18.0069, -76.7832, TRUE),
  ('jm_owner3@example.com',  'Garfield Taylor',    '8769262003', 'restaurant', 'Liguanea, Kingston 6',          18.0168, -76.7660, TRUE),
  ('jm_owner4@example.com',  'Nadine Patterson',   '8769262004', 'restaurant', 'Cross Roads, Kingston 5',       18.0127, -76.7859, TRUE),
  ('jm_owner5@example.com',  'Christopher Lee',    '8769262005', 'restaurant', 'Manor Park, Kingston 8',        18.0297, -76.7778, TRUE),
  ('jm_owner6@example.com',  'Sandra Burke',       '8769262006', 'restaurant', 'Hope Road, Kingston 6',         18.0132, -76.7699, TRUE),
  ('jm_owner7@example.com',  'Troy Robinson',      '8769262007', 'restaurant', 'Constant Spring, Kingston 10',  18.0315, -76.7900, TRUE),
  ('jm_owner8@example.com',  'Karen Dawkins',      '8769262008', 'restaurant', 'Downtown Kingston',             18.0179, -76.7999, TRUE),
  ('jm_owner9@example.com',  'Jason Sterling',     '8769262009', 'restaurant', 'Barbican, Kingston 6',          18.0230, -76.7650, TRUE),
  ('jm_owner10@example.com', 'Beverly Armstrong',  '8769262010', 'restaurant', 'Red Hills, Kingston 10',        18.0350, -76.8050, TRUE)
ON CONFLICT (email) DO NOTHING;

-- ── Jamaican Drivers ───────────────────────────────────────────────
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('jm_driver1@example.com', 'Devon Chambers',  '8769263001', 'driver', 'Half Way Tree, Kingston 10',  18.0095, -76.7936, TRUE),
  ('jm_driver2@example.com', 'Mark Spencer',    '8769263002', 'driver', 'Cross Roads, Kingston 5',     18.0127, -76.7859, TRUE)
ON CONFLICT (email) DO NOTHING;

-- ── 15 Kingston Restaurants ────────────────────────────────────────
INSERT INTO public.restaurants (owner_id, name, description, phone, email, address, latitude, longitude, cuisine_type, rating, review_count, delivery_fee, estimated_delivery_time, is_open, opening_time, closing_time, is_verified) VALUES
-- 1
((SELECT id FROM public.users WHERE email='jm_owner1@example.com'),
 'Island Grill Half Way Tree', 'Authentic Jamaican grilled chicken and sides', '8769281001', 'islandgrill.hwt@example.com',
 '89 Half Way Tree Rd, Kingston 10', 18.0098, -76.7940, 'Jamaican', 4.5, 487, 350.00, 25, TRUE, '07:00', '22:00', TRUE),
-- 2
((SELECT id FROM public.users WHERE email='jm_owner1@example.com'),
 'Island Grill Liguanea', 'Jamaican-style grilled meals, Kingston favourite', '8769281002', 'islandgrill.lig@example.com',
 '125 Old Hope Road, Liguanea', 18.0165, -76.7655, 'Jamaican', 4.4, 356, 350.00, 25, TRUE, '07:00', '22:00', TRUE),
-- 3
((SELECT id FROM public.users WHERE email='jm_owner2@example.com'),
 'Juici Patties Knutsford', 'Jamaica''s favourite patties and pastries', '8769281003', 'juici.knutsford@example.com',
 '17 Knutsford Blvd, New Kingston', 18.0072, -76.7828, 'Jamaican', 4.3, 612, 300.00, 15, TRUE, '06:00', '23:00', TRUE),
-- 4
((SELECT id FROM public.users WHERE email='jm_owner3@example.com'),
 'Devon House Bakery', 'Famous for I-Scream ice cream and baked goods', '8769281004', 'devonhouse@example.com',
 '26 Hope Road, Kingston 6', 18.0135, -76.7710, 'Bakery', 4.7, 843, 400.00, 20, TRUE, '10:00', '21:00', TRUE),
-- 5
((SELECT id FROM public.users WHERE email='jm_owner4@example.com'),
 'Tracks & Records', 'Usain Bolt''s restaurant — jerk, seafood & cocktails', '8769281005', 'tracks@example.com',
 '67 Constant Spring Rd, Kingston 10', 18.0280, -76.7890, 'Jamaican', 4.6, 529, 450.00, 30, TRUE, '11:00', '23:00', TRUE),
-- 6
((SELECT id FROM public.users WHERE email='jm_owner5@example.com'),
 'Sweetwood Jerk Joint', 'Smoky jerk chicken and pork, Manor Park', '8769281006', 'sweetwood@example.com',
 '3 Manor Park Plaza, Kingston 8', 18.0300, -76.7782, 'Jamaican', 4.5, 298, 350.00, 20, TRUE, '11:00', '21:00', TRUE),
-- 7
((SELECT id FROM public.users WHERE email='jm_owner6@example.com'),
 'Gloria''s Seafood City', 'Fresh seafood platters, lobster & festival', '8769281007', 'glorias@example.com',
 '10 Port Royal St, Kingston', 18.0050, -76.7920, 'Seafood', 4.4, 215, 400.00, 30, TRUE, '10:00', '22:00', TRUE),
-- 8
((SELECT id FROM public.users WHERE email='jm_owner7@example.com'),
 'Red Bones Blues Cafe', 'Upscale Caribbean fusion & live music', '8769281008', 'redbones@example.com',
 '1 Argyle Rd, Kingston 10', 18.0140, -76.7870, 'Caribbean Fusion', 4.7, 378, 450.00, 35, TRUE, '12:00', '23:00', TRUE),
-- 9
((SELECT id FROM public.users WHERE email='jm_owner8@example.com'),
 'Scotchies Kingston', 'Legendary jerk centre — jerk everything', '8769281009', 'scotchies.kgn@example.com',
 '15 Chelsea Ave, Kingston 10', 18.0160, -76.7950, 'Jamaican', 4.8, 721, 350.00, 20, TRUE, '11:00', '21:00', TRUE),
-- 10
((SELECT id FROM public.users WHERE email='jm_owner9@example.com'),
 'Rib Kage Barbican', 'Ribs, wings and BBQ meats', '8769281010', 'ribkage@example.com',
 '15 Barbican Rd, Kingston 6', 18.0235, -76.7655, 'BBQ', 4.3, 186, 350.00, 25, TRUE, '11:00', '22:00', TRUE),
-- 11
((SELECT id FROM public.users WHERE email='jm_owner10@example.com'),
 'Tastee Patties Cross Roads', 'Classic Jamaican patties since 1966', '8769281011', 'tastee.cross@example.com',
 '1 Cross Roads, Kingston 5', 18.0130, -76.7860, 'Jamaican', 4.2, 534, 300.00, 15, TRUE, '06:00', '22:00', TRUE),
-- 12
((SELECT id FROM public.users WHERE email='jm_owner2@example.com'),
 'Nirvanna Indian Kingston', 'North Indian cuisine in New Kingston', '8769281012', 'nirvanna@example.com',
 '11 Holborn Rd, New Kingston', 18.0065, -76.7850, 'Indian', 4.5, 167, 400.00, 35, TRUE, '11:30', '22:00', TRUE),
-- 13
((SELECT id FROM public.users WHERE email='jm_owner3@example.com'),
 'East Japanese Kingston', 'Sushi, ramen, and Japanese favourites', '8769281013', 'eastjapanese@example.com',
 '28 Barbican Rd, Kingston 6', 18.0240, -76.7648, 'Japanese', 4.5, 203, 450.00, 30, TRUE, '11:00', '22:00', TRUE),
-- 14
((SELECT id FROM public.users WHERE email='jm_owner4@example.com'),
 'So-So Seafood Bar', 'Casual seafood right off Constant Spring', '8769281014', 'soso@example.com',
 '91 Constant Spring Rd, Kingston 10', 18.0340, -76.7910, 'Seafood', 4.3, 142, 350.00, 25, TRUE, '10:00', '21:00', TRUE),
-- 15
((SELECT id FROM public.users WHERE email='jm_owner5@example.com'),
 'Chilitos Jamaican-Mex', 'Jamaican-Mexican fusion burritos and tacos', '8769281015', 'chilitos@example.com',
 '7 Holborn Rd, New Kingston', 18.0060, -76.7845, 'Mexican Fusion', 4.4, 249, 350.00, 20, TRUE, '10:00', '22:00', TRUE)
ON CONFLICT DO NOTHING;

-- ── Menu Items ─────────────────────────────────────────────────────
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
-- Island Grill Half Way Tree
((SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'), 'Jerk Chicken Meal',       'Quarter jerk chicken with rice & peas, coleslaw',  950.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'), 'BBQ Chicken Meal',        'Smoky BBQ chicken with festival and fries',         980.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'), 'Curry Goat',              'Tender curry goat with white rice',                1200.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'), 'Festival (3 pcs)',        'Sweet fried dumplings',                             250.00, 'Sides',   TRUE, 0, 5),
-- Island Grill Liguanea
((SELECT id FROM public.restaurants WHERE name='Island Grill Liguanea'), 'Jerk Chicken Meal',       'Quarter jerk chicken with rice & peas',              950.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Island Grill Liguanea'), 'Brown Stew Fish',         'Seasoned snapper in brown stew sauce',              1350.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Island Grill Liguanea'), 'Oxtail Meal',             'Stewed oxtail with butter beans & rice',            1500.00, 'Entrees', TRUE, 0, 15),
-- Juici Patties
((SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'), 'Beef Patty',             'Classic Jamaican beef patty',                       220.00, 'Snacks',  TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'), 'Chicken Patty',          'Seasoned chicken patty',                            220.00, 'Snacks',  TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'), 'Coco Bread & Patty',     'Beef patty in coco bread',                          350.00, 'Snacks',  TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'), 'Veggie Patty',           'Seasoned vegetable filling',                        200.00, 'Snacks',  TRUE, 0, 3),
-- Devon House Bakery
((SELECT id FROM public.restaurants WHERE name='Devon House Bakery'), 'I-Scream Devon Stout',         'Devon stout ice cream - large',                     600.00, 'Desserts',TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Devon House Bakery'), 'I-Scream Grapenut',            'Grapenut ice cream - large',                        600.00, 'Desserts',TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Devon House Bakery'), 'Coconut Drops',                'Traditional coconut candy',                         350.00, 'Snacks',  TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Devon House Bakery'), 'Rum Cake',                     'Rich Jamaican rum cake',                            800.00, 'Desserts',TRUE, 0, 5),
-- Tracks & Records
((SELECT id FROM public.restaurants WHERE name='Tracks & Records'), 'Jerk Platter',                   'Jerk chicken & pork with sides',                   2200.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Tracks & Records'), 'Garlic Lobster',                 'Whole garlic butter lobster',                      4500.00, 'Entrees', TRUE, 0, 25),
((SELECT id FROM public.restaurants WHERE name='Tracks & Records'), 'Wings Platter',                  '12 pcs jerk wings with dip',                       1800.00, 'Appetizers',TRUE,0, 15),
-- Sweetwood Jerk Joint
((SELECT id FROM public.restaurants WHERE name='Sweetwood Jerk Joint'), 'Jerk Chicken Half',          'Half jerk chicken with sides',                     1300.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='Sweetwood Jerk Joint'), 'Jerk Pork',                  'Smoky jerk pork platter',                          1400.00, 'Entrees', TRUE, 0, 18),
((SELECT id FROM public.restaurants WHERE name='Sweetwood Jerk Joint'), 'Bammy',                      'Cassava flatbread',                                 300.00, 'Sides',   TRUE, 0, 5),
-- Gloria's Seafood
((SELECT id FROM public.restaurants WHERE name='Gloria''s Seafood City'), 'Steamed Fish',             'Whole steamed snapper with okra',                  2500.00, 'Entrees', TRUE, 0, 25),
((SELECT id FROM public.restaurants WHERE name='Gloria''s Seafood City'), 'Escovitch Fish',           'Fried fish with tangy escovitch sauce',            2200.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Gloria''s Seafood City'), 'Lobster Thermidor',        'Creamy lobster baked in shell',                    5000.00, 'Entrees', TRUE, 0, 30),
-- Red Bones Blues Cafe
((SELECT id FROM public.restaurants WHERE name='Red Bones Blues Cafe'), 'Ackee & Saltfish Wrap',      'Fusion wrap with Jamaica''s national dish',        1200.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Red Bones Blues Cafe'), 'Rum-Glazed Ribs',            'Slow-cooked ribs with rum glaze',                  2800.00, 'Entrees', TRUE, 0, 25),
-- Scotchies
((SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'), 'Jerk Chicken Quarter',         'Authentic pimento-smoked jerk chicken',             900.00, 'Entrees', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'), 'Jerk Pork',                    'Slow-smoked jerk pork',                            1000.00, 'Entrees', TRUE, 0, 12),
((SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'), 'Roast Breadfruit',             'Charcoal-roasted breadfruit',                       350.00, 'Sides',   TRUE, 0, 8),
((SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'), 'Sweet Potato Pudding',         'Traditional Jamaican sweet potato pudding',          400.00, 'Desserts',TRUE, 0, 5),
-- Rib Kage
((SELECT id FROM public.restaurants WHERE name='Rib Kage Barbican'), 'Full Rack Ribs',                'Full rack BBQ ribs with 2 sides',                  2800.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Rib Kage Barbican'), 'Jerk Wings Bucket',             '20 pcs jerk wings',                                1600.00, 'Entrees', TRUE, 0, 15),
-- Tastee
((SELECT id FROM public.restaurants WHERE name='Tastee Patties Cross Roads'), 'Original Beef Patty',  'Tastee signature beef patty',                       200.00, 'Snacks',  TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Tastee Patties Cross Roads'), 'Chicken Patty',        'Tastee chicken patty',                              200.00, 'Snacks',  TRUE, 0, 3),
((SELECT id FROM public.restaurants WHERE name='Tastee Patties Cross Roads'), 'Cheese Patty',         'Beef & cheese patty',                               250.00, 'Snacks',  TRUE, 0, 3),
-- Nirvanna
((SELECT id FROM public.restaurants WHERE name='Nirvanna Indian Kingston'), 'Butter Chicken',         'Creamy North Indian butter chicken',                1800.00, 'Entrees', TRUE, 0, 20),
((SELECT id FROM public.restaurants WHERE name='Nirvanna Indian Kingston'), 'Garlic Naan',            'Fresh garlic naan bread',                            350.00, 'Sides',   TRUE, 0, 5),
((SELECT id FROM public.restaurants WHERE name='Nirvanna Indian Kingston'), 'Lamb Biryani',           'Aromatic lamb biryani',                             2200.00, 'Entrees', TRUE, 0, 25),
-- East Japanese
((SELECT id FROM public.restaurants WHERE name='East Japanese Kingston'), 'Dragon Roll',              '8 pc dragon roll with eel',                         1800.00, 'Sushi',   TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='East Japanese Kingston'), 'Chicken Ramen',            'Rich chicken broth ramen',                          1500.00, 'Entrees', TRUE, 0, 15),
-- So-So Seafood
((SELECT id FROM public.restaurants WHERE name='So-So Seafood Bar'), 'Fish & Bammy',                  'Fried fish with bammy and salad',                   1400.00, 'Entrees', TRUE, 0, 15),
((SELECT id FROM public.restaurants WHERE name='So-So Seafood Bar'), 'Conch Soup',                    'Traditional conch soup',                            1200.00, 'Soups',   TRUE, 0, 20),
-- Chilitos
((SELECT id FROM public.restaurants WHERE name='Chilitos Jamaican-Mex'), 'Jerk Chicken Burrito',     'Jerk chicken with rice, peas & cheese',             1100.00, 'Entrees', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Chilitos Jamaican-Mex'), 'Ackee Tacos',              'Ackee & saltfish tacos (3)',                        1000.00, 'Entrees', TRUE, 0, 10),
((SELECT id FROM public.restaurants WHERE name='Chilitos Jamaican-Mex'), 'Plantain Nachos',          'Plantain chips with jerk chicken & cheese',          900.00, 'Appetizers',TRUE,0, 8)
ON CONFLICT DO NOTHING;

-- ── JM Drivers ─────────────────────────────────────────────────────
INSERT INTO public.drivers (user_id, vehicle_type, vehicle_number, license_number, rating, completed_deliveries, is_available, current_latitude, current_longitude, is_verified, documents_status)
SELECT u.id, 'bike', 'JM-1234', 'JM-DL-001', 4.7, 120, TRUE, 18.0095, -76.7936, TRUE,
       '{"license":"verified","registration":"verified","insurance":"verified"}'
FROM public.users u WHERE u.email = 'jm_driver1@example.com'
AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = u.id);

INSERT INTO public.drivers (user_id, vehicle_type, vehicle_number, license_number, rating, completed_deliveries, is_available, current_latitude, current_longitude, is_verified, documents_status)
SELECT u.id, 'car', 'JM-5678', 'JM-DL-002', 4.5, 89, TRUE, 18.0127, -76.7859, TRUE,
       '{"license":"verified","registration":"verified","insurance":"verified"}'
FROM public.users u WHERE u.email = 'jm_driver2@example.com'
AND NOT EXISTS (SELECT 1 FROM public.drivers d WHERE d.user_id = u.id);

-- ====================================================================
-- 59 ORDERS — Kingston Jamaica (driver_id NULL = available for drivers)
-- Mix of statuses: pending, confirmed, preparing, ready
-- Delivery fees: JMD 300–600 based on distance
-- ====================================================================
INSERT INTO public.orders (user_id, restaurant_id, subtotal, tax_amount, delivery_fee, discount, total_amount, status, delivery_address, delivery_latitude, delivery_longitude, notes, payment_method, payment_status, is_pickup, ordered_at) VALUES

-- 1
((SELECT id FROM public.users WHERE email='jm_cust1@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'),
 1900.00, 190.00, 350.00, 0, 2440.00, 'pending',
 '12 Hope Road, Kingston 6', 18.0132, -76.7699, 'Extra sauce please', 'card', 'completed', FALSE, NOW() - INTERVAL '15 minutes'),

-- 2
((SELECT id FROM public.users WHERE email='jm_cust2@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Liguanea'),
 950.00, 95.00, 350.00, 0, 1395.00, 'confirmed',
 '45 Old Hope Road, Liguanea', 18.0168, -76.7660, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '12 minutes'),

-- 3
((SELECT id FROM public.users WHERE email='jm_cust3@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'),
 790.00, 79.00, 400.00, 0, 1269.00, 'preparing',
 '8 Constant Spring Road, Kingston 10', 18.0315, -76.7900, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '20 minutes'),

-- 4
((SELECT id FROM public.users WHERE email='jm_cust4@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Devon House Bakery'),
 1550.00, 155.00, 450.00, 0, 2155.00, 'ready',
 '22 Red Hills Road, Kingston 10', 18.0350, -76.8050, 'Include napkins', 'card', 'completed', FALSE, NOW() - INTERVAL '25 minutes'),

-- 5
((SELECT id FROM public.users WHERE email='jm_cust5@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tracks & Records'),
 4500.00, 450.00, 500.00, 0, 5450.00, 'pending',
 '67 Molynes Road, Kingston 10', 18.0180, -76.8000, 'Call when arriving', 'card', 'completed', FALSE, NOW() - INTERVAL '8 minutes'),

-- 6
((SELECT id FROM public.users WHERE email='jm_cust6@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Sweetwood Jerk Joint'),
 2700.00, 270.00, 350.00, 0, 3320.00, 'confirmed',
 '3 Barbican Road, Kingston 6', 18.0230, -76.7650, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '18 minutes'),

-- 7
((SELECT id FROM public.users WHERE email='jm_cust7@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Gloria''s Seafood City'),
 2500.00, 250.00, 400.00, 0, 3150.00, 'preparing',
 '15 Trafalgar Road, New Kingston', 18.0069, -76.7832, 'Extra lemon wedges', 'card', 'completed', FALSE, NOW() - INTERVAL '22 minutes'),

-- 8
((SELECT id FROM public.users WHERE email='jm_cust8@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Red Bones Blues Cafe'),
 2800.00, 280.00, 450.00, 0, 3530.00, 'ready',
 '90 Half Way Tree Rd, Kingston 10', 18.0095, -76.7936, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '30 minutes'),

-- 9
((SELECT id FROM public.users WHERE email='jm_cust9@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'),
 1900.00, 190.00, 400.00, 0, 2490.00, 'pending',
 '5 Papine Square, Kingston 7', 18.0195, -76.7419, 'Make it spicy!', 'cash', 'pending', FALSE, NOW() - INTERVAL '10 minutes'),

-- 10
((SELECT id FROM public.users WHERE email='jm_cust10@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Rib Kage Barbican'),
 2800.00, 280.00, 350.00, 0, 3430.00, 'confirmed',
 '28 Manor Park Plaza, Kingston 8', 18.0297, -76.7778, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '14 minutes'),

-- 11
((SELECT id FROM public.users WHERE email='jm_cust1@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tastee Patties Cross Roads'),
 650.00, 65.00, 300.00, 0, 1015.00, 'preparing',
 '12 Hope Road, Kingston 6', 18.0132, -76.7699, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '16 minutes'),

-- 12
((SELECT id FROM public.users WHERE email='jm_cust2@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Nirvanna Indian Kingston'),
 2150.00, 215.00, 400.00, 0, 2765.00, 'ready',
 '45 Old Hope Road, Liguanea', 18.0168, -76.7660, 'Extra raita', 'card', 'completed', FALSE, NOW() - INTERVAL '28 minutes'),

-- 13
((SELECT id FROM public.users WHERE email='jm_cust3@example.com'),
 (SELECT id FROM public.restaurants WHERE name='East Japanese Kingston'),
 3300.00, 330.00, 450.00, 0, 4080.00, 'pending',
 '71 Constant Spring Road, Kingston 10', 18.0320, -76.7905, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '7 minutes'),

-- 14
((SELECT id FROM public.users WHERE email='jm_cust4@example.com'),
 (SELECT id FROM public.restaurants WHERE name='So-So Seafood Bar'),
 2600.00, 260.00, 400.00, 0, 3260.00, 'confirmed',
 '22 Red Hills Road, Kingston 10', 18.0350, -76.8050, 'No pepper in soup', 'cash', 'pending', FALSE, NOW() - INTERVAL '19 minutes'),

-- 15
((SELECT id FROM public.users WHERE email='jm_cust5@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Chilitos Jamaican-Mex'),
 2000.00, 200.00, 350.00, 0, 2550.00, 'preparing',
 '67 Molynes Road, Kingston 10', 18.0180, -76.8000, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '21 minutes'),

-- 16
((SELECT id FROM public.users WHERE email='jm_cust6@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'),
 2180.00, 218.00, 400.00, 0, 2798.00, 'ready',
 '5 Barbican Close, Kingston 6', 18.0228, -76.7647, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '32 minutes'),

-- 17
((SELECT id FROM public.users WHERE email='jm_cust7@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'),
 440.00, 44.00, 300.00, 0, 784.00, 'pending',
 '15 Trafalgar Road, New Kingston', 18.0069, -76.7832, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '5 minutes'),

-- 18
((SELECT id FROM public.users WHERE email='jm_cust8@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tracks & Records'),
 6300.00, 630.00, 500.00, 0, 7430.00, 'confirmed',
 '12 Worthington Ave, Kingston 5', 18.0080, -76.7870, 'Birthday dinner!', 'card', 'completed', FALSE, NOW() - INTERVAL '13 minutes'),

-- 19
((SELECT id FROM public.users WHERE email='jm_cust9@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'),
 2250.00, 225.00, 450.00, 0, 2925.00, 'preparing',
 '5 Papine Square, Kingston 7', 18.0195, -76.7419, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '24 minutes'),

-- 20
((SELECT id FROM public.users WHERE email='jm_cust10@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Sweetwood Jerk Joint'),
 1600.00, 160.00, 350.00, 0, 2110.00, 'ready',
 '28 Manor Park Plaza, Kingston 8', 18.0297, -76.7778, 'Extra bammy', 'cash', 'pending', FALSE, NOW() - INTERVAL '35 minutes'),

-- 21
((SELECT id FROM public.users WHERE email='jm_cust1@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Devon House Bakery'),
 2000.00, 200.00, 400.00, 0, 2600.00, 'pending',
 '17 Lady Musgrave Rd, Kingston 5', 18.0115, -76.7755, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '6 minutes'),

-- 22
((SELECT id FROM public.users WHERE email='jm_cust2@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Red Bones Blues Cafe'),
 4000.00, 400.00, 450.00, 0, 4850.00, 'confirmed',
 '23 Dunrobin Ave, Kingston 10', 18.0145, -76.7885, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '11 minutes'),

-- 23
((SELECT id FROM public.users WHERE email='jm_cust3@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Liguanea'),
 2850.00, 285.00, 400.00, 0, 3535.00, 'preparing',
 '45 Barbican Rd, Kingston 6', 18.0245, -76.7653, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '17 minutes'),

-- 24
((SELECT id FROM public.users WHERE email='jm_cust4@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Rib Kage Barbican'),
 4400.00, 440.00, 350.00, 0, 5190.00, 'ready',
 '6 Hillcrest Ave, Kingston 6', 18.0255, -76.7670, 'Extra BBQ sauce', 'card', 'completed', FALSE, NOW() - INTERVAL '33 minutes'),

-- 25
((SELECT id FROM public.users WHERE email='jm_cust5@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Nirvanna Indian Kingston'),
 3900.00, 390.00, 400.00, 0, 4690.00, 'pending',
 '16 Eastwood Park Rd, Kingston 5', 18.0090, -76.7810, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '9 minutes'),

-- 26
((SELECT id FROM public.users WHERE email='jm_cust6@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Gloria''s Seafood City'),
 5000.00, 500.00, 450.00, 0, 5950.00, 'confirmed',
 '8 Paddington Terrace, Kingston 6', 18.0170, -76.7630, 'Handle with care', 'card', 'completed', FALSE, NOW() - INTERVAL '15 minutes'),

-- 27
((SELECT id FROM public.users WHERE email='jm_cust7@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tastee Patties Cross Roads'),
 600.00, 60.00, 300.00, 0, 960.00, 'preparing',
 '15 Trafalgar Road, New Kingston', 18.0069, -76.7832, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '23 minutes'),

-- 28
((SELECT id FROM public.users WHERE email='jm_cust8@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Chilitos Jamaican-Mex'),
 1100.00, 110.00, 350.00, 0, 1560.00, 'ready',
 '3 South Ave, Kingston 10', 18.0060, -76.7910, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '29 minutes'),

-- 29
((SELECT id FROM public.users WHERE email='jm_cust9@example.com'),
 (SELECT id FROM public.restaurants WHERE name='East Japanese Kingston'),
 1800.00, 180.00, 500.00, 0, 2480.00, 'pending',
 '20 Gordon Town Rd, Kingston 7', 18.0210, -76.7400, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '4 minutes'),

-- 30
((SELECT id FROM public.users WHERE email='jm_cust10@example.com'),
 (SELECT id FROM public.restaurants WHERE name='So-So Seafood Bar'),
 1400.00, 140.00, 400.00, 0, 1940.00, 'confirmed',
 '10 Retirement Crescent, Kingston 8', 18.0310, -76.7790, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '16 minutes'),

-- 31
((SELECT id FROM public.users WHERE email='jm_cust1@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'),
 1300.00, 130.00, 350.00, 0, 1780.00, 'preparing',
 '12 Hope Road, Kingston 6', 18.0132, -76.7699, 'Extra breadfruit', 'card', 'completed', FALSE, NOW() - INTERVAL '19 minutes'),

-- 32
((SELECT id FROM public.users WHERE email='jm_cust2@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Sweetwood Jerk Joint'),
 2700.00, 270.00, 380.00, 0, 3350.00, 'ready',
 '90 Old Hope Road, Liguanea', 18.0160, -76.7668, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '34 minutes'),

-- 33
((SELECT id FROM public.users WHERE email='jm_cust3@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tracks & Records'),
 2200.00, 220.00, 450.00, 0, 2870.00, 'pending',
 '15 Shortwood Rd, Kingston 8', 18.0285, -76.7720, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '7 minutes'),

-- 34
((SELECT id FROM public.users WHERE email='jm_cust4@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'),
 1200.00, 120.00, 400.00, 0, 1720.00, 'confirmed',
 '11 Olivier Rd, Kingston 8', 18.0265, -76.7740, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '13 minutes'),

-- 35
((SELECT id FROM public.users WHERE email='jm_cust5@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Devon House Bakery'),
 950.00, 95.00, 400.00, 0, 1445.00, 'preparing',
 '67 Molynes Road, Kingston 10', 18.0180, -76.8000, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '20 minutes'),

-- 36
((SELECT id FROM public.users WHERE email='jm_cust6@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'),
 570.00, 57.00, 350.00, 0, 977.00, 'ready',
 '6 Barbican Road, Kingston 6', 18.0230, -76.7650, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '31 minutes'),

-- 37
((SELECT id FROM public.users WHERE email='jm_cust7@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Red Bones Blues Cafe'),
 1200.00, 120.00, 400.00, 0, 1720.00, 'pending',
 '9 Belmont Rd, Kingston 5', 18.0055, -76.7840, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '3 minutes'),

-- 38
((SELECT id FROM public.users WHERE email='jm_cust8@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Rib Kage Barbican'),
 1600.00, 160.00, 350.00, 0, 2110.00, 'confirmed',
 '4 Russell Heights, Kingston 8', 18.0290, -76.7765, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '12 minutes'),

-- 39
((SELECT id FROM public.users WHERE email='jm_cust9@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Nirvanna Indian Kingston'),
 1800.00, 180.00, 450.00, 0, 2430.00, 'preparing',
 '5 Papine Square, Kingston 7', 18.0195, -76.7419, 'Extra spicy naan', 'card', 'completed', FALSE, NOW() - INTERVAL '22 minutes'),

-- 40
((SELECT id FROM public.users WHERE email='jm_cust10@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Liguanea'),
 1500.00, 150.00, 350.00, 0, 2000.00, 'ready',
 '28 Manor Park Plaza, Kingston 8', 18.0297, -76.7778, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '36 minutes'),

-- 41
((SELECT id FROM public.users WHERE email='jm_cust1@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Chilitos Jamaican-Mex'),
 2000.00, 200.00, 350.00, 0, 2550.00, 'pending',
 '25 Waterloo Road, Kingston 10', 18.0100, -76.7920, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '6 minutes'),

-- 42
((SELECT id FROM public.users WHERE email='jm_cust2@example.com'),
 (SELECT id FROM public.restaurants WHERE name='So-So Seafood Bar'),
 2600.00, 260.00, 450.00, 0, 3310.00, 'confirmed',
 '78 Mannings Hill Rd, Kingston 8', 18.0340, -76.7850, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '14 minutes'),

-- 43
((SELECT id FROM public.users WHERE email='jm_cust3@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'),
 900.00, 90.00, 350.00, 0, 1340.00, 'preparing',
 '8 Constant Spring Road, Kingston 10', 18.0315, -76.7900, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '18 minutes'),

-- 44
((SELECT id FROM public.users WHERE email='jm_cust4@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tracks & Records'),
 1800.00, 180.00, 450.00, 0, 2430.00, 'ready',
 '3 Norbrook Drive, Kingston 8', 18.0380, -76.7950, 'Ring the gate bell', 'card', 'completed', FALSE, NOW() - INTERVAL '27 minutes'),

-- 45
((SELECT id FROM public.users WHERE email='jm_cust5@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Gloria''s Seafood City'),
 2200.00, 220.00, 400.00, 0, 2820.00, 'pending',
 '67 Molynes Road, Kingston 10', 18.0180, -76.8000, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '8 minutes'),

-- 46
((SELECT id FROM public.users WHERE email='jm_cust6@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tastee Patties Cross Roads'),
 400.00, 40.00, 300.00, 0, 740.00, 'confirmed',
 '14 Stanton Terrace, Kingston 6', 18.0200, -76.7640, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '11 minutes'),

-- 47
((SELECT id FROM public.users WHERE email='jm_cust7@example.com'),
 (SELECT id FROM public.restaurants WHERE name='East Japanese Kingston'),
 3300.00, 330.00, 500.00, 0, 4130.00, 'preparing',
 '7 Holborn Road, New Kingston', 18.0065, -76.7850, 'Chopsticks pls', 'card', 'completed', FALSE, NOW() - INTERVAL '21 minutes'),

-- 48
((SELECT id FROM public.users WHERE email='jm_cust8@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Half Way Tree'),
 980.00, 98.00, 350.00, 0, 1428.00, 'ready',
 '18 South Ave, Kingston 10', 18.0070, -76.7920, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '30 minutes'),

-- 49
((SELECT id FROM public.users WHERE email='jm_cust9@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Devon House Bakery'),
 1200.00, 120.00, 450.00, 0, 1770.00, 'pending',
 '5 Papine Square, Kingston 7', 18.0195, -76.7419, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '5 minutes'),

-- 50
((SELECT id FROM public.users WHERE email='jm_cust10@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Sweetwood Jerk Joint'),
 1700.00, 170.00, 350.00, 0, 2220.00, 'confirmed',
 '28 Manor Park Plaza, Kingston 8', 18.0297, -76.7778, 'Add extra jerk sauce', 'card', 'completed', FALSE, NOW() - INTERVAL '13 minutes'),

-- 51
((SELECT id FROM public.users WHERE email='jm_cust1@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Red Bones Blues Cafe'),
 2800.00, 280.00, 400.00, 0, 3480.00, 'preparing',
 '9 Hillcrest Ave, Kingston 6', 18.0252, -76.7668, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '23 minutes'),

-- 52
((SELECT id FROM public.users WHERE email='jm_cust2@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Juici Patties Knutsford'),
 350.00, 35.00, 300.00, 0, 685.00, 'ready',
 '32 Liguanea Ave, Kingston 6', 18.0175, -76.7640, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '28 minutes'),

-- 53
((SELECT id FROM public.users WHERE email='jm_cust3@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Rib Kage Barbican'),
 2800.00, 280.00, 350.00, 0, 3430.00, 'pending',
 '14 Coldspring Ave, Kingston 8', 18.0278, -76.7735, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '4 minutes'),

-- 54
((SELECT id FROM public.users WHERE email='jm_cust4@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Island Grill Liguanea'),
 950.00, 95.00, 350.00, 0, 1395.00, 'confirmed',
 '22 Red Hills Road, Kingston 10', 18.0350, -76.8050, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '10 minutes'),

-- 55
((SELECT id FROM public.users WHERE email='jm_cust5@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Chilitos Jamaican-Mex'),
 900.00, 90.00, 350.00, 0, 1340.00, 'preparing',
 '45 Maxfield Ave, Kingston 13', 18.0100, -76.8010, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '19 minutes'),

-- 56
((SELECT id FROM public.users WHERE email='jm_cust6@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Nirvanna Indian Kingston'),
 4000.00, 400.00, 400.00, 0, 4800.00, 'ready',
 '3 Barbican Road, Kingston 6', 18.0230, -76.7650, 'Mild spice level', 'card', 'completed', FALSE, NOW() - INTERVAL '33 minutes'),

-- 57
((SELECT id FROM public.users WHERE email='jm_cust7@example.com'),
 (SELECT id FROM public.restaurants WHERE name='So-So Seafood Bar'),
 1200.00, 120.00, 400.00, 0, 1720.00, 'pending',
 '8 Oxford Terrace, Kingston 5', 18.0085, -76.7870, NULL, 'card', 'completed', FALSE, NOW() - INTERVAL '3 minutes'),

-- 58
((SELECT id FROM public.users WHERE email='jm_cust8@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Scotchies Kingston'),
 1650.00, 165.00, 350.00, 0, 2165.00, 'confirmed',
 '90 Half Way Tree Rd, Kingston 10', 18.0095, -76.7936, NULL, 'cash', 'pending', FALSE, NOW() - INTERVAL '15 minutes'),

-- 59
((SELECT id FROM public.users WHERE email='jm_cust9@example.com'),
 (SELECT id FROM public.restaurants WHERE name='Tracks & Records'),
 3800.00, 380.00, 500.00, 0, 4680.00, 'ready',
 '15 University Crescent, Mona', 18.0205, -76.7485, 'Celebrate Bolt!', 'card', 'completed', FALSE, NOW() - INTERVAL '26 minutes');

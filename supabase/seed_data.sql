-- ====================================================================
-- FOOD DRIVER APP - SAMPLE/SEED DATA
-- Run this AFTER the main schema (complete_schema.sql) is created
-- This file contains test data for development and testing
-- ====================================================================

-- ====================================================================
-- 1. INSERT SAMPLE USERS
-- ====================================================================
-- Customers
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('customer1@example.com', 'Ahmed Hassan', '01712345678', 'user', '123 Main St, Dhaka', 23.8103, 90.4125, TRUE),
  ('customer2@example.com', 'Fatima Khan', '01812345679', 'user', '456 Oak Ave, Dhaka', 23.8150, 90.4200, TRUE),
  ('customer3@example.com', 'Mohammed Ali', '01912345680', 'user', '789 Pine Rd, Dhaka', 23.8200, 90.4150, TRUE),
  ('customer4@example.com', 'Rina Dey', '01612345681', 'user', '321 Elm Street, Dhaka', 23.8250, 90.4100, TRUE),
  ('customer5@example.com', 'Nasir Ahmed', '01512345682', 'user', '654 Maple Dr, Dhaka', 23.8050, 90.4300, TRUE);

-- Restaurant Owners
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('restaurant1@example.com', 'Shahin Alam', '01712345701', 'restaurant', '100 Restaurant St, Dhaka', 23.8110, 90.4130, TRUE),
  ('restaurant2@example.com', 'Salma Begum', '01812345702', 'restaurant', '200 Food Plaza, Dhaka', 23.8160, 90.4180, TRUE),
  ('restaurant3@example.com', 'Hassan Khan', '01912345703', 'restaurant', '300 Cuisine Blvd, Dhaka', 23.8210, 90.4160, TRUE);

-- Drivers
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('driver1@example.com', 'Karim Biswas', '01712345751', 'driver', '150 Driver Lane, Dhaka', 23.8120, 90.4140, TRUE),
  ('driver2@example.com', 'Ravi Sharma', '01812345752', 'driver', '250 Delivery Rd, Dhaka', 23.8170, 90.4190, TRUE),
  ('driver3@example.com', 'Sumon Das', '01912345753', 'driver', '350 Logistics St, Dhaka', 23.8220, 90.4170, TRUE),
  ('driver4@example.com', 'Tariq Khan', '01612345754', 'driver', '420 Express Way, Dhaka', 23.8300, 90.4050, TRUE);

-- Admin User
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('admin@example.com', 'Admin User', '01712345800', 'admin', '1 Admin HQ, Dhaka', 23.8100, 90.4100, TRUE);

-- ====================================================================
-- 2. INSERT SAMPLE RESTAURANTS
-- ====================================================================
INSERT INTO public.restaurants (owner_id, name, description, phone, email, address, latitude, longitude, cuisine_type, rating, review_count, delivery_fee, estimated_delivery_time, is_open, opening_time, closing_time, is_verified) VALUES
  ((SELECT id FROM public.users WHERE email='restaurant1@example.com'), 
   'Spice Kitchen', 
   'Authentic traditional Bengali and Indian cuisine with aromatic spices',
   '01712345701',
   'restaurant1@example.com',
   '100 Restaurant St, Dhaka',
   23.8110, 90.4130,
   'Bengali',
   4.5, 45,
   50, 30,
   TRUE,
   '11:00', '23:00',
   TRUE),
  ((SELECT id FROM public.users WHERE email='restaurant2@example.com'),
   'Taste of Dhaka',
   'Traditional Bangladeshi food with a modern touch',
   '01812345702',
   'restaurant2@example.com',
   '200 Food Plaza, Dhaka',
   23.8160, 90.4180,
   'Bangladeshi',
   4.7, 128,
   60, 35,
   TRUE,
   '10:00', '22:00',
   TRUE),
  ((SELECT id FROM public.users WHERE email='restaurant3@example.com'),
   'Global Bites',
   'International cuisine from around the world',
   '01912345703',
   'restaurant3@example.com',
   '300 Cuisine Blvd, Dhaka',
   23.8210, 90.4160,
   'International',
   4.3, 67,
   70, 40,
   TRUE,
   '12:00', '23:30',
   TRUE);

-- ====================================================================
-- 3. INSERT SAMPLE MENU ITEMS
-- ====================================================================
-- Spice Kitchen Menu
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   'Biryani Rice',
   'Fragrant basmati rice cooked with marinated meat',
   450.00, 'Rice', TRUE, 10, 25),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   'Tandoori Chicken',
   'Grilled chicken marinated in yogurt and spices',
   320.00, 'Meat', TRUE, 5, 20),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   'Paneer Tikka',
   'Cottage cheese grilled with vegetables',
   280.00, 'Vegetarian', TRUE, 0, 15),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   'Naan Bread',
   'Traditional oven-baked flatbread',
   60.00, 'Bread', TRUE, 0, 5),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   'Mango Lassi',
   'Refreshing yogurt-based mango drink',
   80.00, 'Beverage', TRUE, 0, 3);

-- Taste of Dhaka Menu
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   'Hilsa Fry',
   'Fried hilsa fish with traditional spices',
   520.00, 'Fish', TRUE, 15, 25),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   'Mixed Vegetable Curry',
   'Seasonal vegetables in aromatic curry sauce',
   200.00, 'Vegetarian', TRUE, 10, 18),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   'Chicken Jhol',
   'Chicken curry with traditional gravy',
   380.00, 'Meat', TRUE, 0, 20),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   'Pitha',
   'Traditional sweet rice cake',
   150.00, 'Dessert', TRUE, 5, 10),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   'Gulab Jamun',
   'Sweet milk solids in sugar syrup',
   120.00, 'Dessert', TRUE, 0, 8);

-- Global Bites Menu
INSERT INTO public.menus (restaurant_id, name, description, price, category, is_available, discount, preparation_time) VALUES
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'),
   'Burger Deluxe',
   'Premium beef burger with special sauce',
   380.00, 'Burger', TRUE, 10, 15),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'),
   'Caesar Salad',
   'Fresh romaine with parmesan and croutons',
   220.00, 'Salad', TRUE, 0, 10),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'),
   'Spaghetti Carbonara',
   'Creamy Italian pasta with bacon',
   420.00, 'Pasta', TRUE, 5, 18),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'),
   'Thai Green Curry',
   'Spicy Thai curry with coconut milk',
   350.00, 'Curry', TRUE, 0, 22),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'),
   'Iced Coffee',
   'Chilled espresso with cream',
   100.00, 'Beverage', TRUE, 0, 5);

-- ====================================================================
-- 4. INSERT SAMPLE DRIVERS
-- ====================================================================
INSERT INTO public.drivers (user_id, vehicle_type, vehicle_number, license_number, rating, completed_deliveries, is_available, current_latitude, current_longitude, is_verified, documents_status) VALUES
  ((SELECT id FROM public.users WHERE email='driver1@example.com'),
   'bike', 'DK-01-AB-001', 'LIC-001',
   4.8, 245,
   TRUE,
   23.8120, 90.4140,
   TRUE,
   '{"license": "verified", "registration": "verified", "insurance": "verified"}'),
  ((SELECT id FROM public.users WHERE email='driver2@example.com'),
   'bike', 'DK-01-AB-002', 'LIC-002',
   4.6, 189,
   TRUE,
   23.8170, 90.4190,
   TRUE,
   '{"license": "verified", "registration": "verified", "insurance": "verified"}'),
  ((SELECT id FROM public.users WHERE email='driver3@example.com'),
   'scooter', 'DK-01-AB-003', 'LIC-003',
   4.4, 156,
   FALSE,
   23.8220, 90.4170,
   FALSE,
   '{"license": "verified", "registration": "pending", "insurance": "pending"}'),
  ((SELECT id FROM public.users WHERE email='driver4@example.com'),
   'bike', 'DK-01-AB-004', 'LIC-004',
   4.9, 312,
   TRUE,
   23.8300, 90.4050,
   TRUE,
   '{"license": "verified", "registration": "verified", "insurance": "verified"}');

-- ====================================================================
-- 5. INSERT SAMPLE ORDERS
-- ====================================================================
INSERT INTO public.orders (user_id, restaurant_id, driver_id, subtotal, tax_amount, delivery_fee, discount, total_amount, status, delivery_address, delivery_latitude, delivery_longitude, notes, payment_method, payment_status, ordered_at, confirmed_at, completed_at) VALUES
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-001'),
   900.00, 90.00, 50.00, 50.00, 990.00,
   'delivered',
   '123 Main St, Dhaka',
   23.8103, 90.4125,
   'Extra spicy please',
   'card',
   'completed',
   NOW() - INTERVAL '2 days',
   NOW() - INTERVAL '2 days' + INTERVAL '10 minutes',
   NOW() - INTERVAL '2 days' + INTERVAL '45 minutes'),
  ((SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-002'),
   700.00, 70.00, 60.00, 0.00, 830.00,
   'delivered',
   '456 Oak Ave, Dhaka',
   23.8150, 90.4200,
   NULL,
   'card',
   'completed',
   NOW() - INTERVAL '1 day',
   NOW() - INTERVAL '1 day' + INTERVAL '12 minutes',
   NOW() - INTERVAL '1 day' + INTERVAL '40 minutes'),
  ((SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Global Bites'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-004'),
   850.00, 85.00, 70.00, 42.50, 962.50,
   'delivered',
   '789 Pine Rd, Dhaka',
   23.8200, 90.4150,
   'No onions',
   'wallet',
   'completed',
   NOW() - INTERVAL '6 hours',
   NOW() - INTERVAL '6 hours' + INTERVAL '15 minutes',
   NOW() - INTERVAL '6 hours' + INTERVAL '50 minutes'),
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   NULL,
   650.00, 65.00, 60.00, 0.00, 775.00,
   'confirmed',
   '123 Main St, Dhaka',
   23.8103, 90.4125,
   'Add extra sauce',
   'card',
   'pending',
   NOW() - INTERVAL '10 minutes',
   NOW() - INTERVAL '5 minutes',
   NULL),
  ((SELECT id FROM public.users WHERE email='customer4@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   NULL,
   500.00, 50.00, 50.00, 50.00, 550.00,
   'pending',
   '321 Elm Street, Dhaka',
   23.8250, 90.4100,
   NULL,
   'cash',
   'pending',
   NOW() - INTERVAL '3 minutes',
   NULL,
   NULL);

-- ====================================================================
-- 6. INSERT SAMPLE ORDER ITEMS
-- ====================================================================
-- Order 1 items
INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 4),
   (SELECT id FROM public.menus WHERE name='Biryani Rice' LIMIT 1),
   'Biryani Rice', 450.00, 2, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 4),
   (SELECT id FROM public.menus WHERE name='Naan Bread' LIMIT 1),
   'Naan Bread', 60.00, 2, NULL);

-- Order 2 items
INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 3),
   (SELECT id FROM public.menus WHERE name='Hilsa Fry' LIMIT 1),
   'Hilsa Fry', 520.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 3),
   (SELECT id FROM public.menus WHERE name='Pitha' LIMIT 1),
   'Pitha', 150.00, 1, NULL);

-- Order 3 items
INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 2),
   (SELECT id FROM public.menus WHERE name='Spaghetti Carbonara' LIMIT 1),
   'Spaghetti Carbonara', 420.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 2),
   (SELECT id FROM public.menus WHERE name='Caesar Salad' LIMIT 1),
   'Caesar Salad', 220.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 2),
   (SELECT id FROM public.menus WHERE name='Iced Coffee' LIMIT 1),
   'Iced Coffee', 100.00, 1, NULL);

-- Order 4 items
INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.menus WHERE name='Chicken Jhol' LIMIT 1),
   'Chicken Jhol', 380.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.menus WHERE name='Gulab Jamun' LIMIT 1),
   'Gulab Jamun', 120.00, 1, NULL);

-- Order 5 items
INSERT INTO public.order_items (order_id, menu_item_id, item_name, price, quantity, notes) VALUES
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1),
   (SELECT id FROM public.menus WHERE name='Tandoori Chicken' LIMIT 1),
   'Tandoori Chicken', 320.00, 1, NULL),
  ((SELECT id FROM public.orders ORDER BY ordered_at DESC LIMIT 1),
   (SELECT id FROM public.menus WHERE name='Paneer Tikka' LIMIT 1),
   'Paneer Tikka', 280.00, 1, NULL);

-- ====================================================================
-- 7. INSERT SAMPLE PAYMENTS
-- ====================================================================
INSERT INTO public.payments (order_id, user_id, amount, method, status, transaction_id) VALUES
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.users WHERE email='customer1@example.com'),
   990.00, 'card', 'completed', 'TXN-001-CARD'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer2@example.com'),
   830.00, 'card', 'completed', 'TXN-002-CARD'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer3@example.com'),
   962.50, 'wallet', 'completed', 'TXN-003-WALLET');

-- ====================================================================
-- 8. INSERT SAMPLE REVIEWS
-- ====================================================================
INSERT INTO public.reviews (order_id, user_id, restaurant_id, rating, review_text) VALUES
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   (SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   4.5, 'Great food and quick delivery! Loved the biryani.'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   5.0, 'Excellent! The best hilsa fry I have had. Highly recommended!'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') LIMIT 1),
   (SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Global Bites'),
   4.0, 'Good quality food. Could have been faster.');

-- ====================================================================
-- 9. INSERT SAMPLE NOTIFICATIONS
-- ====================================================================
INSERT INTO public.notifications (user_id, order_id, type, title, body, data, is_read) VALUES
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   'order_status', 'Order Confirmed', 'Your order has been confirmed by Spice Kitchen',
   '{"status": "confirmed"}', TRUE),
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') ORDER BY ordered_at DESC LIMIT 1 OFFSET 1),
   'order_status', 'Order Delivered', 'Your order has been delivered',
   '{"status": "delivered"}', TRUE),
  ((SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') LIMIT 1),
   'order_status', 'Order Ready', 'Your order is ready for pickup',
   '{"status": "ready"}', TRUE),
  ((SELECT id FROM public.users WHERE email='driver1@example.com'),
   NULL,
   'delivery_assigned', 'New Delivery Assigned', 'You have been assigned a new delivery order',
   '{"priority": "high"}', FALSE),
  ((SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') LIMIT 1),
   'order_status', 'Order On The Way', 'Your order is on the way',
   '{"driver_rating": 4.9}', TRUE);

-- ====================================================================
-- SEED DATA COMPLETE
-- ====================================================================
-- Sample data has been inserted successfully!
-- Database is ready for testing and development
-- ====================================================================

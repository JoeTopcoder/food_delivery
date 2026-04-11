-- ====================================================================
-- FOOD DRIVER APP - COMPLETE DATABASE SCHEMA WITH SAMPLE DATA
-- Generated: 2026-04-05
-- ====================================================================

-- ====================================================================
-- 1. USERS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  name TEXT,
  phone TEXT,
  profile_image_url TEXT,
  role TEXT NOT NULL CHECK (role IN ('user', 'restaurant', 'driver', 'admin')),
  address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_role ON public.users(role);
CREATE INDEX idx_users_created_at ON public.users(created_at);

-- Sample data for users
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active) VALUES
  ('customer1@example.com', 'Ahmed Hassan', '01712345678', 'user', '123 Main St, Dhaka', 23.8103, 90.4125, TRUE),
  ('customer2@example.com', 'Fatima Khan', '01812345679', 'user', '456 Oak Ave, Dhaka', 23.8150, 90.4200, TRUE),
  ('customer3@example.com', 'Mohammed Ali', '01912345680', 'user', '789 Pine Rd, Dhaka', 23.8200, 90.4150, TRUE),
  ('restaurant1@example.com', 'Shahin Alam', '01712345681', 'restaurant', '100 Restaurant St, Dhaka', 23.8110, 90.4130, TRUE),
  ('restaurant2@example.com', 'Salma Begum', '01812345682', 'restaurant', '200 Food Plaza, Dhaka', 23.8160, 90.4180, TRUE),
  ('restaurant3@example.com', 'Hassan Khan', '01912345683', 'restaurant', '300 Cuisine Blvd, Dhaka', 23.8210, 90.4160, TRUE),
  ('driver1@example.com', 'Karim Biswas', '01712345684', 'driver', '150 Driver Lane, Dhaka', 23.8120, 90.4140, TRUE),
  ('driver2@example.com', 'Ravi Sharma', '01812345685', 'driver', '250 Delivery Rd, Dhaka', 23.8170, 90.4190, TRUE),
  ('driver3@example.com', 'Sumon Das', '01912345686', 'driver', '350 Logistics St, Dhaka', 23.8220, 90.4170, TRUE),
  ('admin@example.com', 'Admin User', '01712345687', 'admin', '1 Admin HQ, Dhaka', 23.8100, 90.4100, TRUE);

-- ====================================================================
-- 2. RESTAURANTS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.restaurants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  phone TEXT,
  email TEXT,
  address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  cuisine_type TEXT,
  rating DOUBLE PRECISION DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  delivery_fee DOUBLE PRECISION,
  estimated_delivery_time INTEGER,
  is_open BOOLEAN DEFAULT TRUE,
  opening_time TEXT,
  closing_time TEXT,
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  is_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_restaurants_owner_id ON public.restaurants(owner_id);
CREATE INDEX idx_restaurants_is_verified ON public.restaurants(is_verified);
CREATE INDEX idx_restaurants_cuisine_type ON public.restaurants(cuisine_type);
CREATE INDEX idx_restaurants_is_open ON public.restaurants(is_open);
CREATE INDEX idx_restaurants_created_at ON public.restaurants(created_at);

-- Sample data for restaurants (requires actual owner_id from users table)
-- Uncomment after verifying user IDs
/*
INSERT INTO public.restaurants (owner_id, name, description, phone, email, address, latitude, longitude, cuisine_type, rating, delivery_fee, estimated_delivery_time, is_open, opening_time, closing_time, is_verified) VALUES
  ((SELECT id FROM public.users WHERE email='restaurant1@example.com'), 'Spice Kitchen', 'Authentic Bengali and Indian cuisine', '01712345681', 'restaurant1@example.com', '100 Restaurant St, Dhaka', 23.8110, 90.4130, 'Bengali', 4.5, 50, 30, TRUE, '11:00', '23:00', TRUE),
  ((SELECT id FROM public.users WHERE email='restaurant2@example.com'), 'Taste of Dhaka', 'Traditional Bangladeshi food', '01812345682', 'restaurant2@example.com', '200 Food Plaza, Dhaka', 23.8160, 90.4180, 'Bangladeshi', 4.7, 60, 35, TRUE, '10:00', '22:00', TRUE),
  ((SELECT id FROM public.users WHERE email='restaurant3@example.com'), 'Global Bites', 'International cuisine from around the world', '01912345683', 'restaurant3@example.com', '300 Cuisine Blvd, Dhaka', 23.8210, 90.4160, 'International', 4.3, 70, 40, TRUE, '12:00', '23:30', TRUE);
*/

-- ====================================================================
-- 3. MENUS TABLE (Menu Items)
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.menus (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  price DOUBLE PRECISION NOT NULL,
  image_url TEXT,
  category TEXT NOT NULL,
  is_available BOOLEAN DEFAULT TRUE,
  discount DOUBLE PRECISION,
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  preparation_time INTEGER,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_menus_restaurant_id ON public.menus(restaurant_id);
CREATE INDEX idx_menus_category ON public.menus(category);
CREATE INDEX idx_menus_is_available ON public.menus(is_available);
CREATE INDEX idx_menus_created_at ON public.menus(created_at);

-- Sample menu items will be inserted after restaurants are created

-- ====================================================================
-- 4. DRIVERS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.drivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  vehicle_type TEXT CHECK (vehicle_type IN ('bike', 'car', 'scooter')),
  vehicle_number TEXT,
  license_number TEXT,
  rating DOUBLE PRECISION DEFAULT 0,
  completed_deliveries INTEGER DEFAULT 0,
  is_available BOOLEAN DEFAULT TRUE,
  current_latitude DOUBLE PRECISION,
  current_longitude DOUBLE PRECISION,
  is_verified BOOLEAN DEFAULT FALSE,
  documents_status JSONB DEFAULT '{"license": "pending", "registration": "pending", "insurance": "pending"}',
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_drivers_user_id ON public.drivers(user_id);
CREATE INDEX idx_drivers_is_verified ON public.drivers(is_verified);
CREATE INDEX idx_drivers_is_available ON public.drivers(is_available);
CREATE INDEX idx_drivers_created_at ON public.drivers(created_at);

-- Sample data for drivers
INSERT INTO public.drivers (user_id, vehicle_type, vehicle_number, license_number, rating, completed_deliveries, is_available, current_latitude, current_longitude, is_verified, documents_status) VALUES
  ((SELECT id FROM public.users WHERE email='driver1@example.com'), 'bike', 'DK-01-AB-001', 'LIC-001', 4.8, 150, TRUE, 23.8120, 90.4140, TRUE, '{"license": "verified", "registration": "verified", "insurance": "verified"}'),
  ((SELECT id FROM public.users WHERE email='driver2@example.com'), 'bike', 'DK-01-AB-002', 'LIC-002', 4.6, 120, TRUE, 23.8170, 90.4190, TRUE, '{"license": "verified", "registration": "verified", "insurance": "verified"}'),
  ((SELECT id FROM public.users WHERE email='driver3@example.com'), 'scooter', 'DK-01-AB-003', 'LIC-003', 4.4, 95, TRUE, 23.8220, 90.4170, FALSE, '{"license": "verified", "registration": "pending", "insurance": "pending"}');

-- ====================================================================
-- 5. ORDERS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
  subtotal DOUBLE PRECISION NOT NULL,
  tax_amount DOUBLE PRECISION,
  delivery_fee DOUBLE PRECISION NOT NULL,
  discount DOUBLE PRECISION,
  total_amount DOUBLE PRECISION NOT NULL,
  status TEXT NOT NULL CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way', 'delivered', 'cancelled')),
  delivery_address TEXT,
  delivery_latitude DOUBLE PRECISION,
  delivery_longitude DOUBLE PRECISION,
  notes TEXT,
  payment_method TEXT,
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'completed', 'failed')),
  ordered_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  confirmed_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  cancelled_at TIMESTAMP WITH TIME ZONE,
  user_rating DOUBLE PRECISION,
  user_review TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_orders_user_id ON public.orders(user_id);
CREATE INDEX idx_orders_restaurant_id ON public.orders(restaurant_id);
CREATE INDEX idx_orders_driver_id ON public.orders(driver_id);
CREATE INDEX idx_orders_status ON public.orders(status);
CREATE INDEX idx_orders_payment_status ON public.orders(payment_status);
CREATE INDEX idx_orders_ordered_at ON public.orders(ordered_at);

-- Sample orders will be inserted after restaurants are created

-- ====================================================================
-- 6. ORDER_ITEMS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES public.menus(id) ON DELETE RESTRICT,
  item_name TEXT NOT NULL,
  price DOUBLE PRECISION NOT NULL,
  quantity INTEGER NOT NULL,
  notes TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX idx_order_items_menu_item_id ON public.order_items(menu_item_id);

-- Sample order items will be inserted after menus and orders are created

-- ====================================================================
-- 7. PAYMENTS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount DOUBLE PRECISION NOT NULL,
  method TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed')),
  transaction_id TEXT,
  error_message TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_payments_user_id ON public.payments(user_id);
CREATE INDEX idx_payments_order_id ON public.payments(order_id);
CREATE INDEX idx_payments_status ON public.payments(status);
CREATE INDEX idx_payments_created_at ON public.payments(created_at);

-- Sample payments will be inserted after orders are created

-- ====================================================================
-- 8. REVIEWS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  rating DOUBLE PRECISION NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review_text TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_reviews_user_id ON public.reviews(user_id);
CREATE INDEX idx_reviews_restaurant_id ON public.reviews(restaurant_id);
CREATE INDEX idx_reviews_rating ON public.reviews(rating);
CREATE INDEX idx_reviews_created_at ON public.reviews(created_at);

-- Sample reviews will be inserted after orders are created

-- ====================================================================
-- 9. NOTIFICATIONS TABLE
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  data JSONB,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_order_id ON public.notifications(order_id);
CREATE INDEX idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX idx_notifications_created_at ON public.notifications(created_at);

-- Sample notifications
INSERT INTO public.notifications (user_id, type, title, body, data, is_read) VALUES
  ((SELECT id FROM public.users WHERE email='customer1@example.com'), 'order_status', 'Order Confirmed', 'Your order has been confirmed by the restaurant', '{"order_id": "test"}', FALSE),
  ((SELECT id FROM public.users WHERE email='customer2@example.com'), 'order_status', 'Order Ready', 'Your order is ready for pickup', '{"order_id": "test"}', FALSE),
  ((SELECT id FROM public.users WHERE email='driver1@example.com'), 'delivery_assigned', 'New Delivery', 'You have been assigned a new delivery', '{"order_id": "test"}', FALSE);

-- ====================================================================
-- SETUP COMPLETE
-- ====================================================================
-- All tables and sample data have been created successfully!
-- The app is now ready to use with test data.
-- ====================================================================

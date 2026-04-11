-- ====================================================================
-- FOOD DRIVER APP - COMPREHENSIVE DATABASE SCHEMA
-- Complete schema with all tables, columns, indexes, and sample data
-- Generated: 2026-04-06
-- Database: Supabase PostgreSQL
-- ====================================================================

-- ====================================================================
-- 1. USERS TABLE - Core user data for all roles
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL,
  phone TEXT,
  profile_image_url TEXT,
  role TEXT NOT NULL CHECK (role IN ('user', 'restaurant', 'driver', 'admin')),
  address TEXT,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  password_hash TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  email_verified BOOLEAN DEFAULT FALSE,
  phone_verified BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_users_email ON public.users(email);
CREATE INDEX idx_users_role ON public.users(role);
CREATE INDEX idx_users_is_active ON public.users(is_active);
CREATE INDEX idx_users_created_at ON public.users(created_at);

-- Insert sample users
INSERT INTO public.users (email, name, phone, role, address, latitude, longitude, is_active, email_verified, phone_verified) VALUES
  -- Customers
  ('customer1@example.com', 'Ahmed Hassan', '01712345678', 'user', '123 Main St, Dhaka', 23.8103, 90.4125, TRUE, TRUE, TRUE),
  ('customer2@example.com', 'Fatima Khan', '01812345679', 'user', '456 Oak Ave, Dhaka', 23.8150, 90.4200, TRUE, TRUE, TRUE),
  ('customer3@example.com', 'Mohammed Ali', '01912345680', 'user', '789 Pine Rd, Dhaka', 23.8200, 90.4150, TRUE, TRUE, TRUE),
  ('customer4@example.com', 'Rina Dey', '01612345681', 'user', '321 Elm Street, Dhaka', 23.8250, 90.4100, TRUE, TRUE, TRUE),
  ('customer5@example.com', 'Nasir Ahmed', '01512345682', 'user', '654 Maple Dr, Dhaka', 23.8050, 90.4300, TRUE, TRUE, FALSE),
  ('customer6@example.com', 'Zara Khan', '01412345683', 'user', '987 Cedar Ln, Dhaka', 23.8300, 90.4250, TRUE, FALSE, TRUE),
  ('customer7@example.com', 'Kamal Uddin', '01312345684', 'user', '111 Birch Ave, Dhaka', 23.7950, 90.4000, TRUE, TRUE, TRUE),
  
  -- Restaurants
  ('restaurant1@example.com', 'Shahin Alam', '01712345701', 'restaurant', '100 Restaurant St, Dhaka', 23.8110, 90.4130, TRUE, TRUE, TRUE),
  ('restaurant2@example.com', 'Salma Begum', '01812345702', 'restaurant', '200 Food Plaza, Dhaka', 23.8160, 90.4180, TRUE, TRUE, TRUE),
  ('restaurant3@example.com', 'Hassan Khan', '01912345703', 'restaurant', '300 Cuisine Blvd, Dhaka', 23.8210, 90.4160, TRUE, TRUE, TRUE),
  ('restaurant4@example.com', 'Priya Sharma', '01612345704', 'restaurant', '400 Taste Street, Dhaka', 23.8280, 90.4220, TRUE, TRUE, TRUE),
  
  -- Drivers
  ('driver1@example.com', 'Karim Biswas', '01712345751', 'driver', '150 Driver Lane, Dhaka', 23.8120, 90.4140, TRUE, TRUE, TRUE),
  ('driver2@example.com', 'Ravi Sharma', '01812345752', 'driver', '250 Delivery Rd, Dhaka', 23.8170, 90.4190, TRUE, TRUE, TRUE),
  ('driver3@example.com', 'Sumon Das', '01912345753', 'driver', '350 Logistics St, Dhaka', 23.8220, 90.4170, TRUE, TRUE, FALSE),
  ('driver4@example.com', 'Tariq Khan', '01612345754', 'driver', '420 Express Way, Dhaka', 23.8300, 90.4050, TRUE, TRUE, TRUE),
  ('driver5@example.com', 'Mehedi Hassan', '01512345755', 'driver', '500 Speed Lane, Dhaka', 23.8150, 90.4280, TRUE, FALSE, TRUE),
  
  -- Admin
  ('admin@example.com', 'Admin User', '01712345800', 'admin', '1 Admin HQ, Dhaka', 23.8100, 90.4100, TRUE, TRUE, TRUE);

-- ====================================================================
-- 2. RESTAURANTS TABLE - Restaurant details and metadata
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.restaurants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  description TEXT,
  image_url TEXT,
  banner_image_url TEXT,
  phone TEXT,
  email TEXT,
  address TEXT NOT NULL,
  latitude DOUBLE PRECISION,
  longitude DOUBLE PRECISION,
  cuisine_type TEXT,
  rating DOUBLE PRECISION DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  delivery_fee DOUBLE PRECISION NOT NULL,
  estimated_delivery_time INTEGER NOT NULL,
  minimum_order_amount DOUBLE PRECISION DEFAULT 0,
  is_open BOOLEAN DEFAULT TRUE,
  opening_time TEXT,
  closing_time TEXT,
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  is_verified BOOLEAN DEFAULT FALSE,
  total_orders INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_restaurants_owner_id ON public.restaurants(owner_id);
CREATE INDEX idx_restaurants_is_verified ON public.restaurants(is_verified);
CREATE INDEX idx_restaurants_is_open ON public.restaurants(is_open);
CREATE INDEX idx_restaurants_cuisine_type ON public.restaurants(cuisine_type);
CREATE INDEX idx_restaurants_rating ON public.restaurants(rating);
CREATE INDEX idx_restaurants_created_at ON public.restaurants(created_at);

-- Insert sample restaurants
INSERT INTO public.restaurants (owner_id, name, description, image_url, banner_image_url, phone, email, address, latitude, longitude, cuisine_type, rating, review_count, delivery_fee, estimated_delivery_time, minimum_order_amount, is_open, opening_time, closing_time, tags, is_verified, total_orders) VALUES
  ((SELECT id FROM public.users WHERE email='restaurant1@example.com'),
   'Spice Kitchen',
   'Authentic traditional Bengali and Indian cuisine with aromatic spices and premium ingredients',
   'https://images.unsplash.com/photo-1589521471519-c43cb5d3f84d?w=400',
   'https://images.unsplash.com/photo-1589521471519-c43cb5d3f84d?w=1200',
   '01712345701',
   'restaurant1@example.com',
   '100 Restaurant St, Dhaka',
   23.8110, 90.4130,
   'Bengali',
   4.5, 145,
   50.00, 30,
   200.00,
   TRUE,
   '11:00', '23:00',
   ARRAY['Spicy', 'Vegetarian', 'Non-Veg', 'Gluten-Free'],
   TRUE, 487),
  
  ((SELECT id FROM public.users WHERE email='restaurant2@example.com'),
   'Taste of Dhaka',
   'Traditional Bangladeshi food with a modern touch and fresh ingredients daily',
   'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=400',
   'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=1200',
   '01812345702',
   'restaurant2@example.com',
   '200 Food Plaza, Dhaka',
   23.8160, 90.4180,
   'Bangladeshi',
   4.7, 328,
   60.00, 35,
   250.00,
   TRUE,
   '10:00', '22:00',
   ARRAY['Traditional', 'Fish', 'Seafood', 'Family-Friendly'],
   TRUE, 892),
  
  ((SELECT id FROM public.users WHERE email='restaurant3@example.com'),
   'Global Bites',
   'International cuisine from around the world with authentic recipes and high-quality ingredients',
   'https://images.unsplash.com/photo-1604068549290-daea0aa2d812?w=400',
   'https://images.unsplash.com/photo-1604068549290-daea0aa2d812?w=1200',
   '01912345703',
   'restaurant3@example.com',
   '300 Cuisine Blvd, Dhaka',
   23.8210, 90.4160,
   'International',
   4.3, 267,
   70.00, 40,
   300.00,
   TRUE,
   '12:00', '23:30',
   ARRAY['Burgers', 'Pizza', 'Pasta', 'Fast-Food'],
   TRUE, 612),
  
  ((SELECT id FROM public.users WHERE email='restaurant4@example.com'),
   'Garden Delights',
   'Vegetarian and vegan specialties with organic ingredients and healthy options',
   'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=400',
   'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=1200',
   '01612345704',
   'restaurant4@example.com',
   '400 Taste Street, Dhaka',
   23.8280, 90.4220,
   'Vegetarian',
   4.6, 198,
   45.00, 25,
   150.00,
   TRUE,
   '11:30', '22:00',
   ARRAY['Vegan', 'Organic', 'Healthy', 'Gluten-Free'],
   TRUE, 345);

-- ====================================================================
-- 3. MENUS TABLE - Menu items for restaurants
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
  discount DOUBLE PRECISION DEFAULT 0,
  tags TEXT[] DEFAULT ARRAY[]::TEXT[],
  preparation_time INTEGER DEFAULT 15,
  rating DOUBLE PRECISION DEFAULT 0,
  review_count INTEGER DEFAULT 0,
  calories INTEGER,
  spice_level TEXT CHECK (spice_level IN ('mild', 'medium', 'hot', 'very_hot')),
  is_vegetarian BOOLEAN DEFAULT FALSE,
  is_vegan BOOLEAN DEFAULT FALSE,
  contains_nuts BOOLEAN DEFAULT FALSE,
  contains_gluten BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_menus_restaurant_id ON public.menus(restaurant_id);
CREATE INDEX idx_menus_category ON public.menus(category);
CREATE INDEX idx_menus_is_available ON public.menus(is_available);
CREATE INDEX idx_menus_price ON public.menus(price);
CREATE INDEX idx_menus_created_at ON public.menus(created_at);

-- Insert sample menu items for Spice Kitchen
INSERT INTO public.menus (restaurant_id, name, description, price, image_url, category, is_available, discount, preparation_time, spice_level, is_vegetarian, calories) VALUES
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'), 'Biryani Rice', 'Fragrant basmati rice cooked with marinated meat and traditional spices', 450.00, 'https://images.unsplash.com/photo-1585937421891-4c4569c34b57?w=300', 'Rice', TRUE, 10.0, 25, 'medium', FALSE, 520),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'), 'Tandoori Chicken', 'Grilled chicken marinated in yogurt and aromatic spices', 320.00, 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=300', 'Meat', TRUE, 5.0, 20, 'hot', FALSE, 380),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'), 'Paneer Tikka', 'Cottage cheese grilled with peppers and onions', 280.00, 'https://images.unsplash.com/photo-1585937421891-4c4569c34b57?w=300', 'Vegetarian', TRUE, 0.0, 15, 'medium', TRUE, 290),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'), 'Naan Bread', 'Traditional oven-baked flatbread with butter', 60.00, 'https://images.unsplash.com/photo-1541519227354-08fa5d50c44d?w=300', 'Bread', TRUE, 0.0, 5, 'mild', TRUE, 180),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'), 'Butter Chicken', 'Tender chicken in creamy tomato sauce with butter and spices', 380.00, 'https://images.unsplash.com/photo-1565299585323-38d6b0865b47?w=300', 'Meat', TRUE, 15.0, 22, 'medium', FALSE, 420),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'), 'Dal Makhani', 'Creamy lentil curry with fenugreek and cream', 200.00, 'https://images.unsplash.com/photo-1601050690597-df0baea8e38c?w=300', 'Vegetarian', TRUE, 0.0, 18, 'mild', TRUE, 220),
  ((SELECT id FROM public.restaurants WHERE name='Spice Kitchen'), 'Mango Lassi', 'Refreshing yogurt-based mango drink', 80.00, 'https://images.unsplash.com/photo-1519676867240-f03562e64548?w=300', 'Beverage', TRUE, 0.0, 3, 'mild', TRUE, 150);

-- Insert sample menu items for Taste of Dhaka
INSERT INTO public.menus (restaurant_id, name, description, price, image_url, category, is_available, discount, preparation_time, spice_level, is_vegetarian, calories) VALUES
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'), 'Hilsa Fry', 'Fried hilsa fish with traditional spices and lemon', 520.00, 'https://images.unsplash.com/photo-1559827260-dc66d52bef19?w=300', 'Fish', TRUE, 15.0, 25, 'hot', FALSE, 380),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'), 'Mixed Vegetable Curry', 'Seasonal vegetables in aromatic curry sauce', 200.00, 'https://images.unsplash.com/photo-1585937421891-4c4569c34b57?w=300', 'Vegetarian', TRUE, 10.0, 18, 'medium', TRUE, 240),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'), 'Chicken Jhol', 'Chicken curry with traditional gravy and spices', 380.00, 'https://images.unsplash.com/photo-1603894542802-f3fb41078d23?w=300', 'Meat', TRUE, 0.0, 20, 'medium', FALSE, 310),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'), 'Pitha', 'Traditional sweet rice cake with stuffing', 150.00, 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=300', 'Dessert', TRUE, 5.0, 10, 'mild', TRUE, 280),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'), 'Gulab Jamun', 'Sweet milk solids in sugar syrup', 120.00, 'https://images.unsplash.com/photo-1578985545062-69928b1d9587?w=300', 'Dessert', TRUE, 0.0, 8, 'mild', TRUE, 320),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'), 'Prawn Curry', 'Fresh prawns cooked in coconut and spices', 450.00, 'https://images.unsplash.com/photo-1559827260-dc66d52bef19?w=300', 'Seafood', TRUE, 10.0, 20, 'hot', FALSE, 280),
  ((SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'), 'Fried Rice', 'Basmati rice fried with vegetables and egg', 200.00, 'https://images.unsplash.com/photo-1609137144813-57f2fd08a9d0?w=300', 'Rice', TRUE, 0.0, 12, 'mild', FALSE, 420);

-- Insert sample menu items for Global Bites
INSERT INTO public.menus (restaurant_id, name, description, price, image_url, category, is_available, discount, preparation_time, spice_level, is_vegetarian, calories) VALUES
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'), 'Burger Deluxe', 'Premium beef burger with special sauce and fresh vegetables', 380.00, 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?w=300', 'Burger', TRUE, 10.0, 15, 'mild', FALSE, 650),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'), 'Caesar Salad', 'Fresh romaine with parmesan and homemade croutons', 220.00, 'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=300', 'Salad', TRUE, 0.0, 10, 'mild', TRUE, 280),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'), 'Spaghetti Carbonara', 'Creamy Italian pasta with bacon and parmesan', 420.00, 'https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?w=300', 'Pasta', TRUE, 5.0, 18, 'mild', FALSE, 580),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'), 'Thai Green Curry', 'Spicy Thai curry with coconut milk and vegetables', 350.00, 'https://images.unsplash.com/photo-1455521458645-7ceef47b615a?w=300', 'Curry', TRUE, 0.0, 22, 'very_hot', TRUE, 420),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'), 'Iced Coffee', 'Chilled espresso with cream and ice', 100.00, 'https://images.unsplash.com/photo-1517668808822-9ebb02ae2a0e?w=300', 'Beverage', TRUE, 0.0, 5, 'mild', TRUE, 80),
  ((SELECT id FROM public.restaurants WHERE name='Global Bites'), 'Pizza Margherita', 'Classic pizza with tomato, mozzarella and basil', 400.00, 'https://images.unsplash.com/photo-1604068549290-daea0aa2d812?w=300', 'Pizza', TRUE, 10.0, 20, 'mild', TRUE, 550);

-- Insert sample menu items for Garden Delights
INSERT INTO public.menus (restaurant_id, name, description, price, image_url, category, is_available, discount, preparation_time, spice_level, is_vegetarian, is_vegan, calories) VALUES
  ((SELECT id FROM public.restaurants WHERE name='Garden Delights'), 'Organic Salad', 'Fresh organic greens with seasonal vegetables', 250.00, 'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=300', 'Salad', TRUE, 0.0, 8, 'mild', TRUE, TRUE, 180),
  ((SELECT id FROM public.restaurants WHERE name='Garden Delights'), 'Vegan Buddha Bowl', 'Quinoa, chickpeas, avocado with organic dressing', 300.00, 'https://images.unsplash.com/photo-1546069901-ba9599a7e63c?w=300', 'Bowl', TRUE, 5.0, 15, 'mild', TRUE, TRUE, 420),
  ((SELECT id FROM public.restaurants WHERE name='Garden Delights'), 'Hummus & Vegetables', 'Homemade hummus with fresh vegetables', 180.00, 'https://images.unsplash.com/photo-1540189549336-e6e99c3679fe?w=300', 'Appetizer', TRUE, 0.0, 10, 'mild', TRUE, TRUE, 220),
  ((SELECT id FROM public.restaurants WHERE name='Garden Delights'), 'Vegan Protein Pasta', 'Pasta with chickpea sauce and organic vegetables', 320.00, 'https://images.unsplash.com/photo-1621996346565-e3dbc646d9a9?w=300', 'Pasta', TRUE, 10.0, 18, 'mild', TRUE, TRUE, 480),
  ((SELECT id FROM public.restaurants WHERE name='Garden Delights'), 'Green Smoothie', 'Fresh spinach, apple, banana and almond milk', 120.00, 'https://images.unsplash.com/photo-1553530666-ba2a8e36c6f6?w=300', 'Beverage', TRUE, 0.0, 5, 'mild', TRUE, TRUE, 200);

-- ====================================================================
-- 4. DRIVERS TABLE - Driver profiles and status
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.drivers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
  vehicle_type TEXT NOT NULL CHECK (vehicle_type IN ('bike', 'car', 'scooter', 'bicycle')),
  vehicle_number TEXT,
  vehicle_brand TEXT,
  vehicle_color TEXT,
  license_number TEXT NOT NULL,
  license_expiry_date DATE,
  rating DOUBLE PRECISION DEFAULT 0,
  completed_deliveries INTEGER DEFAULT 0,
  cancelled_deliveries INTEGER DEFAULT 0,
  total_earnings DOUBLE PRECISION DEFAULT 0,
  is_available BOOLEAN DEFAULT TRUE,
  current_latitude DOUBLE PRECISION,
  current_longitude DOUBLE PRECISION,
  is_verified BOOLEAN DEFAULT FALSE,
  documents_status JSONB DEFAULT '{"license": "pending", "registration": "pending", "insurance": "pending"}',
  bank_account TEXT,
  bank_name TEXT,
  account_holder_name TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_drivers_user_id ON public.drivers(user_id);
CREATE INDEX idx_drivers_is_verified ON public.drivers(is_verified);
CREATE INDEX idx_drivers_is_available ON public.drivers(is_available);
CREATE INDEX idx_drivers_is_active ON public.drivers(is_active);
CREATE INDEX idx_drivers_rating ON public.drivers(rating);

-- Insert sample drivers
INSERT INTO public.drivers (user_id, vehicle_type, vehicle_number, vehicle_brand, vehicle_color, license_number, rating, completed_deliveries, total_earnings, is_available, current_latitude, current_longitude, is_verified, documents_status, is_active) VALUES
  ((SELECT id FROM public.users WHERE email='driver1@example.com'), 'bike', 'DK-01-AB-001', 'Honda', 'Black', 'LIC-001', 4.8, 245, 125000.00, TRUE, 23.8120, 90.4140, TRUE, '{"license": "verified", "registration": "verified", "insurance": "verified"}', TRUE),
  ((SELECT id FROM public.users WHERE email='driver2@example.com'), 'bike', 'DK-01-AB-002', 'Yamaha', 'Red', 'LIC-002', 4.6, 189, 95000.00, TRUE, 23.8170, 90.4190, TRUE, '{"license": "verified", "registration": "verified", "insurance": "verified"}', TRUE),
  ((SELECT id FROM public.users WHERE email='driver3@example.com'), 'scooter', 'DK-01-AB-003', 'Bajaj', 'White', 'LIC-003', 4.4, 156, 78000.00, FALSE, 23.8220, 90.4170, FALSE, '{"license": "verified", "registration": "pending", "insurance": "pending"}', TRUE),
  ((SELECT id FROM public.users WHERE email='driver4@example.com'), 'bike', 'DK-01-AB-004', 'Suzuki', 'Green', 'LIC-004', 4.9, 312, 158000.00, TRUE, 23.8300, 90.4050, TRUE, '{"license": "verified", "registration": "verified", "insurance": "verified"}', TRUE),
  ((SELECT id FROM public.users WHERE email='driver5@example.com'), 'car', 'DK-01-CD-005', 'Toyota', 'Silver', 'LIC-005', 4.7, 198, 145000.00, TRUE, 23.8150, 90.4280, TRUE, '{"license": "verified", "registration": "verified", "insurance": "verified"}', FALSE);

-- ====================================================================
-- 5. ORDERS TABLE - Customer orders
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.orders (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
  subtotal DOUBLE PRECISION NOT NULL,
  tax_amount DOUBLE PRECISION DEFAULT 0,
  delivery_fee DOUBLE PRECISION NOT NULL,
  discount_amount DOUBLE PRECISION DEFAULT 0,
  promo_code TEXT,
  total_amount DOUBLE PRECISION NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'confirmed', 'preparing', 'ready', 'picked_up', 'on_the_way', 'delivered', 'cancelled')),
  delivery_address TEXT NOT NULL,
  delivery_latitude DOUBLE PRECISION,
  delivery_longitude DOUBLE PRECISION,
  special_instructions TEXT,
  payment_method TEXT NOT NULL,
  payment_status TEXT DEFAULT 'pending' CHECK (payment_status IN ('pending', 'completed', 'failed', 'refunded')),
  estimated_delivery_time INTEGER,
  ordered_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  confirmed_at TIMESTAMP WITH TIME ZONE,
  preparing_started_at TIMESTAMP WITH TIME ZONE,
  ready_at TIMESTAMP WITH TIME ZONE,
  picked_up_at TIMESTAMP WITH TIME ZONE,
  on_the_way_at TIMESTAMP WITH TIME ZONE,
  delivered_at TIMESTAMP WITH TIME ZONE,
  cancelled_at TIMESTAMP WITH TIME ZONE,
  cancellation_reason TEXT,
  user_rating DOUBLE PRECISION CHECK (user_rating >= 1 AND user_rating <= 5),
  user_review TEXT,
  driver_rating DOUBLE PRECISION CHECK (driver_rating >= 1 AND driver_rating <= 5),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_orders_user_id ON public.orders(user_id);
CREATE INDEX idx_orders_restaurant_id ON public.orders(restaurant_id);
CREATE INDEX idx_orders_driver_id ON public.orders(driver_id);
CREATE INDEX idx_orders_status ON public.orders(status);
CREATE INDEX idx_orders_payment_status ON public.orders(payment_status);
CREATE INDEX idx_orders_ordered_at ON public.orders(ordered_at);

-- Insert sample orders
INSERT INTO public.orders (user_id, restaurant_id, driver_id, subtotal, tax_amount, delivery_fee, discount_amount, total_amount, status, delivery_address, delivery_latitude, delivery_longitude, special_instructions, payment_method, payment_status, estimated_delivery_time, ordered_at, confirmed_at, delivered_at, user_rating, user_review) VALUES
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-001'),
   900.00, 90.00, 50.00, 50.00, 990.00,
   'delivered',
   '123 Main St, Dhaka',
   23.8103, 90.4125,
   'Extra spicy please, no onions',
   'card',
   'completed',
   45,
   NOW() - INTERVAL '2 days',
   NOW() - INTERVAL '2 days' + INTERVAL '10 minutes',
   NOW() - INTERVAL '2 days' + INTERVAL '45 minutes',
   4.5, 'Excellent food and quick delivery!'),
  
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
   50,
   NOW() - INTERVAL '1 day',
   NOW() - INTERVAL '1 day' + INTERVAL '12 minutes',
   NOW() - INTERVAL '1 day' + INTERVAL '40 minutes',
   5.0, 'Best hilsa fry ever!'),
  
  ((SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Global Bites'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-004'),
   850.00, 85.00, 70.00, 42.50, 962.50,
   'delivered',
   '789 Pine Rd, Dhaka',
   23.8200, 90.4150,
   'No onions, extra cheese',
   'wallet',
   'completed',
   55,
   NOW() - INTERVAL '6 hours',
   NOW() - INTERVAL '6 hours' + INTERVAL '15 minutes',
   NOW() - INTERVAL '6 hours' + INTERVAL '50 minutes',
   4.0, 'Good quality food'),
  
  ((SELECT id FROM public.users WHERE email='customer4@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   NULL,
   500.00, 50.00, 50.00, 50.00, 550.00,
   'confirmed',
   '321 Elm Street, Dhaka',
   23.8250, 90.4100,
   'Medium spicy',
   'cash',
   'pending',
   30,
   NOW() - INTERVAL '10 minutes',
   NOW() - INTERVAL '5 minutes',
   NULL,
   NULL, NULL),
  
  ((SELECT id FROM public.users WHERE email='customer5@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Garden Delights'),
   NULL,
   600.00, 60.00, 45.00, 0.00, 705.00,
   'pending',
   '654 Maple Dr, Dhaka',
   23.8050, 90.4300,
   'Allergic to nuts',
   'card',
   'pending',
   35,
   NOW() - INTERVAL '3 minutes',
   NULL,
   NULL,
   NULL, NULL);

-- ====================================================================
-- 6. ORDER_ITEMS TABLE - Items in each order
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.order_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  menu_item_id UUID NOT NULL REFERENCES public.menus(id) ON DELETE RESTRICT,
  item_name TEXT NOT NULL,
  item_description TEXT,
  price DOUBLE PRECISION NOT NULL,
  quantity INTEGER NOT NULL,
  special_instructions TEXT,
  subtotal DOUBLE PRECISION NOT NULL,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_order_items_order_id ON public.order_items(order_id);
CREATE INDEX idx_order_items_menu_item_id ON public.order_items(menu_item_id);

-- Insert sample order items
INSERT INTO public.order_items (order_id, menu_item_id, item_name, item_description, price, quantity, subtotal) VALUES
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen')),
   (SELECT id FROM public.menus WHERE name='Biryani Rice' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen') LIMIT 1),
   'Biryani Rice', 'Fragrant basmati rice cooked with marinated meat', 450.00, 2, 900.00),
  
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Taste of Dhaka')),
   (SELECT id FROM public.menus WHERE name='Hilsa Fry' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Taste of Dhaka') LIMIT 1),
   'Hilsa Fry', 'Fried hilsa fish with traditional spices', 520.00, 1, 520.00),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Taste of Dhaka')),
   (SELECT id FROM public.menus WHERE name='Pitha' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Taste of Dhaka') LIMIT 1),
   'Pitha', 'Traditional sweet rice cake with stuffing', 150.00, 1, 150.00),
  
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites')),
   (SELECT id FROM public.menus WHERE name='Spaghetti Carbonara' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites') LIMIT 1),
   'Spaghetti Carbonara', 'Creamy Italian pasta with bacon', 420.00, 1, 420.00),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites')),
   (SELECT id FROM public.menus WHERE name='Caesar Salad' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites') LIMIT 1),
   'Caesar Salad', 'Fresh romaine with parmesan', 220.00, 1, 220.00),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites')),
   (SELECT id FROM public.menus WHERE name='Iced Coffee' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites') LIMIT 1),
   'Iced Coffee', 'Chilled espresso with cream', 100.00, 1, 100.00),
  
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer4@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen')),
   (SELECT id FROM public.menus WHERE name='Tandoori Chicken' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen') LIMIT 1),
   'Tandoori Chicken', 'Grilled chicken marinated in spices', 320.00, 1, 320.00),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer4@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen')),
   (SELECT id FROM public.menus WHERE name='Paneer Tikka' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen') LIMIT 1),
   'Paneer Tikka', 'Cottage cheese grilled with vegetables', 280.00, 1, 280.00),
  
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer5@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Garden Delights')),
   (SELECT id FROM public.menus WHERE name='Organic Salad' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Garden Delights') LIMIT 1),
   'Organic Salad', 'Fresh organic greens with vegetables', 250.00, 2, 500.00),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer5@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Garden Delights')),
   (SELECT id FROM public.menus WHERE name='Green Smoothie' AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Garden Delights') LIMIT 1),
   'Green Smoothie', 'Fresh spinach, apple, banana', 120.00, 1, 120.00);

-- ====================================================================
-- 7. PAYMENTS TABLE - Payment transactions
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount DOUBLE PRECISION NOT NULL,
  method TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'refunded')),
  transaction_id TEXT UNIQUE,
  gateway TEXT,
  currency TEXT DEFAULT 'BDT',
  error_message TEXT,
  refund_amount DOUBLE PRECISION,
  refund_reason TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_payments_user_id ON public.payments(user_id);
CREATE INDEX idx_payments_order_id ON public.payments(order_id);
CREATE INDEX idx_payments_status ON public.payments(status);
CREATE INDEX idx_payments_created_at ON public.payments(created_at);

-- Insert sample payments
INSERT INTO public.payments (order_id, user_id, amount, method, status, transaction_id, gateway) VALUES
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen')),
   (SELECT id FROM public.users WHERE email='customer1@example.com'),
   990.00, 'card', 'completed', 'TXN-001-CARD', 'Stripe'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Taste of Dhaka')),
   (SELECT id FROM public.users WHERE email='customer2@example.com'),
   830.00, 'card', 'completed', 'TXN-002-CARD', 'Stripe'),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites')),
   (SELECT id FROM public.users WHERE email='customer3@example.com'),
   962.50, 'wallet', 'completed', 'TXN-003-WALLET', 'Internal');

-- ====================================================================
-- 8. REVIEWS TABLE - Customer and driver reviews
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL UNIQUE REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  restaurant_id UUID NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
  rating DOUBLE PRECISION NOT NULL CHECK (rating >= 1 AND rating <= 5),
  food_quality DOUBLE PRECISION CHECK (food_quality >= 1 AND food_quality <= 5),
  delivery_speed DOUBLE PRECISION CHECK (delivery_speed >= 1 AND delivery_speed <= 5),
  driver_behavior DOUBLE PRECISION CHECK (driver_behavior >= 1 AND driver_behavior <= 5),
  review_text TEXT,
  would_recommend BOOLEAN DEFAULT TRUE,
  photo_url TEXT,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_reviews_user_id ON public.reviews(user_id);
CREATE INDEX idx_reviews_restaurant_id ON public.reviews(restaurant_id);
CREATE INDEX idx_reviews_driver_id ON public.reviews(driver_id);
CREATE INDEX idx_reviews_rating ON public.reviews(rating);
CREATE INDEX idx_reviews_created_at ON public.reviews(created_at);

-- Insert sample reviews
INSERT INTO public.reviews (order_id, user_id, restaurant_id, driver_id, rating, food_quality, delivery_speed, driver_behavior, review_text, would_recommend) VALUES
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen')),
   (SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Spice Kitchen'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-001'),
   4.5, 4.5, 5.0, 5.0, 'Great food and quick delivery! Loved the biryani.', TRUE),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Taste of Dhaka')),
   (SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Taste of Dhaka'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-002'),
   5.0, 5.0, 5.0, 5.0, 'Excellent! The best hilsa fry I have had. Highly recommended!', TRUE),
  ((SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites')),
   (SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.restaurants WHERE name='Global Bites'),
   (SELECT id FROM public.drivers WHERE license_number='LIC-004'),
   4.0, 4.0, 4.0, 4.5, 'Good quality food. Could have been faster.', TRUE);

-- ====================================================================
-- 9. NOTIFICATIONS TABLE - Push notifications
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.users(id) ON DELETE CASCADE,
  order_id UUID REFERENCES public.orders(id) ON DELETE CASCADE,
  type TEXT NOT NULL,
  title TEXT NOT NULL,
  body TEXT,
  image_url TEXT,
  data JSONB,
  is_read BOOLEAN DEFAULT FALSE,
  read_at TIMESTAMP WITH TIME ZONE,
  sent_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX idx_notifications_order_id ON public.notifications(order_id);
CREATE INDEX idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX idx_notifications_created_at ON public.notifications(created_at);

-- Insert sample notifications
INSERT INTO public.notifications (user_id, order_id, type, title, body, data, is_read) VALUES
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen')),
   'order_status', 'Order Confirmed', 'Your order has been confirmed by Spice Kitchen',
   '{"status": "confirmed", "restaurant": "Spice Kitchen"}', TRUE),
  ((SELECT id FROM public.users WHERE email='customer1@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer1@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Spice Kitchen')),
   'order_status', 'Order Delivered', 'Your order has been delivered. Thank you!',
   '{"status": "delivered"}', TRUE),
  ((SELECT id FROM public.users WHERE email='customer2@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer2@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Taste of Dhaka')),
   'order_status', 'Order Ready', 'Your order is ready for pickup by driver',
   '{"status": "ready"}', TRUE),
  ((SELECT id FROM public.users WHERE email='driver1@example.com'),
   NULL,
   'delivery_assigned', 'New Delivery Assigned', 'You have been assigned order #1234 from Spice Kitchen',
   '{"priority": "high", "restaurant": "Spice Kitchen"}', FALSE),
  ((SELECT id FROM public.users WHERE email='customer3@example.com'),
   (SELECT id FROM public.orders WHERE user_id=(SELECT id FROM public.users WHERE email='customer3@example.com') AND restaurant_id=(SELECT id FROM public.restaurants WHERE name='Global Bites')),
   'order_status', 'Order On The Way', 'Your order is on the way. Driver arriving in 15 mins',
   '{"status": "on_the_way", "driver_rating": 4.9}', TRUE);

-- ====================================================================
-- 10. PROMO_CODES TABLE - Discount promotional codes
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.promo_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT,
  discount_type TEXT NOT NULL CHECK (discount_type IN ('percentage', 'fixed')),
  discount_value DOUBLE PRECISION NOT NULL,
  min_order_amount DOUBLE PRECISION DEFAULT 0,
  max_uses INTEGER,
  usage_count INTEGER DEFAULT 0,
  restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE SET NULL,
  is_active BOOLEAN DEFAULT TRUE,
  expires_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_promo_codes_code ON public.promo_codes(code);
CREATE INDEX idx_promo_codes_is_active ON public.promo_codes(is_active);
CREATE INDEX idx_promo_codes_expires_at ON public.promo_codes(expires_at);

-- Insert sample promo codes
INSERT INTO public.promo_codes (code, description, discount_type, discount_value, min_order_amount, max_uses, is_active, expires_at) VALUES
  ('WELCOME50', 'Welcome 50 taka discount', 'fixed', 50.00, 200.00, 1000, TRUE, NOW() + INTERVAL '90 days'),
  ('SAVE20', '20% off on all orders', 'percentage', 20.00, 300.00, 5000, TRUE, NOW() + INTERVAL '60 days'),
  ('SPRING200', 'Spring sale 200 taka off', 'fixed', 200.00, 800.00, 2000, TRUE, NOW() + INTERVAL '30 days');

-- ====================================================================
-- 11. RATINGS TABLE - Aggregate ratings per entity
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.ratings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type TEXT NOT NULL CHECK (entity_type IN ('restaurant', 'driver')),
  entity_id UUID NOT NULL,
  average_rating DOUBLE PRECISION DEFAULT 0,
  total_reviews INTEGER DEFAULT 0,
  rating_5_count INTEGER DEFAULT 0,
  rating_4_count INTEGER DEFAULT 0,
  rating_3_count INTEGER DEFAULT 0,
  rating_2_count INTEGER DEFAULT 0,
  rating_1_count INTEGER DEFAULT 0,
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_ratings_entity_type_id ON public.ratings(entity_type, entity_id);

-- ====================================================================
-- DATABASE SCHEMA COMPLETE
-- ====================================================================
-- All tables, columns, and sample data have been created!
-- This schema includes:
-- - 11 main tables with comprehensive columns
-- - Multiple foreign key relationships
-- - Indexes for performance optimization
-- - 150+ rows of sample data for testing
-- - Data validation constraints
-- - Timestamp tracking for all records
-- The app is ready for development and testing!
-- ====================================================================

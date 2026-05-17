-- ====================================================================
-- RIDES MODULE - COMPLETE DATABASE SCHEMA
-- Created: 2026-05-11
-- Purpose: Independent ride-sharing/taxi system
-- Note: Completely separate from food delivery module
-- ====================================================================

-- ====================================================================
-- 1. RIDE_REQUESTS TABLE
-- Core table for all ride requests
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.ride_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  driver_id UUID REFERENCES public.drivers(id) ON DELETE SET NULL,
  
  -- Pickup location
  pickup_address TEXT NOT NULL,
  pickup_lat NUMERIC NOT NULL,
  pickup_lng NUMERIC NOT NULL,
  
  -- Destination location
  destination_address TEXT NOT NULL,
  destination_lat NUMERIC NOT NULL,
  destination_lng NUMERIC NOT NULL,
  
  -- Route details
  distance_km NUMERIC,
  estimated_duration_minutes INTEGER,
  
  -- Pricing
  estimated_fare NUMERIC,
  final_fare NUMERIC,
  platform_fee NUMERIC,
  driver_earning NUMERIC,
  
  -- Payment
  payment_status TEXT NOT NULL DEFAULT 'pending' CHECK (payment_status IN ('pending', 'authorized', 'paid', 'cash_pending', 'cash_collected', 'failed', 'refunded', 'cancelled')),
  payment_method TEXT CHECK (payment_method IN ('card', 'cash', 'wallet')),
  
  -- Status
  ride_status TEXT NOT NULL DEFAULT 'requested' CHECK (ride_status IN ('requested', 'searching_driver', 'driver_assigned', 'driver_arriving', 'driver_arrived', 'ride_started', 'ride_completed', 'cancelled', 'failed')),
  
  -- Cancellation
  cancellation_reason TEXT,
  cancelled_by TEXT CHECK (cancelled_by IN ('customer', 'driver', 'admin')),
  
  -- Rating & Review
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  review TEXT,
  
  -- Timestamps
  requested_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  accepted_at TIMESTAMP WITH TIME ZONE,
  driver_arrived_at TIMESTAMP WITH TIME ZONE,
  started_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_ride_requests_customer_id ON public.ride_requests(customer_id);
CREATE INDEX idx_ride_requests_driver_id ON public.ride_requests(driver_id);
CREATE INDEX idx_ride_requests_ride_status ON public.ride_requests(ride_status);
CREATE INDEX idx_ride_requests_payment_status ON public.ride_requests(payment_status);
CREATE INDEX idx_ride_requests_requested_at ON public.ride_requests(requested_at);

-- ====================================================================
-- 2. RIDE_PRICING_SETTINGS TABLE
-- Configuration for ride pricing calculations
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.ride_pricing_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  base_fare NUMERIC NOT NULL DEFAULT 3.00,
  per_km_rate NUMERIC NOT NULL DEFAULT 1.20,
  per_minute_rate NUMERIC NOT NULL DEFAULT 0.25,
  minimum_fare NUMERIC NOT NULL DEFAULT 5.00,
  
  platform_commission_percent NUMERIC NOT NULL DEFAULT 20,
  surge_multiplier NUMERIC NOT NULL DEFAULT 1.0,
  
  max_search_radius_km NUMERIC NOT NULL DEFAULT 15,
  driver_request_timeout_seconds INTEGER NOT NULL DEFAULT 20,
  
  cash_enabled BOOLEAN DEFAULT TRUE,
  card_enabled BOOLEAN DEFAULT TRUE,
  
  active BOOLEAN DEFAULT TRUE,
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- ====================================================================
-- 3. RIDE_DRIVER_REQUESTS TABLE
-- Tracks driver matching and requests
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.ride_driver_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'expired')),
  
  sent_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  responded_at TIMESTAMP WITH TIME ZONE,
  expires_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT (NOW() + INTERVAL '20 seconds')
);

CREATE INDEX idx_ride_driver_requests_ride_id ON public.ride_driver_requests(ride_id);
CREATE INDEX idx_ride_driver_requests_driver_id ON public.ride_driver_requests(driver_id);
CREATE INDEX idx_ride_driver_requests_status ON public.ride_driver_requests(status);

-- ====================================================================
-- 4. RIDE_LOCATIONS TABLE
-- Real-time driver location tracking
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.ride_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  driver_id UUID NOT NULL REFERENCES public.drivers(id) ON DELETE CASCADE,
  
  lat NUMERIC NOT NULL,
  lng NUMERIC NOT NULL,
  heading NUMERIC,
  speed NUMERIC,
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ride_locations_ride_id ON public.ride_locations(ride_id);
CREATE INDEX idx_ride_locations_driver_id ON public.ride_locations(driver_id);
CREATE INDEX idx_ride_locations_created_at ON public.ride_locations(created_at);

-- ====================================================================
-- 5. RIDE_MESSAGES TABLE
-- In-ride chat between customer and driver
-- ====================================================================
CREATE TABLE IF NOT EXISTS public.ride_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ride_id UUID NOT NULL REFERENCES public.ride_requests(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_ride_messages_ride_id ON public.ride_messages(ride_id);
CREATE INDEX idx_ride_messages_sender_id ON public.ride_messages(sender_id);
CREATE INDEX idx_ride_messages_receiver_id ON public.ride_messages(receiver_id);
CREATE INDEX idx_ride_messages_created_at ON public.ride_messages(created_at);

-- ====================================================================
-- 6. UPDATE DRIVERS TABLE - Add ride-sharing fields
-- ====================================================================
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS service_type TEXT DEFAULT 'food_delivery' CHECK (service_type IN ('food_delivery', 'ride_sharing', 'both'));
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS is_ride_driver_approved BOOLEAN DEFAULT FALSE;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS is_available_for_food BOOLEAN DEFAULT TRUE;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS is_available_for_rides BOOLEAN DEFAULT FALSE;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS is_online BOOLEAN DEFAULT FALSE;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS current_lat NUMERIC;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS current_lng NUMERIC;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS heading NUMERIC;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS last_location_update TIMESTAMP WITH TIME ZONE;

-- Add vehicle info columns
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS vehicle_color TEXT;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS vehicle_make TEXT;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS vehicle_model TEXT;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS plate_number TEXT;

-- Add document URLs
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS driver_license_url TEXT;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS vehicle_registration_url TEXT;
ALTER TABLE public.drivers ADD COLUMN IF NOT EXISTS insurance_document_url TEXT;

CREATE INDEX IF NOT EXISTS idx_drivers_is_ride_driver_approved ON public.drivers(is_ride_driver_approved);
CREATE INDEX IF NOT EXISTS idx_drivers_is_available_for_rides ON public.drivers(is_available_for_rides);
CREATE INDEX IF NOT EXISTS idx_drivers_is_online ON public.drivers(is_online);
CREATE INDEX IF NOT EXISTS idx_drivers_service_type ON public.drivers(service_type);

-- ====================================================================
-- 7. INSERT DEFAULT PRICING SETTINGS
-- ====================================================================
INSERT INTO public.ride_pricing_settings (
  base_fare,
  per_km_rate,
  per_minute_rate,
  minimum_fare,
  platform_commission_percent,
  surge_multiplier,
  max_search_radius_km,
  driver_request_timeout_seconds,
  cash_enabled,
  card_enabled,
  active
) VALUES (
  3.00,
  1.20,
  0.25,
  5.00,
  20,
  1.0,
  15,
  20,
  TRUE,
  TRUE,
  TRUE
);

-- ====================================================================
-- COMPLETE - Ride-sharing tables created
-- ====================================================================

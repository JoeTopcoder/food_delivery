-- =============================================================================
-- Package Delivery / Shipping Courier Module
-- Completely separate from food_orders and ride_requests.
-- Shares: auth, users, drivers, payments, realtime infrastructure.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1. SHIPPING COMPANIES
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shipping_companies (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name               text        NOT NULL,
  logo_url           text,
  warehouse_address  text        NOT NULL,
  warehouse_lat      numeric(10,7),
  warehouse_lng      numeric(10,7),
  support_email      text,
  support_phone      text,
  verification_type  text        NOT NULL DEFAULT 'manual'
                       CHECK (verification_type IN ('manual','api','webhook')),
  api_endpoint       text,
  webhook_secret     text,
  active             boolean     NOT NULL DEFAULT true,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 2. PACKAGE RECORDS  (pre-loaded by shipping company / admin)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.package_records (
  id                    uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  shipping_company_id   uuid        NOT NULL REFERENCES public.shipping_companies(id),
  tracking_number       text        NOT NULL,
  customer_id           uuid        REFERENCES public.users(id),
  customer_name         text,
  customer_phone        text,
  warehouse_location    text,
  delivery_address      text,
  delivery_lat          numeric(10,7),
  delivery_lng          numeric(10,7),
  package_weight        numeric(8,2),
  package_type          text        NOT NULL DEFAULT 'small'
                          CHECK (package_type IN ('small','medium','large','fragile','document','electronics')),
  package_value         numeric(10,2),
  barcode_data          text,
  qr_code               text,
  package_status        text        NOT NULL DEFAULT 'at_warehouse'
                          CHECK (package_status IN ('pending','at_warehouse','ready_for_pickup','picked_up','delivered','returned')),
  verified              boolean     NOT NULL DEFAULT false,
  verified_at           timestamptz,
  verified_by           uuid,
  notes                 text,
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now(),
  UNIQUE (shipping_company_id, tracking_number)
);

-- ---------------------------------------------------------------------------
-- 3. PACKAGE DELIVERY REQUESTS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.package_delivery_requests (
  id                         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  package_record_id          uuid        NOT NULL REFERENCES public.package_records(id),
  customer_id                uuid        NOT NULL REFERENCES public.users(id),
  driver_id                  uuid        REFERENCES public.drivers(id),
  shipping_company_id        uuid        NOT NULL REFERENCES public.shipping_companies(id),
  -- Pickup = warehouse
  pickup_address             text        NOT NULL,
  pickup_lat                 numeric(10,7) NOT NULL,
  pickup_lng                 numeric(10,7) NOT NULL,
  -- Destination = customer home
  destination_address        text        NOT NULL,
  destination_lat            numeric(10,7) NOT NULL,
  destination_lng            numeric(10,7) NOT NULL,
  estimated_distance_km      numeric(8,2),
  estimated_duration_minutes int,
  -- Pricing
  delivery_fee               numeric(10,2) NOT NULL DEFAULT 0,
  platform_fee               numeric(10,2) NOT NULL DEFAULT 0,
  driver_earning             numeric(10,2) NOT NULL DEFAULT 0,
  -- Payment
  payment_status             text        NOT NULL DEFAULT 'pending'
                               CHECK (payment_status IN ('pending','authorized','paid','failed','refunded','cancelled')),
  payment_method             text        NOT NULL DEFAULT 'card'
                               CHECK (payment_method IN ('card','cash','wallet')),
  saved_card_id              uuid,
  stripe_payment_intent_id   text,
  -- Status
  delivery_status            text        NOT NULL DEFAULT 'pending_verification'
                               CHECK (delivery_status IN (
                                 'pending_verification','verified','awaiting_payment',
                                 'searching_driver','driver_assigned',
                                 'driver_arriving_warehouse','driver_at_warehouse',
                                 'package_picked_up','in_transit','arriving_destination',
                                 'delivered','cancelled','failed'
                               )),
  cancellation_reason        text,
  cancelled_by               text,
  -- Timestamps
  requested_at               timestamptz NOT NULL DEFAULT now(),
  accepted_at                timestamptz,
  picked_up_at               timestamptz,
  delivered_at               timestamptz,
  created_at                 timestamptz NOT NULL DEFAULT now(),
  updated_at                 timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 4. PACKAGE SCANS  (barcode / QR at pickup + dropoff)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.package_scans (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_request_id uuid        NOT NULL REFERENCES public.package_delivery_requests(id),
  driver_id           uuid        NOT NULL REFERENCES public.drivers(id),
  scan_type           text        NOT NULL CHECK (scan_type IN ('pickup_scan','dropoff_scan')),
  barcode_data        text,
  is_valid            boolean     NOT NULL DEFAULT false,
  scan_image_url      text,
  created_at          timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 5. LIVE DRIVER LOCATION (package deliveries)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.package_delivery_locations (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  delivery_request_id uuid        NOT NULL REFERENCES public.package_delivery_requests(id),
  driver_id           uuid        NOT NULL REFERENCES public.drivers(id),
  lat                 numeric(10,7) NOT NULL,
  lng                 numeric(10,7) NOT NULL,
  heading             numeric(5,2),
  speed               numeric(5,2),
  created_at          timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 6. WEBHOOK LOGS
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.shipping_company_webhooks (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  shipping_company_id uuid        NOT NULL REFERENCES public.shipping_companies(id),
  event_type          text        NOT NULL,
  payload             jsonb       NOT NULL DEFAULT '{}',
  processed           boolean     NOT NULL DEFAULT false,
  processed_at        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- Extend drivers table for package delivery
-- ---------------------------------------------------------------------------
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS is_available_for_packages boolean  NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS max_package_weight         numeric(8,2) DEFAULT 50.0,
  ADD COLUMN IF NOT EXISTS can_handle_fragile         boolean  NOT NULL DEFAULT false;

-- Widen service_type constraint to include 'package_delivery'
ALTER TABLE public.drivers
  DROP CONSTRAINT IF EXISTS drivers_service_type_check;

ALTER TABLE public.drivers
  ADD CONSTRAINT drivers_service_type_check CHECK (
    service_type IN (
      'food_delivery','ride_sharing','package_delivery',
      'food_and_rides','food_and_packages','rides_and_packages',
      'all','both'
    )
  );

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_pkg_records_tracking   ON public.package_records(tracking_number);
CREATE INDEX IF NOT EXISTS idx_pkg_records_company    ON public.package_records(shipping_company_id);
CREATE INDEX IF NOT EXISTS idx_pkg_records_customer   ON public.package_records(customer_id);
CREATE INDEX IF NOT EXISTS idx_pkg_del_req_customer   ON public.package_delivery_requests(customer_id);
CREATE INDEX IF NOT EXISTS idx_pkg_del_req_driver     ON public.package_delivery_requests(driver_id);
CREATE INDEX IF NOT EXISTS idx_pkg_del_req_status     ON public.package_delivery_requests(delivery_status);
CREATE INDEX IF NOT EXISTS idx_pkg_del_locations      ON public.package_delivery_locations(delivery_request_id);
CREATE INDEX IF NOT EXISTS idx_pkg_scans_delivery     ON public.package_scans(delivery_request_id);

-- ---------------------------------------------------------------------------
-- Realtime publication
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.package_delivery_requests;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.package_delivery_locations;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ---------------------------------------------------------------------------
-- SEED: Shipping companies (Jamaica)
-- ---------------------------------------------------------------------------
INSERT INTO public.shipping_companies
  (name, logo_url, warehouse_address, warehouse_lat, warehouse_lng,
   support_email, support_phone, verification_type, active)
VALUES
  ('Applizone Shipping', NULL,
   '15 Red Hills Road, Kingston, Jamaica', 18.0145, -76.8023,
   'support@applizone.com', '+18765550101', 'manual', true),
  ('Island Freight', NULL,
   '23 Spanish Town Road, Kingston, Jamaica', 18.0067, -76.8412,
   'info@islandfreight.com', '+18765550102', 'manual', true),
  ('QuickShip Express', NULL,
   '8 Constant Spring Road, Kingston, Jamaica', 18.0289, -76.7971,
   'hello@quickship.com', '+18765550103', 'manual', true),
  ('Cayman Express', NULL,
   '45 Mountain View Avenue, Kingston, Jamaica', 18.0001, -76.7756,
   'care@caymanexpress.com', '+18765550104', 'manual', true),
  ('Global Cargo', NULL,
   '12 Marcus Garvey Drive, Kingston, Jamaica', 17.9972, -76.7889,
   'global@cargo.com', '+18765550105', 'manual', true)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- SEED: Sample package records (for testing)
-- ---------------------------------------------------------------------------
INSERT INTO public.package_records
  (shipping_company_id, tracking_number, customer_name, customer_phone,
   warehouse_location, delivery_address, delivery_lat, delivery_lng,
   package_weight, package_type, package_value, barcode_data,
   package_status, verified, notes)
SELECT
  sc.id,
  'PKG-948383',
  'John Doe',
  '+18765551234',
  sc.warehouse_address,
  '123 Main Street, Kingston, Jamaica',
  18.0100, -76.7900,
  4.2, 'medium', 150.00,
  'PKG-948383',
  'at_warehouse', true,
  'Electronics package from overseas'
FROM public.shipping_companies sc
WHERE sc.name = 'Applizone Shipping'
ON CONFLICT DO NOTHING;

INSERT INTO public.package_records
  (shipping_company_id, tracking_number, customer_name, customer_phone,
   warehouse_location, delivery_address, delivery_lat, delivery_lng,
   package_weight, package_type, package_value, barcode_data,
   package_status, verified, notes)
SELECT
  sc.id,
  'PKG-123456',
  'Jane Smith',
  '+18765559876',
  sc.warehouse_address,
  '45 Dunrobin Avenue, Kingston, Jamaica',
  18.0050, -76.7850,
  1.5, 'document', 50.00,
  'PKG-123456',
  'at_warehouse', true,
  'Document package'
FROM public.shipping_companies sc
WHERE sc.name = 'Island Freight'
ON CONFLICT DO NOTHING;

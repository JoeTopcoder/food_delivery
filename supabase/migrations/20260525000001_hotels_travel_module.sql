-- Hotels & Travel Module
-- All tables prefixed with hotel_ or travel_ to avoid conflicts with existing schema.

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. travel_provider_settings
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.travel_provider_settings (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  provider          text        NOT NULL DEFAULT 'hotelbeds',
  is_active         boolean     NOT NULL DEFAULT false,
  mode              text        NOT NULL DEFAULT 'test' CHECK (mode IN ('test', 'live')),
  commission_type   text        NOT NULL DEFAULT 'percentage' CHECK (commission_type IN ('fixed', 'percentage')),
  commission_value  numeric     NOT NULL DEFAULT 10.0,
  source_market     text        NOT NULL DEFAULT 'US',
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);

-- Seed default settings (inactive/test by default for safety)
INSERT INTO public.travel_provider_settings
  (provider, is_active, mode, commission_type, commission_value, source_market)
VALUES
  ('hotelbeds', false, 'test', 'percentage', 10.0, 'US')
ON CONFLICT DO NOTHING;

ALTER TABLE public.travel_provider_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_manage_travel_settings"
  ON public.travel_provider_settings FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));
CREATE POLICY "all_read_travel_settings"
  ON public.travel_provider_settings FOR SELECT USING (true);

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. hotel_content_cache
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotel_content_cache (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  provider          text        NOT NULL DEFAULT 'hotelbeds',
  hotel_code        text        NOT NULL,
  hotel_name        text,
  category          text,
  category_code     text,
  address           text,
  city              text,
  country_code      text,
  destination_code  text,
  destination_name  text,
  latitude          numeric,
  longitude         numeric,
  phone             text,
  email             text,
  description       text,
  images            jsonb       DEFAULT '[]',
  facilities        jsonb       DEFAULT '[]',
  room_types        jsonb       DEFAULT '[]',
  board_types       jsonb       DEFAULT '[]',
  points_of_interest jsonb      DEFAULT '[]',
  raw_content       jsonb,
  last_synced_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (provider, hotel_code)
);

CREATE INDEX idx_hotel_content_code ON public.hotel_content_cache (hotel_code);
CREATE INDEX idx_hotel_content_destination ON public.hotel_content_cache (destination_code);

ALTER TABLE public.hotel_content_cache ENABLE ROW LEVEL SECURITY;
CREATE POLICY "all_read_hotel_content"
  ON public.hotel_content_cache FOR SELECT USING (true);
CREATE POLICY "service_manage_hotel_content"
  ON public.hotel_content_cache FOR ALL
  USING (auth.role() = 'service_role');

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. hotel_search_logs
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotel_search_logs (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  provider        text        NOT NULL DEFAULT 'hotelbeds',
  destination     text,
  destination_code text,
  check_in        date,
  check_out       date,
  rooms           int         NOT NULL DEFAULT 1,
  adults          int         NOT NULL DEFAULT 2,
  children        int         NOT NULL DEFAULT 0,
  children_ages   jsonb       DEFAULT '[]',
  source_market   text,
  filters         jsonb       DEFAULT '{}',
  results_count   int,
  raw_request     jsonb,
  raw_response    jsonb,
  created_at      timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_hotel_search_user ON public.hotel_search_logs (user_id);
CREATE INDEX idx_hotel_search_destination ON public.hotel_search_logs (destination_code);
CREATE INDEX idx_hotel_search_created ON public.hotel_search_logs (created_at DESC);

ALTER TABLE public.hotel_search_logs ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_read_own_searches"
  ON public.hotel_search_logs FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY "admin_read_all_searches"
  ON public.hotel_search_logs FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));
CREATE POLICY "service_insert_searches"
  ON public.hotel_search_logs FOR INSERT
  WITH CHECK (auth.role() = 'service_role');

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. hotel_booking_attempts
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotel_booking_attempts (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  provider            text        NOT NULL DEFAULT 'hotelbeds',
  hotel_code          text,
  rate_key            text,
  rate_type           text,
  check_rate_required boolean     NOT NULL DEFAULT false,
  amount              numeric,
  currency            text        DEFAULT 'USD',
  status              text        NOT NULL DEFAULT 'pending'
                        CHECK (status IN ('pending','confirmed','failed','cancelled')),
  error_message       text,
  idempotency_key     text        UNIQUE,
  raw_request         jsonb,
  raw_response        jsonb,
  created_at          timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_hotel_attempt_user ON public.hotel_booking_attempts (user_id);
CREATE INDEX idx_hotel_attempt_status ON public.hotel_booking_attempts (status);

ALTER TABLE public.hotel_booking_attempts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_read_own_attempts"
  ON public.hotel_booking_attempts FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY "admin_read_all_attempts"
  ON public.hotel_booking_attempts FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));
CREATE POLICY "service_manage_attempts"
  ON public.hotel_booking_attempts FOR ALL
  USING (auth.role() = 'service_role');

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. hotel_bookings
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotel_bookings (
  id                        uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                   uuid        REFERENCES public.users(id) ON DELETE SET NULL,
  provider                  text        NOT NULL DEFAULT 'hotelbeds',
  hotelbeds_reference       text,
  agency_reference          text,
  hotel_code                text,
  hotel_name                text,
  hotel_category            text,
  hotel_address             text,
  hotel_city                text,
  hotel_country             text,
  hotel_phone               text,
  destination_name          text,
  room_type                 text,
  board_type                text,
  board_code                text,
  check_in                  date,
  check_out                 date,
  nights                    int,
  rooms                     int         NOT NULL DEFAULT 1,
  adults                    int         NOT NULL DEFAULT 2,
  children                  int         NOT NULL DEFAULT 0,
  children_ages             jsonb       DEFAULT '[]',
  holder_first_name         text,
  holder_last_name          text,
  holder_email              text,
  holder_phone              text,
  passenger_details         jsonb       DEFAULT '[]',
  base_amount               numeric,
  service_fee               numeric     DEFAULT 0,
  total_amount              numeric,
  currency                  text        DEFAULT 'USD',
  rate_key                  text,
  rate_type                 text,
  rate_class                text,
  cancellation_policies     jsonb       DEFAULT '[]',
  rate_comments             text,
  promotions                jsonb       DEFAULT '[]',
  supplier_name             text,
  supplier_vat              text,
  payment_status            text        NOT NULL DEFAULT 'pending'
                              CHECK (payment_status IN ('pending','authorized','paid','refunded','voided')),
  booking_status            text        NOT NULL DEFAULT 'pending'
                              CHECK (booking_status IN ('pending','confirmed','cancelled','failed')),
  cancellation_status       text        DEFAULT 'none'
                              CHECK (cancellation_status IN ('none','requested','cancelled')),
  cancellation_amount       numeric,
  cancellation_reference    text,
  stripe_payment_intent_id  text,
  voucher_url               text,
  raw_provider_response     jsonb,
  created_at                timestamptz NOT NULL DEFAULT now(),
  updated_at                timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_hotel_bookings_user ON public.hotel_bookings (user_id);
CREATE INDEX idx_hotel_bookings_ref ON public.hotel_bookings (hotelbeds_reference);
CREATE INDEX idx_hotel_bookings_status ON public.hotel_bookings (booking_status);
CREATE INDEX idx_hotel_bookings_checkin ON public.hotel_bookings (check_in);

ALTER TABLE public.hotel_bookings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "users_read_own_bookings"
  ON public.hotel_bookings FOR SELECT
  USING (user_id = auth.uid());
CREATE POLICY "admin_manage_all_bookings"
  ON public.hotel_bookings FOR ALL
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));
CREATE POLICY "service_manage_bookings"
  ON public.hotel_bookings FOR ALL
  USING (auth.role() = 'service_role');

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.update_hotel_booking_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER trg_hotel_booking_updated_at
  BEFORE UPDATE ON public.hotel_bookings
  FOR EACH ROW EXECUTE FUNCTION public.update_hotel_booking_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. hotel_booking_events
-- ─────────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.hotel_booking_events (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  booking_id     uuid        REFERENCES public.hotel_bookings(id) ON DELETE CASCADE,
  event_type     text        NOT NULL,
  event_payload  jsonb       DEFAULT '{}',
  created_at     timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_hotel_events_booking ON public.hotel_booking_events (booking_id);
CREATE INDEX idx_hotel_events_type ON public.hotel_booking_events (event_type);

ALTER TABLE public.hotel_booking_events ENABLE ROW LEVEL SECURITY;
CREATE POLICY "service_manage_hotel_events"
  ON public.hotel_booking_events FOR ALL
  USING (auth.role() = 'service_role');
CREATE POLICY "admin_read_hotel_events"
  ON public.hotel_booking_events FOR SELECT
  USING (EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. Feature flag seed
-- ─────────────────────────────────────────────────────────────────────────────
INSERT INTO public.feature_flags (name, enabled, description)
VALUES ('hotels_enabled', false, 'Hotels & Travel module (Hotelbeds)')
ON CONFLICT (name) DO NOTHING;

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. Recent hotel searches for home screen (RPC)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_recent_hotel_searches(p_user_id uuid, p_limit int DEFAULT 5)
RETURNS TABLE (
  destination       text,
  destination_code  text,
  check_in          date,
  check_out         date,
  rooms             int,
  adults            int,
  children          int,
  searched_at       timestamptz
)
LANGUAGE sql SECURITY DEFINER AS $$
  SELECT DISTINCT ON (destination_code)
    destination, destination_code, check_in, check_out, rooms, adults, children, created_at
  FROM public.hotel_search_logs
  WHERE user_id = p_user_id
    AND destination_code IS NOT NULL
  ORDER BY destination_code, created_at DESC
  LIMIT p_limit;
$$;

GRANT EXECUTE ON FUNCTION public.get_recent_hotel_searches(uuid, int) TO authenticated;

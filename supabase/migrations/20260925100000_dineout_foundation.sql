-- ============================================================================
-- HotBite DineOut — foundation schema
-- ============================================================================
-- Restaurant dining reservations, fully separate from the delivery flow. Reuses
-- restaurants(owner_id), users, menus and the notifications system. Delivery
-- (menus.price/is_available, orders, payouts, riders) is untouched.
--
-- OVERBOOKING GUARANTEE: dineout_reservation_tables carries a GiST EXCLUDE
-- constraint on (table_id, during) so Postgres itself rejects two overlapping
-- ACTIVE holds/reservations on the same table — the atomic, race-proof core.
-- ============================================================================
CREATE EXTENSION IF NOT EXISTS btree_gist;

-- ── per-restaurant DineOut settings (1:1) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dineout_settings (
  restaurant_id           uuid PRIMARY KEY REFERENCES public.restaurants(id) ON DELETE CASCADE,
  enabled                 boolean NOT NULL DEFAULT false,        -- independent of delivery
  booking_interval_min    int NOT NULL DEFAULT 30 CHECK (booking_interval_min BETWEEN 5 AND 240),
  min_party               int NOT NULL DEFAULT 1 CHECK (min_party >= 1),
  max_party               int NOT NULL DEFAULT 12 CHECK (max_party >= min_party),
  advance_booking_days    int NOT NULL DEFAULT 30 CHECK (advance_booking_days BETWEEN 0 AND 365),
  grace_period_min        int NOT NULL DEFAULT 15 CHECK (grace_period_min >= 0),
  cleanup_buffer_min      int NOT NULL DEFAULT 15 CHECK (cleanup_buffer_min >= 0),
  default_duration_min    int NOT NULL DEFAULT 90 CHECK (default_duration_min > 0),
  max_online_per_slot     int,                                   -- NULL = only table capacity limits
  deposit_required        boolean NOT NULL DEFAULT false,
  deposit_amount          numeric NOT NULL DEFAULT 0 CHECK (deposit_amount >= 0),
  deposit_per_person      boolean NOT NULL DEFAULT false,
  cancellation_policy     text,
  cancellation_cutoff_hrs int NOT NULL DEFAULT 4 CHECK (cancellation_cutoff_hrs >= 0),
  hold_ttl_min            int NOT NULL DEFAULT 10 CHECK (hold_ttl_min BETWEEN 2 AND 60),
  timezone                text NOT NULL DEFAULT 'America/Jamaica',
  policies                text,
  photos                  jsonb NOT NULL DEFAULT '[]'::jsonb,
  created_at              timestamptz NOT NULL DEFAULT now(),
  updated_at              timestamptz NOT NULL DEFAULT now()
);

-- ── dining tables ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dineout_tables (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id   uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  label           text NOT NULL,
  seat_capacity   int NOT NULL CHECK (seat_capacity > 0),
  online_bookable boolean NOT NULL DEFAULT true,
  combinable      boolean NOT NULL DEFAULT false,
  held_for_walkin boolean NOT NULL DEFAULT false,
  is_active       boolean NOT NULL DEFAULT true,
  sort_order      int NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (restaurant_id, label)
);
CREATE INDEX IF NOT EXISTS idx_dineout_tables_restaurant ON public.dineout_tables(restaurant_id);

-- ── permitted table combinations (joined for larger parties) ───────────────
CREATE TABLE IF NOT EXISTS public.dineout_table_combinations (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name          text,
  table_ids     uuid[] NOT NULL CHECK (array_length(table_ids,1) >= 2),
  total_capacity int NOT NULL CHECK (total_capacity > 0),
  online_bookable boolean NOT NULL DEFAULT true,
  is_active     boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dineout_combos_restaurant ON public.dineout_table_combinations(restaurant_id);

-- ── weekly dine-in hours (multiple windows per day allowed) ────────────────
CREATE TABLE IF NOT EXISTS public.dineout_schedules (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  day_of_week   int NOT NULL CHECK (day_of_week BETWEEN 0 AND 6),  -- 0=Sunday
  open_time     time NOT NULL,
  close_time    time NOT NULL,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (close_time > open_time)
);
CREATE INDEX IF NOT EXISTS idx_dineout_schedules_restaurant ON public.dineout_schedules(restaurant_id, day_of_week);

-- ── exceptions: block a date/time range, optionally for one table ──────────
CREATE TABLE IF NOT EXISTS public.dineout_exceptions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  table_id      uuid REFERENCES public.dineout_tables(id) ON DELETE CASCADE, -- NULL = whole restaurant
  blocked_from  timestamptz NOT NULL,
  blocked_to    timestamptz NOT NULL,
  reason        text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  CHECK (blocked_to > blocked_from)
);
CREATE INDEX IF NOT EXISTS idx_dineout_exceptions_restaurant ON public.dineout_exceptions(restaurant_id, blocked_from, blocked_to);

-- ── expected dining duration by party size ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dineout_duration_rules (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  min_party     int NOT NULL CHECK (min_party >= 1),
  max_party     int NOT NULL CHECK (max_party >= min_party),
  duration_min  int NOT NULL CHECK (duration_min > 0),
  UNIQUE (restaurant_id, min_party, max_party)
);

-- ── dining packages ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dineout_packages (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  name          text NOT NULL,
  description   text,
  price         numeric NOT NULL CHECK (price >= 0),
  per_person    boolean NOT NULL DEFAULT true,
  is_available  boolean NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dineout_packages_restaurant ON public.dineout_packages(restaurant_id);

-- Dine-in menu = existing menus item, exposed to the dine-in channel with its
-- OWN price + availability (delivery columns price/is_available are untouched).
ALTER TABLE public.menus ADD COLUMN IF NOT EXISTS dinein_enabled  boolean NOT NULL DEFAULT false;
ALTER TABLE public.menus ADD COLUMN IF NOT EXISTS dinein_price    numeric;
ALTER TABLE public.menus ADD COLUMN IF NOT EXISTS dinein_available boolean NOT NULL DEFAULT true;

-- ── reservations ───────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dineout_reservations (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id       uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  user_id             uuid REFERENCES public.users(id) ON DELETE SET NULL, -- NULL = walk-in
  reservation_ref     text NOT NULL UNIQUE,
  party_size          int NOT NULL CHECK (party_size >= 1),
  reserved_from       timestamptz NOT NULL,
  reserved_to         timestamptz NOT NULL,   -- dining end (start + duration)
  buffer_to           timestamptz NOT NULL,   -- reserved_to + cleanup buffer
  status              text NOT NULL DEFAULT 'hold'
                        CHECK (status IN ('hold','pending_payment','confirmed','seated','completed',
                                          'cancelled','no_show','expired')),
  source              text NOT NULL DEFAULT 'online' CHECK (source IN ('online','walkin','staff')),
  package_id          uuid REFERENCES public.dineout_packages(id) ON DELETE SET NULL,
  preorder            jsonb NOT NULL DEFAULT '[]'::jsonb,
  guest_name          text,
  guest_phone         text,
  notes               text,
  subtotal            numeric NOT NULL DEFAULT 0,
  tax_amount          numeric NOT NULL DEFAULT 0,
  service_charge      numeric NOT NULL DEFAULT 0,
  deposit_amount      numeric NOT NULL DEFAULT 0,
  deposit_status      text NOT NULL DEFAULT 'none' CHECK (deposit_status IN ('none','pending','paid','refunded','forfeited')),
  total               numeric NOT NULL DEFAULT 0,
  payable_at_restaurant numeric NOT NULL DEFAULT 0,
  payment_intent_id   text,
  idempotency_key     text UNIQUE,
  hold_expires_at     timestamptz,
  seated_at           timestamptz,
  departed_at         timestamptz,
  cleaned_at          timestamptz,
  cancelled_at        timestamptz,
  cancellation_reason text,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CHECK (reserved_to > reserved_from AND buffer_to >= reserved_to)
);
CREATE INDEX IF NOT EXISTS idx_dineout_res_restaurant_time ON public.dineout_reservations(restaurant_id, reserved_from);
CREATE INDEX IF NOT EXISTS idx_dineout_res_user ON public.dineout_reservations(user_id);
CREATE INDEX IF NOT EXISTS idx_dineout_res_status ON public.dineout_reservations(status);
CREATE INDEX IF NOT EXISTS idx_dineout_res_hold_expiry ON public.dineout_reservations(hold_expires_at) WHERE status IN ('hold','pending_payment');

-- ── assigned tables + THE overbooking guard ────────────────────────────────
-- One row per (reservation, table). `during` = [reserved_from, buffer_to). While
-- `active`, the GiST EXCLUDE makes overlapping ranges on the same table
-- impossible — the atomic, concurrency-safe core. `active` is cleared only when
-- the reservation is released (cancelled/expired/completed-after-cleaning), NEVER
-- automatically at the estimated end time.
CREATE TABLE IF NOT EXISTS public.dineout_reservation_tables (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.dineout_reservations(id) ON DELETE CASCADE,
  table_id       uuid NOT NULL REFERENCES public.dineout_tables(id) ON DELETE CASCADE,
  restaurant_id  uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  during         tstzrange NOT NULL,
  active         boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT dineout_no_double_booking
    EXCLUDE USING gist (table_id WITH =, during WITH &&) WHERE (active)
);
CREATE INDEX IF NOT EXISTS idx_dineout_res_tables_res ON public.dineout_reservation_tables(reservation_id);
CREATE INDEX IF NOT EXISTS idx_dineout_res_tables_table ON public.dineout_reservation_tables(table_id) WHERE active;

-- ── status history (audit) ─────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dineout_status_history (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id uuid NOT NULL REFERENCES public.dineout_reservations(id) ON DELETE CASCADE,
  from_status    text,
  to_status      text NOT NULL,
  changed_by     uuid REFERENCES public.users(id) ON DELETE SET NULL,
  note           text,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dineout_status_hist_res ON public.dineout_status_history(reservation_id);

-- ── payment records (deposit lifecycle) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.dineout_payments (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  reservation_id    uuid NOT NULL REFERENCES public.dineout_reservations(id) ON DELETE CASCADE,
  amount            numeric NOT NULL,
  kind              text NOT NULL DEFAULT 'deposit' CHECK (kind IN ('deposit','refund','forfeit')),
  status            text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','succeeded','failed','refunded')),
  payment_intent_id text,
  idempotency_key   text UNIQUE,
  created_at        timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_dineout_payments_res ON public.dineout_payments(reservation_id);

NOTIFY pgrst, 'reload schema';

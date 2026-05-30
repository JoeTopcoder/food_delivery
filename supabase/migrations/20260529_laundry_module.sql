-- =============================================================================
-- 7DASH LAUNDROMAT MODULE — Supabase Migration
-- Run this in the Supabase SQL editor (Dashboard → SQL Editor → New query)
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ─────────────────────────────────────────────────────────────────────────────
-- ENUMS
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
  create type laundry_booking_status as enum (
    'new_request',
    'accepted',
    'waiting_for_pickup',
    'picked_up_from_customer',
    'received_at_laundry',
    'weighed',
    'price_confirmed',
    'washing_cleaning',
    'quality_check',
    'ready_for_delivery',
    'picked_up_for_return',
    'out_for_delivery',
    'completed',
    'cancelled',
    'disputed'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type laundry_driver_leg as enum ('pickup', 'return');
exception when duplicate_object then null; end $$;

do $$ begin
  create type laundry_driver_status as enum (
    'assigned_pickup',
    'arrived_customer',
    'laundry_collected',
    'arrived_provider',
    'pickup_leg_completed',
    'assigned_return',
    'arrived_provider_return',
    'laundry_received',
    'out_for_delivery',
    'delivered',
    'completed'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type laundry_provider_status as enum ('pending', 'active', 'suspended', 'rejected');
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_providers
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_providers (
  id                    uuid primary key default uuid_generate_v4(),
  user_id               uuid not null references public.users(id) on delete cascade,
  business_name         text not null,
  description           text,
  logo_url              text,
  banner_url            text,
  phone                 text,
  email                 text,
  address               text,
  latitude              double precision,
  longitude             double precision,
  pickup_radius_km      double precision default 10,
  status                laundry_provider_status not null default 'pending',
  is_active             boolean not null default false,
  is_verified           boolean not null default false,
  rating                double precision default 0,
  review_count          int default 0,
  operating_hours       jsonb,           -- {"mon":{"open":"08:00","close":"18:00"}, ...}
  bank_name             text,
  bank_account_number   text,
  bank_account_holder   text,
  stripe_account_id     text,
  commission_rate       double precision default 0.15,
  onboarding_step       int default 0,
  rejection_reason      text,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz
);

create index if not exists idx_laundry_providers_user_id   on laundry_providers(user_id);
create index if not exists idx_laundry_providers_status    on laundry_providers(status);
create index if not exists idx_laundry_providers_location  on laundry_providers(latitude, longitude);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_services  (master service catalogue)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_services (
  id          uuid primary key default uuid_generate_v4(),
  name        text not null unique,
  description text,
  icon        text,             -- icon identifier / emoji
  sort_order  int default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

insert into laundry_services (name, description, icon, sort_order) values
  ('Wash & Fold',        'Full wash, dry and fold service',          'local_laundry_service', 1),
  ('Wash Only',          'Machine wash without drying/folding',      'water_drop',            2),
  ('Dry Only',           'Tumble dry or line dry only',              'air',                   3),
  ('Ironing',            'Professional pressing and ironing',        'iron',                  4),
  ('Dry Cleaning',       'Professional dry-clean treatment',         'dry_cleaning',          5),
  ('Express Laundry',    'Same-day turnaround service',              'bolt',                  6),
  ('Bedding Cleaning',   'Sheets, duvet covers, pillowcases',        'bed',                   7),
  ('Uniform Cleaning',   'Work uniforms and professional attire',    'work',                  8),
  ('Delicates Cleaning', 'Gentle cycle for delicate fabrics',        'diamond',               9)
on conflict (name) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_provider_services  (per-provider pricing for each service)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_provider_services (
  id                  uuid primary key default uuid_generate_v4(),
  provider_id         uuid not null references laundry_providers(id) on delete cascade,
  service_id          uuid not null references laundry_services(id),
  is_available        boolean not null default true,
  price_per_pound     double precision,
  price_per_kg        double precision,
  minimum_order_fee   double precision default 0,
  express_fee         double precision default 0,
  ironing_fee         double precision default 0,
  dry_cleaning_fee    double precision default 0,
  estimated_hours     int default 24,
  notes               text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  unique (provider_id, service_id)
);

create index if not exists idx_laundry_provider_services_provider on laundry_provider_services(provider_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_pricing  (provider-level fee structure)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_pricing (
  id              uuid primary key default uuid_generate_v4(),
  provider_id     uuid not null unique references laundry_providers(id) on delete cascade,
  pickup_fee      double precision default 0,
  delivery_fee    double precision default 0,
  min_order_fee   double precision default 5,
  currency        text default 'USD',
  updated_at      timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_bookings
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_bookings (
  id                    uuid primary key default uuid_generate_v4(),
  booking_number        text unique not null default ('LB-' || upper(substr(md5(random()::text), 1, 8))),
  customer_id           uuid not null references public.users(id),
  provider_id           uuid not null references laundry_providers(id),

  status                laundry_booking_status not null default 'new_request',

  -- Addresses
  pickup_address        text not null,
  pickup_latitude       double precision,
  pickup_longitude      double precision,
  return_address        text not null,
  return_latitude       double precision,
  return_longitude      double precision,

  -- Schedule
  pickup_date           date not null,
  pickup_time_slot      text not null,        -- e.g. "09:00-11:00"
  return_date           date,
  return_time_slot      text,

  -- Estimates (customer-provided)
  estimated_weight_kg   double precision,
  estimated_bags        int default 1,
  customer_notes        text,
  special_instructions  text,

  -- Actuals (provider-recorded)
  actual_weight_kg      double precision,
  actual_bags           int,
  provider_notes        text,

  -- Pricing
  estimated_total       double precision,
  actual_total          double precision,
  pickup_fee            double precision default 0,
  delivery_fee          double precision default 0,
  platform_fee          double precision default 0,
  discount_amount       double precision default 0,
  currency              text default 'USD',

  -- Payment
  payment_method        text default 'card',
  stripe_payment_intent_id text,
  stripe_charge_id      text,
  payment_status        text default 'pending',
  price_approved_by_customer boolean default false,

  -- Ratings
  customer_rating_provider  int check (customer_rating_provider between 1 and 5),
  customer_rating_driver    int check (customer_rating_driver between 1 and 5),
  customer_review           text,
  provider_rating_customer  int check (provider_rating_customer between 1 and 5),

  -- Metadata
  cancellation_reason   text,
  cancelled_by          text,
  cancelled_at          timestamptz,
  completed_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz
);

create index if not exists idx_laundry_bookings_customer  on laundry_bookings(customer_id);
create index if not exists idx_laundry_bookings_provider  on laundry_bookings(provider_id);
create index if not exists idx_laundry_bookings_status    on laundry_bookings(status);
create index if not exists idx_laundry_bookings_pickup    on laundry_bookings(pickup_date);
create index if not exists idx_laundry_bookings_created   on laundry_bookings(created_at desc);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_booking_items  (per-service line items)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_booking_items (
  id            uuid primary key default uuid_generate_v4(),
  booking_id    uuid not null references laundry_bookings(id) on delete cascade,
  service_id    uuid not null references laundry_services(id),
  service_name  text not null,
  quantity      int default 1,
  unit_price    double precision default 0,
  total_price   double precision default 0,
  notes         text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_laundry_booking_items_booking on laundry_booking_items(booking_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_status_history
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_status_history (
  id            uuid primary key default uuid_generate_v4(),
  booking_id    uuid not null references laundry_bookings(id) on delete cascade,
  status        laundry_booking_status not null,
  actor_id      uuid references public.users(id),
  actor_role    text,                            -- 'customer' | 'provider' | 'driver' | 'system'
  note          text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_laundry_status_history_booking on laundry_status_history(booking_id, created_at);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_photos
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_photos (
  id            uuid primary key default uuid_generate_v4(),
  booking_id    uuid not null references laundry_bookings(id) on delete cascade,
  uploader_id   uuid references public.users(id),
  photo_type    text not null,    -- 'before' | 'after' | 'pickup_proof' | 'dropoff_proof' | 'customer_upload'
  url           text not null,
  caption       text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_laundry_photos_booking on laundry_photos(booking_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_weights  (audit trail for weigh-in)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_weights (
  id              uuid primary key default uuid_generate_v4(),
  booking_id      uuid not null references laundry_bookings(id) on delete cascade,
  weight_kg       double precision not null,
  recorded_by     uuid references public.users(id),
  photo_url       text,
  notes           text,
  created_at      timestamptz not null default now()
);

create index if not exists idx_laundry_weights_booking on laundry_weights(booking_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_driver_assignments
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_driver_assignments (
  id              uuid primary key default uuid_generate_v4(),
  booking_id      uuid not null references laundry_bookings(id),
  driver_id       uuid not null references public.users(id),
  leg             laundry_driver_leg not null,
  status          laundry_driver_status not null default 'assigned_pickup',
  assigned_at     timestamptz not null default now(),
  accepted_at     timestamptz,
  completed_at    timestamptz,
  pickup_proof_url   text,
  dropoff_proof_url  text,
  driver_notes    text,
  unique (booking_id, leg)   -- only one active assignment per leg
);

create index if not exists idx_laundry_driver_assignments_driver  on laundry_driver_assignments(driver_id);
create index if not exists idx_laundry_driver_assignments_booking on laundry_driver_assignments(booking_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_reviews
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_reviews (
  id            uuid primary key default uuid_generate_v4(),
  booking_id    uuid not null unique references laundry_bookings(id),
  customer_id   uuid not null references public.users(id),
  provider_id   uuid not null references laundry_providers(id),
  driver_id     uuid references public.users(id),
  provider_rating   int check (provider_rating between 1 and 5),
  driver_rating     int check (driver_rating between 1 and 5),
  review_text       text,
  provider_response text,
  created_at    timestamptz not null default now()
);

create index if not exists idx_laundry_reviews_provider on laundry_reviews(provider_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_disputes
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_disputes (
  id              uuid primary key default uuid_generate_v4(),
  booking_id      uuid not null references laundry_bookings(id),
  opened_by       uuid not null references public.users(id),
  reason          text not null,
  description     text,
  status          text not null default 'open',   -- 'open' | 'resolved' | 'closed'
  resolution      text,
  resolved_by     uuid references public.users(id),
  resolved_at     timestamptz,
  created_at      timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_provider_documents
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_provider_documents (
  id                  uuid primary key default uuid_generate_v4(),
  provider_id         uuid not null references laundry_providers(id) on delete cascade,
  document_type       text not null,     -- 'business_registration' | 'health_permit' | 'id'
  document_number     text,
  photo_url           text,
  expiry_date         date,
  verification_status text default 'pending',  -- 'pending' | 'approved' | 'rejected'
  rejection_reason    text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  unique (provider_id, document_type)
);

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLE: laundry_provider_payouts
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_provider_payouts (
  id                  uuid primary key default uuid_generate_v4(),
  provider_id         uuid not null references laundry_providers(id),
  amount              double precision not null,
  currency            text default 'USD',
  period_start        date not null,
  period_end          date not null,
  booking_count       int default 0,
  gross_revenue       double precision default 0,
  commission          double precision default 0,
  net_payout          double precision default 0,
  stripe_transfer_id  text,
  status              text default 'pending',   -- 'pending' | 'processing' | 'paid' | 'failed'
  paid_at             timestamptz,
  created_at          timestamptz not null default now()
);

create index if not exists idx_laundry_payouts_provider on laundry_provider_payouts(provider_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- FUNCTION: update_laundry_booking_updated_at
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function update_laundry_booking_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

create trigger trg_laundry_bookings_updated_at
  before update on laundry_bookings
  for each row execute function update_laundry_booking_updated_at();

create or replace function update_laundry_provider_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end; $$;

create trigger trg_laundry_providers_updated_at
  before update on laundry_providers
  for each row execute function update_laundry_provider_updated_at();

-- ─────────────────────────────────────────────────────────────────────────────
-- FUNCTION: auto-insert status history on booking status change
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function laundry_booking_status_history_trigger()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op = 'INSERT') or (old.status is distinct from new.status) then
    insert into laundry_status_history (booking_id, status, actor_role)
    values (new.id, new.status, 'system');
  end if;
  return new;
end; $$;

create trigger trg_laundry_status_history
  after insert or update on laundry_bookings
  for each row execute function laundry_booking_status_history_trigger();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS — Enable on all tables
-- ─────────────────────────────────────────────────────────────────────────────
alter table laundry_providers               enable row level security;
alter table laundry_services                enable row level security;
alter table laundry_provider_services       enable row level security;
alter table laundry_pricing                 enable row level security;
alter table laundry_bookings                enable row level security;
alter table laundry_booking_items           enable row level security;
alter table laundry_status_history          enable row level security;
alter table laundry_photos                  enable row level security;
alter table laundry_weights                 enable row level security;
alter table laundry_driver_assignments      enable row level security;
alter table laundry_reviews                 enable row level security;
alter table laundry_disputes                enable row level security;
alter table laundry_provider_documents      enable row level security;
alter table laundry_provider_payouts        enable row level security;

-- ── laundry_services (read-only for everyone) ─────────────────────────────────
create policy "laundry_services_select_all" on laundry_services
  for select using (true);

create policy "laundry_services_admin_all" on laundry_services
  for all using (
    exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

-- ── laundry_providers ─────────────────────────────────────────────────────────
create policy "laundry_providers_select_active" on laundry_providers
  for select using (is_active = true or user_id = auth.uid() or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

create policy "laundry_providers_insert_own" on laundry_providers
  for insert with check (user_id = auth.uid());

create policy "laundry_providers_update_own" on laundry_providers
  for update using (user_id = auth.uid() or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

create policy "laundry_providers_admin_delete" on laundry_providers
  for delete using (
    exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

-- ── laundry_provider_services ─────────────────────────────────────────────────
create policy "laundry_ps_select" on laundry_provider_services
  for select using (true);

create policy "laundry_ps_write" on laundry_provider_services
  for all using (
    exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

-- ── laundry_pricing ───────────────────────────────────────────────────────────
create policy "laundry_pricing_select" on laundry_pricing
  for select using (true);

create policy "laundry_pricing_write" on laundry_pricing
  for all using (
    exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

-- ── laundry_bookings ──────────────────────────────────────────────────────────
create policy "laundry_bookings_customer_select" on laundry_bookings
  for select using (
    customer_id = auth.uid()
    or exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
    or exists (select 1 from laundry_driver_assignments where booking_id = laundry_bookings.id and driver_id = auth.uid())
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

create policy "laundry_bookings_customer_insert" on laundry_bookings
  for insert with check (customer_id = auth.uid());

create policy "laundry_bookings_update" on laundry_bookings
  for update using (
    customer_id = auth.uid()
    or exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
    or exists (select 1 from laundry_driver_assignments where booking_id = laundry_bookings.id and driver_id = auth.uid())
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

-- ── laundry_booking_items ─────────────────────────────────────────────────────
create policy "laundry_items_select" on laundry_booking_items
  for select using (
    exists (select 1 from laundry_bookings b where b.id = booking_id and (
      b.customer_id = auth.uid()
      or exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid())
      or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
    ))
  );

create policy "laundry_items_insert" on laundry_booking_items
  for insert with check (
    exists (select 1 from laundry_bookings b where b.id = booking_id and b.customer_id = auth.uid())
  );

-- ── laundry_status_history ────────────────────────────────────────────────────
create policy "laundry_status_history_select" on laundry_status_history
  for select using (
    exists (select 1 from laundry_bookings b where b.id = booking_id and (
      b.customer_id = auth.uid()
      or exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid())
      or exists (select 1 from laundry_driver_assignments where booking_id = b.id and driver_id = auth.uid())
      or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
    ))
  );

-- ── laundry_photos ────────────────────────────────────────────────────────────
create policy "laundry_photos_select" on laundry_photos
  for select using (
    uploader_id = auth.uid()
    or exists (select 1 from laundry_bookings b where b.id = booking_id and (
      b.customer_id = auth.uid()
      or exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid())
      or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
    ))
  );

create policy "laundry_photos_insert" on laundry_photos
  for insert with check (uploader_id = auth.uid());

-- ── laundry_weights ───────────────────────────────────────────────────────────
create policy "laundry_weights_select" on laundry_weights
  for select using (
    exists (select 1 from laundry_bookings b where b.id = booking_id and (
      b.customer_id = auth.uid()
      or exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid())
      or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
    ))
  );

create policy "laundry_weights_insert_provider" on laundry_weights
  for insert with check (
    exists (select 1 from laundry_bookings b
      join laundry_providers p on p.id = b.provider_id
      where b.id = booking_id and p.user_id = auth.uid())
  );

-- ── laundry_driver_assignments ────────────────────────────────────────────────
create policy "laundry_da_select" on laundry_driver_assignments
  for select using (
    driver_id = auth.uid()
    or exists (select 1 from laundry_bookings b where b.id = booking_id and (
      b.customer_id = auth.uid()
      or exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid())
    ))
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

create policy "laundry_da_update_driver" on laundry_driver_assignments
  for update using (driver_id = auth.uid() or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

create policy "laundry_da_insert_admin" on laundry_driver_assignments
  for insert with check (
    exists (select 1 from public.users where id = auth.uid() and role = 'admin')
    or exists (select 1 from laundry_bookings b
      join laundry_providers p on p.id = b.provider_id
      where b.id = booking_id and p.user_id = auth.uid())
  );

-- ── laundry_reviews ───────────────────────────────────────────────────────────
create policy "laundry_reviews_select" on laundry_reviews
  for select using (true);

create policy "laundry_reviews_insert_customer" on laundry_reviews
  for insert with check (customer_id = auth.uid());

create policy "laundry_reviews_update_provider_response" on laundry_reviews
  for update using (
    customer_id = auth.uid()
    or exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
  );

-- ── laundry_disputes ──────────────────────────────────────────────────────────
create policy "laundry_disputes_select" on laundry_disputes
  for select using (
    opened_by = auth.uid()
    or exists (select 1 from laundry_bookings b where b.id = booking_id and (
      exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid())
    ))
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

create policy "laundry_disputes_insert" on laundry_disputes
  for insert with check (opened_by = auth.uid());

create policy "laundry_disputes_update_admin" on laundry_disputes
  for update using (exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- ── laundry_provider_documents ────────────────────────────────────────────────
create policy "laundry_docs_select" on laundry_provider_documents
  for select using (
    exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

create policy "laundry_docs_write" on laundry_provider_documents
  for all using (
    exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

-- ── laundry_provider_payouts ──────────────────────────────────────────────────
create policy "laundry_payouts_select" on laundry_provider_payouts
  for select using (
    exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid())
    or exists (select 1 from public.users where id = auth.uid() and role = 'admin')
  );

create policy "laundry_payouts_admin_write" on laundry_provider_payouts
  for all using (exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- ─────────────────────────────────────────────────────────────────────────────
-- STORAGE BUCKETS  (run in Supabase Dashboard → Storage or via API)
-- ─────────────────────────────────────────────────────────────────────────────
-- INSERT INTO storage.buckets (id, name, public) VALUES
--   ('laundry-provider-logos',     'laundry-provider-logos',     true),
--   ('laundry-provider-documents', 'laundry-provider-documents',  false),
--   ('laundry-order-photos',       'laundry-order-photos',        false),
--   ('laundry-before-photos',      'laundry-before-photos',       false),
--   ('laundry-after-photos',       'laundry-after-photos',        false)
-- ON CONFLICT (id) DO NOTHING;

-- Storage policies (execute after creating buckets):
-- CREATE POLICY "Public logos" ON storage.objects FOR SELECT USING (bucket_id = 'laundry-provider-logos');
-- CREATE POLICY "Provider upload logo" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'laundry-provider-logos' AND auth.uid() IS NOT NULL);
-- CREATE POLICY "Authenticated doc upload" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'laundry-provider-documents' AND auth.uid() IS NOT NULL);
-- CREATE POLICY "Doc owner select" ON storage.objects FOR SELECT USING (bucket_id = 'laundry-provider-documents' AND (storage.foldername(name))[1] = auth.uid()::text);
-- CREATE POLICY "Photo upload auth" ON storage.objects FOR INSERT WITH CHECK (bucket_id IN ('laundry-order-photos','laundry-before-photos','laundry-after-photos') AND auth.uid() IS NOT NULL);
-- CREATE POLICY "Photo select auth" ON storage.objects FOR SELECT USING (bucket_id IN ('laundry-order-photos','laundry-before-photos','laundry-after-photos') AND auth.uid() IS NOT NULL);

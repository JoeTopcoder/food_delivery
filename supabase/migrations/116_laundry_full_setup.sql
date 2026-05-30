-- =============================================================================
-- LAUNDRY MODULE — COMPLETE SETUP  (safe to run multiple times)
-- Run in: Supabase Dashboard → SQL Editor → New Query
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- EXTENSIONS
-- ─────────────────────────────────────────────────────────────────────────────
create extension if not exists "uuid-ossp";

-- ─────────────────────────────────────────────────────────────────────────────
-- ENUMS  (skip if already exist)
-- ─────────────────────────────────────────────────────────────────────────────
do $$ begin
  create type laundry_booking_status as enum (
    'new_request','accepted','waiting_for_pickup','picked_up_from_customer',
    'received_at_laundry','weighed','price_confirmed','washing_cleaning',
    'quality_check','ready_for_delivery','picked_up_for_return',
    'out_for_delivery','completed','cancelled','disputed'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type laundry_driver_leg as enum ('pickup','return');
exception when duplicate_object then null; end $$;

do $$ begin
  create type laundry_driver_status as enum (
    'assigned_pickup','arrived_customer','laundry_collected','arrived_provider',
    'pickup_leg_completed','assigned_return','arrived_provider_return',
    'laundry_received','out_for_delivery','delivered','completed'
  );
exception when duplicate_object then null; end $$;

do $$ begin
  create type laundry_provider_status as enum ('pending','active','suspended','rejected');
exception when duplicate_object then null; end $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- TABLES
-- ─────────────────────────────────────────────────────────────────────────────

create table if not exists laundry_providers (
  id                  uuid primary key default uuid_generate_v4(),
  user_id             uuid not null references public.users(id) on delete cascade,
  business_name       text not null,
  description         text,
  logo_url            text,
  banner_url          text,
  phone               text,
  email               text,
  address             text,
  latitude            double precision,
  longitude           double precision,
  pickup_radius_km    double precision default 10,
  status              laundry_provider_status not null default 'pending',
  is_active           boolean not null default false,
  is_verified         boolean not null default false,
  rating              double precision default 0,
  review_count        int default 0,
  operating_hours     jsonb,
  bank_name           text,
  bank_account_number text,
  bank_account_holder text,
  stripe_account_id   text,
  commission_rate     double precision default 0.15,
  onboarding_step     int default 0,
  rejection_reason    text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz
);
create index if not exists idx_laundry_providers_user_id  on laundry_providers(user_id);
create index if not exists idx_laundry_providers_status   on laundry_providers(status);
create index if not exists idx_laundry_providers_location on laundry_providers(latitude, longitude);

create table if not exists laundry_services (
  id         uuid primary key default uuid_generate_v4(),
  name       text not null unique,
  description text,
  icon       text,
  sort_order int default 0,
  is_active  boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists laundry_provider_services (
  id                uuid primary key default uuid_generate_v4(),
  provider_id       uuid not null references laundry_providers(id) on delete cascade,
  service_id        uuid not null references laundry_services(id),
  is_available      boolean not null default true,
  price_per_pound   double precision,
  price_per_kg      double precision,
  minimum_order_fee double precision default 0,
  express_fee       double precision default 0,
  ironing_fee       double precision default 0,
  dry_cleaning_fee  double precision default 0,
  estimated_hours   int default 24,
  notes             text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz,
  unique (provider_id, service_id)
);
create index if not exists idx_laundry_ps_provider on laundry_provider_services(provider_id);

create table if not exists laundry_pricing (
  id            uuid primary key default uuid_generate_v4(),
  provider_id   uuid not null unique references laundry_providers(id) on delete cascade,
  pickup_fee    double precision default 0,
  delivery_fee  double precision default 0,
  min_order_fee double precision default 5,
  currency      text default 'USD',
  updated_at    timestamptz not null default now()
);

create table if not exists laundry_bookings (
  id                    uuid primary key default uuid_generate_v4(),
  booking_number        text unique not null default ('LB-' || upper(substr(md5(random()::text), 1, 8))),
  customer_id           uuid not null references public.users(id),
  provider_id           uuid not null references laundry_providers(id),
  status                laundry_booking_status not null default 'new_request',
  pickup_address        text not null,
  pickup_latitude       double precision,
  pickup_longitude      double precision,
  return_address        text not null,
  return_latitude       double precision,
  return_longitude      double precision,
  pickup_date           date not null,
  pickup_time_slot      text not null,
  return_date           date,
  return_time_slot      text,
  estimated_weight_kg   double precision,
  estimated_bags        int default 1,
  customer_notes        text,
  special_instructions  text,
  actual_weight_kg      double precision,
  actual_bags           int,
  provider_notes        text,
  estimated_total       double precision,
  actual_total          double precision,
  pickup_fee            double precision default 0,
  delivery_fee          double precision default 0,
  platform_fee          double precision default 0,
  discount_amount       double precision default 0,
  currency              text default 'USD',
  payment_method        text default 'card',
  stripe_payment_intent_id text,
  stripe_charge_id      text,
  payment_status        text default 'pending',
  price_approved_by_customer boolean default false,
  customer_rating_provider int check (customer_rating_provider between 1 and 5),
  customer_rating_driver   int check (customer_rating_driver   between 1 and 5),
  customer_review          text,
  provider_rating_customer int check (provider_rating_customer between 1 and 5),
  cancellation_reason   text,
  cancelled_by          text,
  cancelled_at          timestamptz,
  completed_at          timestamptz,
  created_at            timestamptz not null default now(),
  updated_at            timestamptz
);
create index if not exists idx_laundry_bookings_customer on laundry_bookings(customer_id);
create index if not exists idx_laundry_bookings_provider on laundry_bookings(provider_id);
create index if not exists idx_laundry_bookings_status   on laundry_bookings(status);
create index if not exists idx_laundry_bookings_pickup   on laundry_bookings(pickup_date);
create index if not exists idx_laundry_bookings_created  on laundry_bookings(created_at desc);

create table if not exists laundry_booking_items (
  id           uuid primary key default uuid_generate_v4(),
  booking_id   uuid not null references laundry_bookings(id) on delete cascade,
  service_id   uuid references laundry_services(id),   -- nullable so text-named items work too
  service_name text not null,
  quantity     int default 1,
  unit_price   double precision default 0,
  total_price  double precision default 0,
  notes        text,
  created_at   timestamptz not null default now()
);
create index if not exists idx_laundry_bi_booking on laundry_booking_items(booking_id);

create table if not exists laundry_status_history (
  id         uuid primary key default uuid_generate_v4(),
  booking_id uuid not null references laundry_bookings(id) on delete cascade,
  status     laundry_booking_status not null,
  actor_id   uuid references public.users(id),
  actor_role text,
  note       text,
  created_at timestamptz not null default now()
);
create index if not exists idx_laundry_sh_booking on laundry_status_history(booking_id, created_at);

create table if not exists laundry_photos (
  id          uuid primary key default uuid_generate_v4(),
  booking_id  uuid not null references laundry_bookings(id) on delete cascade,
  uploader_id uuid references public.users(id),
  photo_type  text not null,
  url         text not null,
  caption     text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_laundry_photos_booking on laundry_photos(booking_id);

create table if not exists laundry_weights (
  id          uuid primary key default uuid_generate_v4(),
  booking_id  uuid not null references laundry_bookings(id) on delete cascade,
  weight_kg   double precision not null,
  recorded_by uuid references public.users(id),
  photo_url   text,
  notes       text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_laundry_weights_booking on laundry_weights(booking_id);

create table if not exists laundry_driver_assignments (
  id               uuid primary key default uuid_generate_v4(),
  booking_id       uuid not null references laundry_bookings(id),
  driver_id        uuid not null references public.users(id),
  leg              laundry_driver_leg not null,
  status           laundry_driver_status not null default 'assigned_pickup',
  assigned_at      timestamptz not null default now(),
  accepted_at      timestamptz,
  completed_at     timestamptz,
  pickup_proof_url  text,
  dropoff_proof_url text,
  driver_notes     text,
  unique (booking_id, leg)
);
create index if not exists idx_laundry_da_driver  on laundry_driver_assignments(driver_id);
create index if not exists idx_laundry_da_booking on laundry_driver_assignments(booking_id);

create table if not exists laundry_reviews (
  id                uuid primary key default uuid_generate_v4(),
  booking_id        uuid not null unique references laundry_bookings(id),
  customer_id       uuid not null references public.users(id),
  provider_id       uuid not null references laundry_providers(id),
  driver_id         uuid references public.users(id),
  provider_rating   int check (provider_rating between 1 and 5),
  driver_rating     int check (driver_rating   between 1 and 5),
  review_text       text,
  provider_response text,
  created_at        timestamptz not null default now()
);
create index if not exists idx_laundry_reviews_provider on laundry_reviews(provider_id);

create table if not exists laundry_disputes (
  id          uuid primary key default uuid_generate_v4(),
  booking_id  uuid not null references laundry_bookings(id),
  opened_by   uuid not null references public.users(id),
  reason      text not null,
  description text,
  status      text not null default 'open',
  resolution  text,
  resolved_by uuid references public.users(id),
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);

create table if not exists laundry_provider_documents (
  id                  uuid primary key default uuid_generate_v4(),
  provider_id         uuid not null references laundry_providers(id) on delete cascade,
  document_type       text not null,
  document_number     text,
  photo_url           text,
  expiry_date         date,
  verification_status text default 'pending',
  rejection_reason    text,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz,
  unique (provider_id, document_type)
);

create table if not exists laundry_provider_payouts (
  id                 uuid primary key default uuid_generate_v4(),
  provider_id        uuid not null references laundry_providers(id),
  amount             double precision not null,
  currency           text default 'USD',
  period_start       date not null,
  period_end         date not null,
  booking_count      int default 0,
  gross_revenue      double precision default 0,
  commission         double precision default 0,
  net_payout         double precision default 0,
  stripe_transfer_id text,
  status             text default 'pending',
  paid_at            timestamptz,
  created_at         timestamptz not null default now()
);
create index if not exists idx_laundry_payouts_provider on laundry_provider_payouts(provider_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- TRIGGERS
-- ─────────────────────────────────────────────────────────────────────────────

create or replace function update_laundry_booking_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_laundry_bookings_updated_at on laundry_bookings;
create trigger trg_laundry_bookings_updated_at
  before update on laundry_bookings
  for each row execute function update_laundry_booking_updated_at();

create or replace function update_laundry_provider_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end; $$;

drop trigger if exists trg_laundry_providers_updated_at on laundry_providers;
create trigger trg_laundry_providers_updated_at
  before update on laundry_providers
  for each row execute function update_laundry_provider_updated_at();

-- Auto-log status changes into history
create or replace function laundry_booking_status_history_trigger()
returns trigger language plpgsql security definer as $$
begin
  if (tg_op = 'INSERT') or (old.status is distinct from new.status) then
    insert into laundry_status_history (booking_id, status, actor_role)
    values (new.id, new.status, 'system');
  end if;
  return new;
end; $$;

drop trigger if exists trg_laundry_status_history on laundry_bookings;
create trigger trg_laundry_status_history
  after insert or update on laundry_bookings
  for each row execute function laundry_booking_status_history_trigger();

-- Notify provider when a new booking arrives
create or replace function laundry_notify_provider_on_booking()
returns trigger language plpgsql security definer as $$
declare
  v_provider_user_id uuid;
  v_customer_name    text;
begin
  -- Get provider's user_id
  select user_id into v_provider_user_id
  from laundry_providers where id = new.provider_id;

  -- Get customer name
  select coalesce(name, 'A customer') into v_customer_name
  from public.users where id = new.customer_id;

  -- Insert notification for provider
  if v_provider_user_id is not null then
    insert into notifications (user_id, title, body, type, data)
    values (
      v_provider_user_id,
      'New Laundry Booking',
      v_customer_name || ' has requested a pickup on ' ||
        to_char(new.pickup_date, 'Mon DD') || ' (' || new.pickup_time_slot || ')',
      'laundry_booking',
      jsonb_build_object(
        'booking_id',     new.id,
        'booking_number', new.booking_number,
        'status',         new.status::text
      )
    );
  end if;

  -- Insert notification for admin
  insert into notifications (user_id, title, body, type, data)
  select u.id,
    'New Laundry Order ' || new.booking_number,
    v_customer_name || ' booked laundry pickup for ' || to_char(new.pickup_date, 'Mon DD'),
    'laundry_booking',
    jsonb_build_object('booking_id', new.id, 'booking_number', new.booking_number)
  from public.users u
  where u.role = 'admin';

  return new;
end; $$;

drop trigger if exists trg_laundry_notify_provider on laundry_bookings;
create trigger trg_laundry_notify_provider
  after insert on laundry_bookings
  for each row execute function laundry_notify_provider_on_booking();

-- Notify customer when booking status changes
create or replace function laundry_notify_customer_on_status_change()
returns trigger language plpgsql security definer as $$
declare
  v_title text;
  v_body  text;
begin
  if old.status = new.status then return new; end if;

  v_title := 'Laundry Update: ' || new.booking_number;
  v_body  := case new.status
    when 'accepted'               then 'Your booking has been accepted! We''ll pick up on the scheduled date.'
    when 'waiting_for_pickup'     then 'Your laundry will be picked up shortly.'
    when 'picked_up_from_customer'then 'Your laundry has been collected.'
    when 'received_at_laundry'    then 'Your laundry arrived at the facility.'
    when 'weighed'                then 'Your laundry has been weighed. Please approve the final price.'
    when 'price_confirmed'        then 'Price confirmed. Washing is starting soon.'
    when 'washing_cleaning'       then 'Your laundry is being washed and cleaned.'
    when 'quality_check'          then 'Quality check in progress.'
    when 'ready_for_delivery'     then 'Your laundry is clean and ready for delivery!'
    when 'out_for_delivery'       then 'Your clean laundry is on the way!'
    when 'completed'              then 'Your laundry has been delivered. How was the service?'
    when 'cancelled'              then 'Your laundry booking has been cancelled.'
    else 'Your booking status has been updated.'
  end;

  insert into notifications (user_id, title, body, type, data)
  values (
    new.customer_id, v_title, v_body, 'laundry_status',
    jsonb_build_object(
      'booking_id',     new.id,
      'booking_number', new.booking_number,
      'status',         new.status::text
    )
  );

  return new;
end; $$;

drop trigger if exists trg_laundry_notify_customer on laundry_bookings;
create trigger trg_laundry_notify_customer
  after update on laundry_bookings
  for each row execute function laundry_notify_customer_on_status_change();

-- ─────────────────────────────────────────────────────────────────────────────
-- RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table laundry_providers          enable row level security;
alter table laundry_services           enable row level security;
alter table laundry_provider_services  enable row level security;
alter table laundry_pricing            enable row level security;
alter table laundry_bookings           enable row level security;
alter table laundry_booking_items      enable row level security;
alter table laundry_status_history     enable row level security;
alter table laundry_photos             enable row level security;
alter table laundry_weights            enable row level security;
alter table laundry_driver_assignments enable row level security;
alter table laundry_reviews            enable row level security;
alter table laundry_disputes           enable row level security;
alter table laundry_provider_documents enable row level security;
alter table laundry_provider_payouts   enable row level security;

-- Drop all existing policies first (idempotent)
do $$ declare r record; begin
  for r in
    select policyname, tablename from pg_policies
    where schemaname = 'public' and tablename like 'laundry%'
  loop
    execute format('drop policy if exists %I on %I', r.policyname, r.tablename);
  end loop;
end $$;

-- laundry_services  — public read, admin write
create policy "ls_read_all"   on laundry_services for select using (true);
create policy "ls_admin_write" on laundry_services for all using (
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_providers
create policy "lp_select" on laundry_providers for select using (
  is_active = true or user_id = auth.uid() or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "lp_insert" on laundry_providers for insert with check (user_id = auth.uid());
create policy "lp_update" on laundry_providers for update using (
  user_id = auth.uid() or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "lp_delete" on laundry_providers for delete using (
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_provider_services
create policy "lps_select" on laundry_provider_services for select using (true);
create policy "lps_write"  on laundry_provider_services for all using (
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_pricing
create policy "lprice_select" on laundry_pricing for select using (true);
create policy "lprice_write"  on laundry_pricing for all using (
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_bookings
create policy "lb_select" on laundry_bookings for select using (
  customer_id = auth.uid() or
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
  exists (select 1 from laundry_driver_assignments lda where lda.booking_id = laundry_bookings.id and lda.driver_id = auth.uid()) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "lb_insert" on laundry_bookings for insert with check (customer_id = auth.uid());
create policy "lb_update" on laundry_bookings for update using (
  customer_id = auth.uid() or
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
  exists (select 1 from laundry_driver_assignments lda where lda.booking_id = laundry_bookings.id and lda.driver_id = auth.uid()) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_booking_items
create policy "lbi_select" on laundry_booking_items for select using (
  exists (select 1 from laundry_bookings b where b.id = booking_id and (
    b.customer_id = auth.uid() or
    exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid()) or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'))));
create policy "lbi_insert" on laundry_booking_items for insert with check (
  exists (select 1 from laundry_bookings b where b.id = booking_id and b.customer_id = auth.uid()));

-- laundry_status_history
create policy "lsh_select" on laundry_status_history for select using (
  exists (select 1 from laundry_bookings b where b.id = booking_id and (
    b.customer_id = auth.uid() or
    exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid()) or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'))));
create policy "lsh_insert_system" on laundry_status_history for insert with check (
  exists (select 1 from laundry_bookings b where b.id = booking_id and (
    b.customer_id = auth.uid() or
    exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid()) or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'))));

-- laundry_photos
create policy "lphoto_select" on laundry_photos for select using (
  uploader_id = auth.uid() or
  exists (select 1 from laundry_bookings b where b.id = booking_id and (
    b.customer_id = auth.uid() or
    exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid()) or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'))));
create policy "lphoto_insert" on laundry_photos for insert with check (uploader_id = auth.uid());

-- laundry_weights
create policy "lw_select" on laundry_weights for select using (
  exists (select 1 from laundry_bookings b where b.id = booking_id and (
    b.customer_id = auth.uid() or
    exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid()) or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'))));
create policy "lw_insert" on laundry_weights for insert with check (
  exists (select 1 from laundry_bookings b
    join laundry_providers p on p.id = b.provider_id
    where b.id = booking_id and p.user_id = auth.uid()));

-- laundry_driver_assignments
create policy "lda_select" on laundry_driver_assignments for select using (
  driver_id = auth.uid() or
  exists (select 1 from laundry_bookings b where b.id = booking_id and (
    b.customer_id = auth.uid() or
    exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid()))) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "lda_insert" on laundry_driver_assignments for insert with check (
  exists (select 1 from public.users where id = auth.uid() and role = 'admin') or
  exists (select 1 from laundry_bookings b
    join laundry_providers p on p.id = b.provider_id
    where b.id = booking_id and p.user_id = auth.uid()));
create policy "lda_update" on laundry_driver_assignments for update using (
  driver_id = auth.uid() or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_reviews
create policy "lr_select" on laundry_reviews for select using (true);
create policy "lr_insert" on laundry_reviews for insert with check (customer_id = auth.uid());
create policy "lr_update" on laundry_reviews for update using (
  customer_id = auth.uid() or
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()));

-- laundry_disputes
create policy "ldis_select" on laundry_disputes for select using (
  opened_by = auth.uid() or
  exists (select 1 from laundry_bookings b where b.id = booking_id and
    exists (select 1 from laundry_providers where id = b.provider_id and user_id = auth.uid())) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "ldis_insert" on laundry_disputes for insert with check (opened_by = auth.uid());
create policy "ldis_update" on laundry_disputes for update using (
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_provider_documents
create policy "ldoc_select" on laundry_provider_documents for select using (
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "ldoc_write" on laundry_provider_documents for all using (
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- laundry_provider_payouts
create policy "lpay_select" on laundry_provider_payouts for select using (
  exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "lpay_write" on laundry_provider_payouts for all using (
  exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- ─────────────────────────────────────────────────────────────────────────────
-- MASTER SERVICE CATALOGUE  (upsert so re-runs are safe)
-- ─────────────────────────────────────────────────────────────────────────────
insert into laundry_services (name, description, icon, sort_order) values
  ('Wash & Fold',        'Full wash, dry and fold service',        'local_laundry_service', 1),
  ('Wash Only',          'Machine wash without drying/folding',    'water_drop',            2),
  ('Dry Only',           'Tumble dry or line dry only',            'air',                   3),
  ('Ironing',            'Professional pressing and ironing',      'iron',                  4),
  ('Dry Cleaning',       'Professional dry-clean treatment',       'dry_cleaning',          5),
  ('Express Laundry',    'Same-day turnaround service',            'bolt',                  6),
  ('Bedding Cleaning',   'Sheets, duvet covers, pillowcases',      'bed',                   7),
  ('Uniform Cleaning',   'Work uniforms and professional attire',  'work',                  8),
  ('Delicates Cleaning', 'Gentle cycle for delicate fabrics',      'diamond',               9)
on conflict (name) do update
  set description = excluded.description,
      icon        = excluded.icon,
      sort_order  = excluded.sort_order;

-- ─────────────────────────────────────────────────────────────────────────────
-- SEED: 4 REAL LAUNDRY PROVIDERS
-- ─────────────────────────────────────────────────────────────────────────────
-- Step 1: Create user accounts for each provider
insert into public.users (id, email, name, role, onboarding_completed, is_active, created_at)
values
  ('a1000001-0000-4000-8000-000000000001', 'freshwave@laundry.app',    'FreshWave Laundry',  'laundry_provider', true, true, now()),
  ('a1000002-0000-4000-8000-000000000002', 'spincycle@laundry.app',    'SpinCycle Pro',      'laundry_provider', true, true, now()),
  ('a1000003-0000-4000-8000-000000000003', 'crystalclean@laundry.app', 'Crystal Clean',      'laundry_provider', true, true, now()),
  ('a1000004-0000-4000-8000-000000000004', 'quicksuds@laundry.app',    'QuickSuds Express',  'laundry_provider', true, true, now())
on conflict (id) do nothing;

-- Step 2: Create the laundry provider profiles
insert into laundry_providers (
  id, user_id, business_name, description, address, phone, email,
  latitude, longitude, status, is_active, is_verified,
  rating, review_count, pickup_radius_km, commission_rate, onboarding_step, created_at
) values
  (
    'b1000001-0000-4000-8000-000000000001',
    'a1000001-0000-4000-8000-000000000001',
    'FreshWave Laundry',
    'Premium wash & fold with same-day express options. We handle everything from everyday clothes to delicates with care.',
    '14 Harbour Drive, George Town',
    '+1 345-555-0101', 'freshwave@laundry.app',
    19.3000, -81.3850, 'active', true, true, 4.8, 127, 12, 0.15, 4, now()
  ),
  (
    'b1000002-0000-4000-8000-000000000002',
    'a1000002-0000-4000-8000-000000000002',
    'SpinCycle Pro',
    'Industrial-grade cleaning for homes and businesses. Specialising in bedding, uniforms and bulk laundry at competitive rates.',
    '8 Eastern Avenue, Bodden Town',
    '+1 345-555-0202', 'spincycle@laundry.app',
    19.2700, -81.2600, 'active', true, true, 4.5, 89, 15, 0.15, 4, now()
  ),
  (
    'b1000003-0000-4000-8000-000000000003',
    'a1000003-0000-4000-8000-000000000003',
    'Crystal Clean',
    'Eco-friendly dry cleaning and delicates specialist. All garments treated with biodegradable solvents.',
    '22 West Bay Road, Seven Mile Beach',
    '+1 345-555-0303', 'crystalclean@laundry.app',
    19.3600, -81.3900, 'active', true, true, 4.9, 214, 10, 0.15, 4, now()
  ),
  (
    'b1000004-0000-4000-8000-000000000004',
    'a1000004-0000-4000-8000-000000000004',
    'QuickSuds Express',
    '2-hour express turnaround for busy professionals. Wash, dry and fold delivered back within hours. Open 7 days.',
    '5 Shedden Road, George Town',
    '+1 345-555-0404', 'quicksuds@laundry.app',
    19.2950, -81.3800, 'active', true, true, 4.6, 73, 8, 0.15, 4, now()
  )
on conflict (id) do update
  set status = 'active', is_active = true, is_verified = true,
      rating = excluded.rating, review_count = excluded.review_count;

-- Step 3: Pricing for each provider
insert into laundry_pricing (provider_id, pickup_fee, delivery_fee, min_order_fee, currency)
values
  ('b1000001-0000-4000-8000-000000000001', 2.50, 2.50, 10.00, 'USD'),
  ('b1000002-0000-4000-8000-000000000002', 0.00, 0.00, 15.00, 'USD'),
  ('b1000003-0000-4000-8000-000000000003', 3.00, 3.00, 20.00, 'USD'),
  ('b1000004-0000-4000-8000-000000000004', 5.00, 5.00, 12.00, 'USD')
on conflict (provider_id) do update
  set pickup_fee   = excluded.pickup_fee,
      delivery_fee = excluded.delivery_fee,
      min_order_fee = excluded.min_order_fee;

-- Step 4: Services for each provider  (look up service IDs by name)
insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000001-0000-4000-8000-000000000001', id, true, 3.50, 24 from laundry_services where name = 'Wash & Fold'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, ironing_fee, estimated_hours)
select 'b1000001-0000-4000-8000-000000000001', id, true, 2.00, 6 from laundry_services where name = 'Ironing'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, express_fee, estimated_hours)
select 'b1000001-0000-4000-8000-000000000001', id, true, 5.00, 3.00, 2 from laundry_services where name = 'Express Laundry'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000001-0000-4000-8000-000000000001', id, true, 4.00, 24 from laundry_services where name = 'Bedding Cleaning'
on conflict (provider_id, service_id) do nothing;

-- SpinCycle Pro
insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000002-0000-4000-8000-000000000002', id, true, 2.80, 24 from laundry_services where name = 'Wash & Fold'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000002-0000-4000-8000-000000000002', id, true, 3.00, 12 from laundry_services where name = 'Uniform Cleaning'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000002-0000-4000-8000-000000000002', id, true, 3.50, 24 from laundry_services where name = 'Bedding Cleaning'
on conflict (provider_id, service_id) do nothing;

-- Crystal Clean
insert into laundry_provider_services (provider_id, service_id, is_available, dry_cleaning_fee, estimated_hours)
select 'b1000003-0000-4000-8000-000000000003', id, true, 12.00, 48 from laundry_services where name = 'Dry Cleaning'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000003-0000-4000-8000-000000000003', id, true, 4.50, 36 from laundry_services where name = 'Delicates Cleaning'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000003-0000-4000-8000-000000000003', id, true, 4.00, 24 from laundry_services where name = 'Wash & Fold'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, ironing_fee, estimated_hours)
select 'b1000003-0000-4000-8000-000000000003', id, true, 3.00, 8 from laundry_services where name = 'Ironing'
on conflict (provider_id, service_id) do nothing;

-- QuickSuds Express
insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000004-0000-4000-8000-000000000004', id, true, 4.00, 2 from laundry_services where name = 'Wash & Fold'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, express_fee, estimated_hours)
select 'b1000004-0000-4000-8000-000000000004', id, true, 6.00, 4.00, 2 from laundry_services where name = 'Express Laundry'
on conflict (provider_id, service_id) do nothing;

insert into laundry_provider_services (provider_id, service_id, is_available, price_per_kg, estimated_hours)
select 'b1000004-0000-4000-8000-000000000004', id, true, 3.00, 2 from laundry_services where name = 'Wash Only'
on conflict (provider_id, service_id) do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- STORAGE BUCKETS
-- ─────────────────────────────────────────────────────────────────────────────
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values
  ('laundry-provider-logos',     'laundry-provider-logos',     true,  5242880,  array['image/jpeg','image/png','image/webp']),
  ('laundry-provider-documents', 'laundry-provider-documents', false, 10485760, array['image/jpeg','image/png','application/pdf']),
  ('laundry-order-photos',       'laundry-order-photos',       false, 10485760, array['image/jpeg','image/png','image/webp']),
  ('laundry-before-photos',      'laundry-before-photos',      false, 10485760, array['image/jpeg','image/png','image/webp']),
  ('laundry-after-photos',       'laundry-after-photos',       false, 10485760, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

-- Storage policies
drop policy if exists "laundry logos public read"           on storage.objects;
drop policy if exists "laundry logos provider upload"       on storage.objects;
drop policy if exists "laundry docs provider upload"        on storage.objects;
drop policy if exists "laundry docs owner read"             on storage.objects;
drop policy if exists "laundry order photos upload"         on storage.objects;
drop policy if exists "laundry order photos read auth"      on storage.objects;

create policy "laundry logos public read" on storage.objects
  for select using (bucket_id = 'laundry-provider-logos');

create policy "laundry logos provider upload" on storage.objects
  for insert with check (bucket_id = 'laundry-provider-logos' and auth.uid() is not null);

create policy "laundry docs provider upload" on storage.objects
  for insert with check (bucket_id = 'laundry-provider-documents' and auth.uid() is not null);

create policy "laundry docs owner read" on storage.objects
  for select using (
    bucket_id = 'laundry-provider-documents' and auth.uid() is not null and (
      (storage.foldername(name))[1] = auth.uid()::text or
      exists (select 1 from public.users where id = auth.uid() and role = 'admin')
    ));

create policy "laundry order photos upload" on storage.objects
  for insert with check (
    bucket_id in ('laundry-order-photos','laundry-before-photos','laundry-after-photos') and
    auth.uid() is not null);

create policy "laundry order photos read auth" on storage.objects
  for select using (
    bucket_id in ('laundry-order-photos','laundry-before-photos','laundry-after-photos') and
    auth.uid() is not null);

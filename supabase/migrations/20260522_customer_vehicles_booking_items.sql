-- ============================================================
-- Migration: Customer Vehicles + Multi-Service Booking Items
-- ============================================================

-- ── customer_vehicles ────────────────────────────────────────
create table if not exists public.customer_vehicles (
  id            uuid primary key default gen_random_uuid(),
  customer_id   uuid not null references auth.users(id) on delete cascade,
  nickname      text,
  make          text not null,
  model         text not null,
  year          int  check (year > 1900 and year <= extract(year from now())::int + 2),
  color         text,
  license_plate text,
  vehicle_type  text not null check (vehicle_type in ('sedan','suv','van','truck','bike')),
  photo_url     text,
  is_default    boolean not null default false,
  is_active     boolean not null default true,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

create index if not exists idx_customer_vehicles_customer on public.customer_vehicles(customer_id);
create index if not exists idx_customer_vehicles_type    on public.customer_vehicles(vehicle_type);
create index if not exists idx_customer_vehicles_active  on public.customer_vehicles(is_active);

-- Only one default per customer (partial unique index)
create unique index if not exists idx_customer_vehicles_one_default
  on public.customer_vehicles(customer_id)
  where is_default = true and is_active = true;

-- updated_at trigger
create or replace function public.set_updated_at()
returns trigger language plpgsql as $$
begin new.updated_at = now(); return new; end;
$$;

drop trigger if exists trg_customer_vehicles_updated_at on public.customer_vehicles;
create trigger trg_customer_vehicles_updated_at
  before update on public.customer_vehicles
  for each row execute function public.set_updated_at();

-- RLS
alter table public.customer_vehicles enable row level security;

drop policy if exists "customer_vehicles_select_own" on public.customer_vehicles;
create policy "customer_vehicles_select_own" on public.customer_vehicles
  for select using (auth.uid() = customer_id and is_active = true);

drop policy if exists "customer_vehicles_insert_own" on public.customer_vehicles;
create policy "customer_vehicles_insert_own" on public.customer_vehicles
  for insert with check (auth.uid() = customer_id);

drop policy if exists "customer_vehicles_update_own" on public.customer_vehicles;
create policy "customer_vehicles_update_own" on public.customer_vehicles
  for update using (auth.uid() = customer_id);

-- ── service_booking_items ────────────────────────────────────
create table if not exists public.service_booking_items (
  id                    uuid primary key default gen_random_uuid(),
  booking_id            uuid not null references public.car_service_bookings(id) on delete cascade,
  service_id            uuid not null references public.car_service_offerings(id),
  vehicle_id            uuid references public.customer_vehicles(id),
  service_name_snapshot text not null,
  vehicle_snapshot      jsonb,
  base_price            numeric not null default 0,
  vehicle_price         numeric not null default 0,
  add_on_price          numeric not null default 0,
  quantity              int not null default 1,
  line_total            numeric not null default 0,
  created_at            timestamptz not null default now()
);

create index if not exists idx_sbi_booking  on public.service_booking_items(booking_id);
create index if not exists idx_sbi_vehicle  on public.service_booking_items(vehicle_id);
create index if not exists idx_sbi_service  on public.service_booking_items(service_id);

-- RLS
alter table public.service_booking_items enable row level security;

drop policy if exists "sbi_select_customer" on public.service_booking_items;
create policy "sbi_select_customer" on public.service_booking_items
  for select using (
    exists (
      select 1 from public.car_service_bookings b
      where b.id = booking_id and b.customer_id = auth.uid()
    )
  );

drop policy if exists "sbi_select_provider" on public.service_booking_items;
create policy "sbi_select_provider" on public.service_booking_items
  for select using (
    exists (
      select 1
      from public.car_service_bookings b
      join public.car_service_providers p on p.id = b.provider_id
      where b.id = booking_id and p.user_id = auth.uid()
    )
  );

drop policy if exists "sbi_insert_own" on public.service_booking_items;
create policy "sbi_insert_own" on public.service_booking_items
  for insert with check (
    exists (
      select 1 from public.car_service_bookings b
      where b.id = booking_id and b.customer_id = auth.uid()
    )
  );

-- ── Alter car_service_bookings — add new columns ─────────────
do $$ begin

  if not exists (select 1 from information_schema.columns
    where table_name='car_service_bookings' and column_name='selected_address_id') then
    alter table public.car_service_bookings add column selected_address_id uuid;
  end if;

  if not exists (select 1 from information_schema.columns
    where table_name='car_service_bookings' and column_name='vehicle_count') then
    alter table public.car_service_bookings add column vehicle_count int not null default 1;
  end if;

  if not exists (select 1 from information_schema.columns
    where table_name='car_service_bookings' and column_name='service_count') then
    alter table public.car_service_bookings add column service_count int not null default 1;
  end if;

  if not exists (select 1 from information_schema.columns
    where table_name='car_service_bookings' and column_name='items_subtotal') then
    alter table public.car_service_bookings add column items_subtotal numeric not null default 0;
  end if;

  if not exists (select 1 from information_schema.columns
    where table_name='car_service_bookings' and column_name='mobile_fee') then
    alter table public.car_service_bookings add column mobile_fee numeric not null default 0;
  end if;

  if not exists (select 1 from information_schema.columns
    where table_name='car_service_bookings' and column_name='discount_amount') then
    alter table public.car_service_bookings add column discount_amount numeric not null default 0;
  end if;

end $$;

-- ── Storage bucket for vehicle photos ────────────────────────
insert into storage.buckets (id, name, public)
values ('vehicle-photos', 'vehicle-photos', true)
on conflict (id) do nothing;

drop policy if exists "vehicle_photos_upload_own" on storage.objects;
create policy "vehicle_photos_upload_own" on storage.objects
  for insert with check (
    bucket_id = 'vehicle-photos'
    and auth.uid()::text = (storage.foldername(name))[2]
  );

drop policy if exists "vehicle_photos_public_read" on storage.objects;
create policy "vehicle_photos_public_read" on storage.objects
  for select using (bucket_id = 'vehicle-photos');

drop policy if exists "vehicle_photos_delete_own" on storage.objects;
create policy "vehicle_photos_delete_own" on storage.objects
  for delete using (
    bucket_id = 'vehicle-photos'
    and auth.uid()::text = (storage.foldername(name))[2]
  );

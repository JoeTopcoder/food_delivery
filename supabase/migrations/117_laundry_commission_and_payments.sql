-- =============================================================================
-- LAUNDRY: COMMISSION, WALLET RESERVATIONS, DRIVER JOBS, PAYMENT SETTLEMENT
-- Safe to re-run. Does NOT touch existing food/ride/grocery wallet logic.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- 1. EXTEND BOOKING STATUSES
-- ─────────────────────────────────────────────────────────────────────────────
alter type laundry_booking_status add value if not exists 'pickup_driver_searching';
alter type laundry_booking_status add value if not exists 'pickup_driver_assigned';
alter type laundry_booking_status add value if not exists 'return_payment_required';
alter type laundry_booking_status add value if not exists 'return_driver_searching';
alter type laundry_booking_status add value if not exists 'return_driver_assigned';

-- ─────────────────────────────────────────────────────────────────────────────
-- 2. EXTEND WALLETS TABLE  (additive — existing balance/cashback untouched)
-- ─────────────────────────────────────────────────────────────────────────────
alter table wallets
  add column if not exists reserved_balance decimal(12,2) not null default 0
    check (reserved_balance >= 0);

-- ─────────────────────────────────────────────────────────────────────────────
-- 3. LAUNDRY LEDGER  (isolated from food/ride wallet_transactions)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_ledger_entries (
  id               uuid primary key default uuid_generate_v4(),
  wallet_id        uuid not null references wallets(user_id),
  user_id          uuid not null references public.users(id),
  booking_id       uuid references laundry_bookings(id),
  entry_type       text not null check (entry_type in (
                     'reserve','release','top_up_reserve','capture',
                     'refund','cancellation_fee','provider_payout',
                     'pickup_driver_payout','return_driver_payout',
                     'platform_commission','platform_service_fee')),
  amount           decimal(12,2) not null,          -- always positive
  balance_before   decimal(12,2) not null,
  balance_after    decimal(12,2) not null,
  reserved_before  decimal(12,2) not null default 0,
  reserved_after   decimal(12,2) not null default 0,
  reference_id     text,                             -- split_id, job_id, etc.
  note             text,
  metadata         jsonb,
  created_at       timestamptz not null default now()
);
create index if not exists idx_laundry_ledger_wallet  on laundry_ledger_entries(wallet_id);
create index if not exists idx_laundry_ledger_booking on laundry_ledger_entries(booking_id);
create index if not exists idx_laundry_ledger_user    on laundry_ledger_entries(user_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 4. WALLET RESERVATIONS  (per-component breakdown)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_wallet_reservations (
  id               uuid primary key default uuid_generate_v4(),
  booking_id       uuid not null references laundry_bookings(id) on delete cascade,
  customer_id      uuid not null references public.users(id),
  component        text not null check (component in (
                     'laundry_service','pickup_delivery',
                     'return_delivery','platform_service_fee')),
  reserved_amount  decimal(12,2) not null check (reserved_amount >= 0),
  status           text not null default 'reserved'
                     check (status in ('reserved','released','captured','refunded')),
  created_at       timestamptz not null default now(),
  updated_at       timestamptz,
  unique (booking_id, component)
);
create index if not exists idx_laundry_reservations_booking  on laundry_wallet_reservations(booking_id);
create index if not exists idx_laundry_reservations_customer on laundry_wallet_reservations(customer_id);

-- ─────────────────────────────────────────────────────────────────────────────
-- 5. COMMISSION SETTINGS
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_commission_settings (
  id                          uuid primary key default uuid_generate_v4(),
  provider_id                 uuid references laundry_providers(id) on delete cascade,
  commission_type             text not null default 'percentage'
                                check (commission_type in ('percentage','fixed')),
  commission_value            decimal(10,4) not null default 0.15,
  customer_service_fee        decimal(10,2) not null default 0,
  customer_service_fee_type   text not null default 'fixed'
                                check (customer_service_fee_type in ('fixed','percentage')),
  applies_to_express_fee      boolean not null default true,
  applies_to_addon_services   boolean not null default true,
  applies_to_delivery_fee     boolean not null default false,
  is_default                  boolean not null default false,
  is_active                   boolean not null default true,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz
);
-- Only one active default at a time
create unique index if not exists idx_laundry_commission_default
  on laundry_commission_settings(is_default) where (is_default = true and is_active = true);
create index if not exists idx_laundry_commission_provider
  on laundry_commission_settings(provider_id) where provider_id is not null;

-- ─────────────────────────────────────────────────────────────────────────────
-- 6. PAYMENT SPLITS  (immutable snapshot per booking)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_payment_splits (
  id                       uuid primary key default uuid_generate_v4(),
  booking_id               uuid not null unique references laundry_bookings(id),
  customer_id              uuid not null references public.users(id),
  provider_id              uuid not null references laundry_providers(id),
  pickup_driver_id         uuid references public.users(id),
  return_driver_id         uuid references public.users(id),

  -- Amounts
  final_laundry_amount     decimal(12,2) not null default 0,
  pickup_delivery_fee      decimal(12,2) not null default 0,
  return_delivery_fee      decimal(12,2) not null default 0,
  customer_service_fee     decimal(12,2) not null default 0,
  final_total              decimal(12,2) not null default 0,

  -- Commission snapshot
  commissionable_amount    decimal(12,2) not null default 0,
  commission_rate          decimal(10,4) not null default 0,
  commission_type          text not null default 'percentage',
  platform_commission      decimal(12,2) not null default 0,

  -- Payouts
  provider_gross_amount    decimal(12,2) not null default 0,
  provider_net_earning     decimal(12,2) not null default 0,
  pickup_driver_earning    decimal(12,2) not null default 0,
  return_driver_earning    decimal(12,2) not null default 0,
  platform_total_earning   decimal(12,2) not null default 0,

  currency                 text not null default 'USD',
  status                   text not null default 'pending'
                             check (status in ('pending','settled','refunded','disputed')),
  settled_at               timestamptz,
  created_at               timestamptz not null default now()
);
create index if not exists idx_laundry_splits_booking  on laundry_payment_splits(booking_id);
create index if not exists idx_laundry_splits_provider on laundry_payment_splits(provider_id);
create index if not exists idx_laundry_splits_status   on laundry_payment_splits(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 7. DRIVER JOBS  (pickup and return are completely separate)
-- ─────────────────────────────────────────────────────────────────────────────
create table if not exists laundry_driver_jobs (
  id                  uuid primary key default uuid_generate_v4(),
  booking_id          uuid not null references laundry_bookings(id) on delete cascade,
  job_type            text not null check (job_type in ('pickup','return_delivery')),
  driver_id           uuid references public.users(id),
  pickup_address      text not null,
  pickup_lat          double precision,
  pickup_lng          double precision,
  dropoff_address     text not null,
  dropoff_lat         double precision,
  dropoff_lng         double precision,
  distance_km         double precision,
  estimated_minutes   int,
  delivery_fee        decimal(10,2) not null default 0,
  driver_payout       decimal(10,2) not null default 0,
  platform_margin     decimal(10,2) not null default 0,
  status              text not null default 'pending'
                        check (status in (
                          'pending','searching','assigned','accepted',
                          'picked_up','dropped_off','completed','cancelled')),
  broadcast_at        timestamptz,
  accepted_at         timestamptz,
  picked_up_at        timestamptz,
  dropped_off_at      timestamptz,
  completed_at        timestamptz,
  proof_url           text,
  driver_notes        text,
  created_at          timestamptz not null default now(),
  unique (booking_id, job_type)    -- one active job per type per booking
);
create index if not exists idx_laundry_jobs_booking on laundry_driver_jobs(booking_id);
create index if not exists idx_laundry_jobs_driver  on laundry_driver_jobs(driver_id);
create index if not exists idx_laundry_jobs_status  on laundry_driver_jobs(status);

-- ─────────────────────────────────────────────────────────────────────────────
-- 8. EXTEND laundry_bookings  (payment tracking columns)
-- ─────────────────────────────────────────────────────────────────────────────
alter table laundry_bookings
  add column if not exists reserved_amount    decimal(12,2) default 0,
  add column if not exists return_delivery_fee decimal(12,2) default 0,
  add column if not exists customer_service_fee decimal(12,2) default 0,
  add column if not exists final_total        decimal(12,2),
  add column if not exists commission_snapshot jsonb;

-- ─────────────────────────────────────────────────────────────────────────────
-- 9. SEED DEFAULT COMMISSION
-- ─────────────────────────────────────────────────────────────────────────────
insert into laundry_commission_settings (
  commission_type, commission_value,
  customer_service_fee, customer_service_fee_type,
  applies_to_express_fee, applies_to_addon_services, applies_to_delivery_fee,
  is_default, is_active
) values (
  'percentage', 0.15,
  1.50, 'fixed',
  true, true, false,
  true, true
) on conflict do nothing;

-- ─────────────────────────────────────────────────────────────────────────────
-- 10. RLS
-- ─────────────────────────────────────────────────────────────────────────────
alter table laundry_ledger_entries        enable row level security;
alter table laundry_wallet_reservations   enable row level security;
alter table laundry_commission_settings   enable row level security;
alter table laundry_payment_splits        enable row level security;
alter table laundry_driver_jobs           enable row level security;

-- ledger: own entries or admin
create policy "laundry_ledger_user" on laundry_ledger_entries
  for select using (user_id = auth.uid() or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- reservations: customer or admin
create policy "laundry_res_select" on laundry_wallet_reservations
  for select using (customer_id = auth.uid() or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- commission settings: read for providers, write for admin
create policy "laundry_comm_read" on laundry_commission_settings
  for select using (true);
create policy "laundry_comm_write" on laundry_commission_settings
  for all using (exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- payment splits: customer sees own, provider sees own, admin sees all
create policy "laundry_splits_select" on laundry_payment_splits
  for select using (
    customer_id = auth.uid() or
    exists (select 1 from laundry_providers where id = provider_id and user_id = auth.uid()) or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- driver jobs: driver sees assigned, customer sees own booking's jobs, admin sees all
create policy "laundry_jobs_select" on laundry_driver_jobs
  for select using (
    driver_id = auth.uid() or
    exists (select 1 from laundry_bookings b where b.id = booking_id and b.customer_id = auth.uid()) or
    exists (select 1 from laundry_bookings b
      join laundry_providers p on p.id = b.provider_id
      where b.id = booking_id and p.user_id = auth.uid()) or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));
create policy "laundry_jobs_update_driver" on laundry_driver_jobs
  for update using (driver_id = auth.uid() or
    exists (select 1 from public.users where id = auth.uid() and role = 'admin'));

-- ─────────────────────────────────────────────────────────────────────────────
-- 11. HELPER: get active commission for a provider
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function get_laundry_commission(p_provider_id uuid)
returns table (
  commission_type         text,
  commission_value        decimal,
  customer_service_fee    decimal,
  customer_service_fee_type text,
  applies_to_delivery_fee boolean
) language sql stable security definer as $$
  select commission_type, commission_value,
         customer_service_fee, customer_service_fee_type,
         applies_to_delivery_fee
  from laundry_commission_settings
  where is_active = true
    and (provider_id = p_provider_id or (provider_id is null and is_default = true))
  order by (provider_id is not null) desc   -- provider-specific wins
  limit 1;
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 12. RPC: reserve_laundry_payment
--     Called at booking creation. Reserves laundry service + pickup fee + svc fee.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function reserve_laundry_payment(
  p_booking_id        uuid,
  p_laundry_amount    decimal,
  p_pickup_fee        decimal default 0,
  p_service_fee       decimal default 0
) returns jsonb language plpgsql security definer as $$
declare
  v_customer_id   uuid;
  v_wallet_id     uuid;
  v_balance       decimal;
  v_reserved      decimal;
  v_total         decimal;
  v_svc_fee       decimal;
begin
  -- Look up booking
  select customer_id into v_customer_id
  from laundry_bookings where id = p_booking_id;
  if not found then raise exception 'Booking not found'; end if;

  -- Auth check: caller must be the customer
  if auth.uid() != v_customer_id then
    raise exception 'Unauthorized';
  end if;

  -- Already reserved?
  if exists (select 1 from laundry_wallet_reservations
             where booking_id = p_booking_id and status = 'reserved') then
    raise exception 'Payment already reserved for this booking';
  end if;

  -- Get wallet (auto-create if missing)
  select user_id, balance, coalesce(reserved_balance,0)
  into v_wallet_id, v_balance, v_reserved
  from wallets where user_id = v_customer_id
  for update;

  if not found then
    insert into wallets (user_id, balance, reserved_balance)
    values (v_customer_id, 0, 0)
    returning user_id, balance, coalesce(reserved_balance,0) into v_wallet_id, v_balance, v_reserved;
  end if;

  -- Resolve service fee from commission settings if not provided
  if p_service_fee = 0 then
    select coalesce(customer_service_fee, 0) into v_svc_fee
    from get_laundry_commission(
      (select provider_id from laundry_bookings where id = p_booking_id)
    );
  else
    v_svc_fee := p_service_fee;
  end if;

  v_total := p_laundry_amount + p_pickup_fee + v_svc_fee;

  -- Check sufficient available balance
  if (v_balance - v_reserved) < v_total then
    return jsonb_build_object(
      'success',            false,
      'error',              'insufficient_balance',
      'required',           v_total,
      'available',          v_balance - v_reserved
    );
  end if;

  -- Reserve the funds
  update wallets
  set reserved_balance = reserved_balance + v_total
  where user_id = v_wallet_id;

  -- Create component reservations
  insert into laundry_wallet_reservations
    (booking_id, customer_id, component, reserved_amount, status)
  values
    (p_booking_id, v_customer_id, 'laundry_service',   p_laundry_amount, 'reserved'),
    (p_booking_id, v_customer_id, 'pickup_delivery',   p_pickup_fee,     'reserved'),
    (p_booking_id, v_customer_id, 'platform_service_fee', v_svc_fee,     'reserved')
  on conflict (booking_id, component) do update
    set reserved_amount = excluded.reserved_amount, status = 'reserved';

  -- Ledger entry
  insert into laundry_ledger_entries
    (wallet_id, user_id, booking_id, entry_type, amount,
     balance_before, balance_after, reserved_before, reserved_after, note)
  values (
    v_wallet_id, v_customer_id, p_booking_id, 'reserve', v_total,
    v_balance, v_balance,
    v_reserved, v_reserved + v_total,
    'Laundry booking reservation — service+pickup+fee'
  );

  -- Update booking
  update laundry_bookings
  set payment_status    = 'reserved',
      reserved_amount   = v_total,
      customer_service_fee = v_svc_fee,
      pickup_fee        = p_pickup_fee
  where id = p_booking_id;

  return jsonb_build_object(
    'success',         true,
    'reserved_amount', v_total,
    'service_fee',     v_svc_fee
  );
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 13. RPC: adjust_laundry_reservation
--     Called when provider records actual weight / final laundry price.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function adjust_laundry_reservation(
  p_booking_id      uuid,
  p_new_laundry_amt decimal
) returns jsonb language plpgsql security definer as $$
declare
  v_customer_id   uuid;
  v_wallet_id     uuid;
  v_balance       decimal;
  v_reserved      decimal;
  v_old_laundry   decimal;
  v_diff          decimal;
begin
  select b.customer_id, w.id, w.balance, coalesce(w.reserved_balance,0),
         coalesce(r.reserved_amount, 0)
  into v_customer_id, v_wallet_id, v_balance, v_reserved, v_old_laundry
  from laundry_bookings b
  join wallets w on w.user_id = b.customer_id
  left join laundry_wallet_reservations r
    on r.booking_id = b.id and r.component = 'laundry_service'
  where b.id = p_booking_id
  for update of w;

  if not found then raise exception 'Booking or wallet not found'; end if;

  v_diff := p_new_laundry_amt - v_old_laundry;

  if v_diff > 0 then
    -- Customer needs to pay more
    if (v_balance - v_reserved) < v_diff then
      return jsonb_build_object(
        'success',   false,
        'error',     'insufficient_balance',
        'extra_needed', v_diff,
        'available', v_balance - v_reserved
      );
    end if;
    update wallets set reserved_balance = reserved_balance + v_diff where user_id = v_wallet_id;
    -- Ledger
    insert into laundry_ledger_entries
      (wallet_id, user_id, booking_id, entry_type, amount,
       balance_before, balance_after, reserved_before, reserved_after, note)
    values (v_wallet_id, v_customer_id, p_booking_id, 'top_up_reserve', v_diff,
            v_balance, v_balance, v_reserved, v_reserved + v_diff,
            'Price adjustment — additional laundry reserve');
  elsif v_diff < 0 then
    -- Release the difference
    update wallets set reserved_balance = reserved_balance + v_diff where user_id = v_wallet_id;
    insert into laundry_ledger_entries
      (wallet_id, user_id, booking_id, entry_type, amount,
       balance_before, balance_after, reserved_before, reserved_after, note)
    values (v_wallet_id, v_customer_id, p_booking_id, 'release', -v_diff,
            v_balance, v_balance, v_reserved, v_reserved + v_diff,
            'Price adjustment — partial release');
  end if;

  -- Update component reservation
  update laundry_wallet_reservations
  set reserved_amount = p_new_laundry_amt, updated_at = now()
  where booking_id = p_booking_id and component = 'laundry_service';

  -- Update booking actual total
  update laundry_bookings set actual_total = p_new_laundry_amt where id = p_booking_id;

  return jsonb_build_object('success', true, 'new_laundry_amount', p_new_laundry_amt, 'diff', v_diff);
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 14. RPC: reserve_laundry_return_fee
--     Called when provider marks booking ready_for_delivery.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function reserve_laundry_return_fee(
  p_booking_id  uuid,
  p_return_fee  decimal
) returns jsonb language plpgsql security definer as $$
declare
  v_customer_id uuid;
  v_wallet_id   uuid;
  v_balance     decimal;
  v_reserved    decimal;
begin
  select b.customer_id, w.id, w.balance, coalesce(w.reserved_balance,0)
  into v_customer_id, v_wallet_id, v_balance, v_reserved
  from laundry_bookings b
  join wallets w on w.user_id = b.customer_id
  where b.id = p_booking_id
  for update of w;

  if not found then raise exception 'Booking not found'; end if;

  -- Already reserved?
  if exists (select 1 from laundry_wallet_reservations
             where booking_id = p_booking_id
               and component = 'return_delivery' and status = 'reserved') then
    return jsonb_build_object('success', true, 'already_reserved', true);
  end if;

  if (v_balance - v_reserved) < p_return_fee then
    -- Mark booking as requiring top-up
    update laundry_bookings set status = 'return_payment_required'
    where id = p_booking_id;
    return jsonb_build_object(
      'success',   false,
      'error',     'insufficient_balance',
      'required',  p_return_fee,
      'available', v_balance - v_reserved
    );
  end if;

  update wallets set reserved_balance = reserved_balance + p_return_fee where user_id = v_wallet_id;

  insert into laundry_wallet_reservations
    (booking_id, customer_id, component, reserved_amount, status)
  values (p_booking_id, v_customer_id, 'return_delivery', p_return_fee, 'reserved')
  on conflict (booking_id, component) do update
    set reserved_amount = excluded.reserved_amount, status = 'reserved';

  insert into laundry_ledger_entries
    (wallet_id, user_id, booking_id, entry_type, amount,
     balance_before, balance_after, reserved_before, reserved_after, note)
  values (v_wallet_id, v_customer_id, p_booking_id, 'reserve', p_return_fee,
          v_balance, v_balance, v_reserved, v_reserved + p_return_fee,
          'Return delivery fee reservation');

  update laundry_bookings
  set return_delivery_fee = p_return_fee, status = 'return_driver_searching'
  where id = p_booking_id;

  return jsonb_build_object('success', true, 'reserved', p_return_fee);
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 15. RPC: settle_laundry_booking
--     Called when booking status moves to 'completed'. Idempotent.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function settle_laundry_booking(p_booking_id uuid)
returns jsonb language plpgsql security definer as $$
declare
  v_booking         laundry_bookings%rowtype;
  v_wallet_id       uuid;
  v_reserved        decimal;
  v_comm            record;
  v_final_laundry   decimal;
  v_total_reserved  decimal;
  v_commissionable  decimal;
  v_commission_amt  decimal;
  v_provider_net    decimal;
  v_pickup_payout   decimal;
  v_return_payout   decimal;
  v_svc_fee         decimal;
  v_platform_total  decimal;
  v_pickup_driver   uuid;
  v_return_driver   uuid;
begin
  -- Prevent duplicate settlement
  if exists (select 1 from laundry_payment_splits
             where booking_id = p_booking_id and status = 'settled') then
    return jsonb_build_object('success', true, 'already_settled', true);
  end if;

  select * into v_booking from laundry_bookings where id = p_booking_id;
  if not found then raise exception 'Booking not found'; end if;

  select user_id, coalesce(reserved_balance,0)
  into v_wallet_id, v_reserved
  from wallets where user_id = v_booking.customer_id
  for update;

  -- Get driver job payouts
  select driver_id, driver_payout into v_pickup_driver, v_pickup_payout
  from laundry_driver_jobs
  where booking_id = p_booking_id and job_type = 'pickup' and status = 'completed';

  select driver_id, driver_payout into v_return_driver, v_return_payout
  from laundry_driver_jobs
  where booking_id = p_booking_id and job_type = 'return_delivery' and status = 'completed';

  v_pickup_payout := coalesce(v_pickup_payout, 0);
  v_return_payout := coalesce(v_return_payout, 0);

  -- Final amounts
  v_final_laundry  := coalesce(v_booking.actual_total, v_booking.estimated_total, 0);
  v_svc_fee        := coalesce(v_booking.customer_service_fee, 0);

  -- Get commission
  select * into v_comm from get_laundry_commission(v_booking.provider_id);
  v_commissionable := v_final_laundry;   -- service amounts only
  if v_comm.commission_type = 'percentage' then
    v_commission_amt := round(v_commissionable * v_comm.commission_value, 2);
  else
    v_commission_amt := v_comm.commission_value;
  end if;
  v_provider_net   := v_commissionable - v_commission_amt;
  v_platform_total := v_commission_amt + v_svc_fee;

  -- Total reserved to release
  v_total_reserved := coalesce(
    (select sum(reserved_amount) from laundry_wallet_reservations
     where booking_id = p_booking_id and status = 'reserved'), 0);

  -- Release all reserved funds (the money was already deducted from balance when reserved)
  update wallets
  set reserved_balance = greatest(0, reserved_balance - v_total_reserved)
  where user_id = v_wallet_id;

  -- Mark all reservations as captured
  update laundry_wallet_reservations
  set status = 'captured', updated_at = now()
  where booking_id = p_booking_id and status = 'reserved';

  -- Ledger: capture
  insert into laundry_ledger_entries
    (wallet_id, user_id, booking_id, entry_type, amount,
     balance_before, balance_after, reserved_before, reserved_after, note)
  values (v_wallet_id, v_booking.customer_id, p_booking_id, 'capture', v_total_reserved,
          (select balance from wallets where user_id = v_wallet_id),
          (select balance from wallets where user_id = v_wallet_id) - v_total_reserved,
          v_reserved, v_reserved - v_total_reserved,
          'Final payment capture on booking completion');

  -- Deduct from wallet balance (the true settlement)
  update wallets set balance = balance - v_total_reserved where user_id = v_wallet_id;

  -- Create immutable payment split
  insert into laundry_payment_splits (
    booking_id, customer_id, provider_id, pickup_driver_id, return_driver_id,
    final_laundry_amount, pickup_delivery_fee, return_delivery_fee, customer_service_fee,
    final_total, commissionable_amount, commission_rate, commission_type,
    platform_commission, provider_gross_amount, provider_net_earning,
    pickup_driver_earning, return_driver_earning, platform_total_earning,
    status, settled_at
  ) values (
    p_booking_id, v_booking.customer_id, v_booking.provider_id,
    v_pickup_driver, v_return_driver,
    v_final_laundry, coalesce(v_booking.pickup_fee,0),
    coalesce(v_booking.return_delivery_fee,0), v_svc_fee,
    v_total_reserved,
    v_commissionable, v_comm.commission_value, v_comm.commission_type,
    v_commission_amt,
    v_final_laundry, v_provider_net,
    v_pickup_payout, v_return_payout, v_platform_total,
    'settled', now()
  ) on conflict (booking_id) do update
    set status = 'settled', settled_at = now();

  -- Record commission snapshot on booking
  update laundry_bookings
  set commission_snapshot = jsonb_build_object(
    'rate', v_comm.commission_value, 'type', v_comm.commission_type,
    'commission_amount', v_commission_amt, 'provider_net', v_provider_net
  ),
  final_total = v_total_reserved,
  payment_status = 'settled'
  where id = p_booking_id;

  return jsonb_build_object(
    'success',           true,
    'final_total',       v_total_reserved,
    'provider_net',      v_provider_net,
    'commission',        v_commission_amt,
    'pickup_driver_pay', v_pickup_payout,
    'return_driver_pay', v_return_payout,
    'platform_total',    v_platform_total
  );
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 16. RPC: release_laundry_reservation
--     Called on cancellation.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function release_laundry_reservation(
  p_booking_id       uuid,
  p_reason           text default 'cancelled',
  p_cancellation_fee decimal default 0
) returns jsonb language plpgsql security definer as $$
declare
  v_customer_id  uuid;
  v_wallet_id    uuid;
  v_balance      decimal;
  v_reserved     decimal;
  v_total_res    decimal;
  v_release_amt  decimal;
begin
  select b.customer_id, w.id, w.balance, coalesce(w.reserved_balance,0)
  into v_customer_id, v_wallet_id, v_balance, v_reserved
  from laundry_bookings b
  join wallets w on w.user_id = b.customer_id
  where b.id = p_booking_id for update of w;

  if not found then raise exception 'Booking not found'; end if;

  select coalesce(sum(reserved_amount), 0) into v_total_res
  from laundry_wallet_reservations
  where booking_id = p_booking_id and status = 'reserved';

  v_release_amt := greatest(0, v_total_res - p_cancellation_fee);

  -- Release back to available balance
  update wallets
  set reserved_balance = greatest(0, reserved_balance - v_total_res),
      balance          = balance + v_release_amt
  where user_id = v_wallet_id;

  update laundry_wallet_reservations
  set status = 'released', updated_at = now()
  where booking_id = p_booking_id and status = 'reserved';

  insert into laundry_ledger_entries
    (wallet_id, user_id, booking_id, entry_type, amount,
     balance_before, balance_after, reserved_before, reserved_after, note)
  values (v_wallet_id, v_customer_id, p_booking_id, 'release', v_release_amt,
          v_balance, v_balance + v_release_amt, v_reserved, v_reserved - v_total_res,
          'Cancellation release — ' || p_reason);

  if p_cancellation_fee > 0 then
    insert into laundry_ledger_entries
      (wallet_id, user_id, booking_id, entry_type, amount,
       balance_before, balance_after, reserved_before, reserved_after, note)
    values (v_wallet_id, v_customer_id, p_booking_id, 'cancellation_fee', p_cancellation_fee,
            v_balance + v_release_amt, v_balance + v_release_amt,
            v_reserved - v_total_res, v_reserved - v_total_res,
            'Cancellation fee');
  end if;

  return jsonb_build_object(
    'success',          true,
    'released',         v_release_amt,
    'cancellation_fee', p_cancellation_fee
  );
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 17. RPC: create_laundry_driver_job
--     Creates a pickup or return delivery job and broadcasts to drivers.
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function create_laundry_driver_job(
  p_booking_id      uuid,
  p_job_type        text,      -- 'pickup' | 'return_delivery'
  p_pickup_address  text,
  p_pickup_lat      double precision,
  p_pickup_lng      double precision,
  p_dropoff_address text,
  p_dropoff_lat     double precision,
  p_dropoff_lng     double precision,
  p_delivery_fee    decimal default 0,
  p_driver_payout   decimal default 0
) returns uuid language plpgsql security definer as $$
declare
  v_job_id uuid;
  v_new_status text;
begin
  -- Prevent duplicate job per leg
  if exists (select 1 from laundry_driver_jobs
             where booking_id = p_booking_id and job_type = p_job_type
               and status not in ('cancelled')) then
    raise exception 'Job of type % already exists for this booking', p_job_type;
  end if;

  insert into laundry_driver_jobs (
    booking_id, job_type,
    pickup_address, pickup_lat, pickup_lng,
    dropoff_address, dropoff_lat, dropoff_lng,
    delivery_fee, driver_payout, status, broadcast_at
  ) values (
    p_booking_id, p_job_type,
    p_pickup_address, p_pickup_lat, p_pickup_lng,
    p_dropoff_address, p_dropoff_lat, p_dropoff_lng,
    p_delivery_fee, p_driver_payout, 'searching', now()
  ) returning id into v_job_id;

  -- Update booking status
  v_new_status := case p_job_type
    when 'pickup'          then 'pickup_driver_searching'
    when 'return_delivery' then 'return_driver_searching'
  end;
  update laundry_bookings set status = v_new_status::laundry_booking_status
  where id = p_booking_id;

  -- Notify nearby drivers (insert into notifications for drivers with active status)
  insert into notifications (user_id, title, body, type, data)
  select u.id,
    case p_job_type
      when 'pickup'          then 'New Laundry Pickup Job'
      when 'return_delivery' then 'New Laundry Return Delivery'
    end,
    case p_job_type
      when 'pickup'          then 'Pickup laundry from customer and deliver to laundromat. Fee: $' || p_driver_payout
      when 'return_delivery' then 'Collect clean laundry from provider and deliver to customer. Fee: $' || p_driver_payout
    end,
    'laundry_driver_job',
    jsonb_build_object(
      'job_id',     v_job_id,
      'job_type',   p_job_type,
      'booking_id', p_booking_id,
      'payout',     p_driver_payout
    )
  from public.users u
  join drivers d on d.user_id = u.id
  where u.role = 'driver' and d.is_available = true;

  return v_job_id;
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 18. RPC: accept_laundry_driver_job
--     First eligible driver to call this wins the job (race-condition safe).
-- ─────────────────────────────────────────────────────────────────────────────
create or replace function accept_laundry_driver_job(p_job_id uuid)
returns jsonb language plpgsql security definer as $$
declare
  v_driver_id  uuid;
  v_booking_id uuid;
  v_job_type   text;
  v_new_status text;
begin
  v_driver_id := auth.uid();
  if v_driver_id is null then raise exception 'Not authenticated'; end if;

  -- Atomic claim — only succeeds if still in 'searching' state
  update laundry_driver_jobs
  set driver_id = v_driver_id, status = 'assigned', accepted_at = now()
  where id = p_job_id and status = 'searching' and driver_id is null
  returning booking_id, job_type into v_booking_id, v_job_type;

  if not found then
    return jsonb_build_object('success', false, 'error', 'job_already_taken');
  end if;

  v_new_status := case v_job_type
    when 'pickup'          then 'pickup_driver_assigned'
    when 'return_delivery' then 'return_driver_assigned'
  end;
  update laundry_bookings set status = v_new_status::laundry_booking_status
  where id = v_booking_id;

  -- Notify customer
  insert into notifications (user_id, title, body, type, data)
  select b.customer_id,
    case v_job_type when 'pickup' then 'Pickup Driver Assigned'
                    else 'Return Driver Assigned' end,
    'A driver has accepted your laundry ' || v_job_type || ' job.',
    'laundry_status',
    jsonb_build_object('booking_id', v_booking_id, 'job_id', p_job_id)
  from laundry_bookings b where b.id = v_booking_id;

  return jsonb_build_object('success', true, 'job_id', p_job_id, 'booking_id', v_booking_id);
end; $$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 19. ADMIN ANALYTICS VIEW
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view laundry_admin_analytics as
select
  count(*)                                          as total_bookings,
  count(*) filter (where b.status = 'completed')   as completed_bookings,
  count(*) filter (where b.status = 'cancelled')   as cancelled_bookings,
  count(*) filter (where b.status = 'disputed')    as disputed_bookings,
  coalesce(sum(s.final_total), 0)                  as gross_sales,
  coalesce(sum(s.platform_commission), 0)          as total_commission,
  coalesce(sum(s.customer_service_fee), 0)         as total_service_fees,
  coalesce(sum(s.platform_total_earning), 0)       as total_platform_revenue,
  coalesce(sum(s.provider_net_earning), 0)         as total_provider_payouts,
  coalesce(sum(s.pickup_driver_earning
             + s.return_driver_earning), 0)        as total_driver_payouts,
  coalesce(avg(s.commission_rate) filter
           (where s.status = 'settled'), 0)        as avg_commission_rate
from laundry_bookings b
left join laundry_payment_splits s on s.booking_id = b.id;

-- ─────────────────────────────────────────────────────────────────────────────
-- 20. PROVIDER EARNINGS VIEW
-- ─────────────────────────────────────────────────────────────────────────────
create or replace view laundry_provider_earnings as
select
  s.provider_id,
  p.business_name,
  count(*)                                                  as total_orders,
  coalesce(sum(s.final_laundry_amount), 0)                  as gross_revenue,
  coalesce(sum(s.platform_commission), 0)                   as total_commission_deducted,
  coalesce(sum(s.provider_net_earning), 0)                  as net_earnings,
  coalesce(sum(s.provider_net_earning)
    filter (where ps.status = 'pending'), 0)                as pending_payout,
  coalesce(avg(s.commission_rate), 0.15)                    as effective_commission_rate
from laundry_payment_splits s
join laundry_providers p on p.id = s.provider_id
left join laundry_provider_payouts ps on ps.provider_id = s.provider_id
where s.status = 'settled'
group by s.provider_id, p.business_name;

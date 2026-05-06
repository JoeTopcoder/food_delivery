-- ====================================================================
-- Apology Coupon Brain
-- --------------------------------------------------------------------
-- When a customer has a poor experience (low review, restaurant/driver
-- cancellation), automatically issue an "I'm sorry" coupon with a small
-- discount (5–10%). Each customer can only have ONE outstanding apology
-- coupon at a time — once they redeem it, no more get issued unless
-- they have another bad experience after that redemption.
-- ====================================================================

-- 1. Tracks every apology coupon we issue and the event that triggered it.
create table if not exists public.apology_coupon_log (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  coupon_id uuid references public.user_coupons(id) on delete set null,
  trigger_type text not null check (trigger_type in ('low_review','cancellation','manual','complaint')),
  trigger_ref uuid,
  rating numeric,
  notes text,
  created_at timestamptz not null default now()
);
create index if not exists idx_apology_log_user on public.apology_coupon_log(user_id, created_at desc);

-- 2. Issue an apology coupon if the customer doesn't already have one
--    pending or one issued AFTER their last redemption.
--    Discount % escalates a tiny bit with severity but is always low (5–10).
create or replace function public.issue_apology_coupon(
  p_user_id uuid,
  p_trigger_type text,
  p_trigger_ref uuid default null,
  p_rating numeric default null,
  p_notes text default null
) returns jsonb
language plpgsql
security definer
as $$
declare
  v_last_apology_redeem timestamptz;
  v_pending_apology record;
  v_recent_issued record;
  v_discount int;
  v_min_order numeric := 0;
  v_code text;
  v_expires timestamptz := now() + interval '14 days';
  v_coupon_id uuid;
  v_reason text;
begin
  if p_user_id is null then
    return jsonb_build_object('issued', false, 'skip_reason', 'no_user');
  end if;

  -- Pending unused apology coupon? Don't pile on.
  select uc.* into v_pending_apology
  from public.user_coupons uc
  join public.apology_coupon_log a on a.coupon_id = uc.id
  where uc.user_id = p_user_id
    and uc.is_used = false
    and uc.expires_at > now()
  order by uc.created_at desc
  limit 1;

  if v_pending_apology.id is not null then
    return jsonb_build_object(
      'issued', false,
      'skip_reason', 'already_pending',
      'existing_code', v_pending_apology.code
    );
  end if;

  -- Find when the customer last redeemed a previous apology (if any).
  select max(uc.created_at) into v_last_apology_redeem
  from public.user_coupons uc
  join public.apology_coupon_log a on a.coupon_id = uc.id
  where uc.user_id = p_user_id and uc.is_used = true;

  -- If we already issued an apology AFTER the last redemption (or ever, if
  -- never redeemed) and it's still in the cool-off window with no new bad
  -- service event, skip. The pending check above catches the active case;
  -- this catches redeemed-but-recent flooding.
  select * into v_recent_issued
  from public.apology_coupon_log
  where user_id = p_user_id
    and created_at > coalesce(v_last_apology_redeem, 'epoch'::timestamptz)
    and created_at > now() - interval '24 hours'
  order by created_at desc
  limit 1;

  if v_recent_issued.id is not null then
    return jsonb_build_object(
      'issued', false,
      'skip_reason', 'cooldown',
      'last_issued_at', v_recent_issued.created_at
    );
  end if;

  -- Decide a small discount based on severity.
  if p_trigger_type = 'cancellation' then
    v_discount := 10;
    v_reason := 'Sorry your order was cancelled — here''s 10% off your next one.';
  elsif p_trigger_type = 'low_review' and coalesce(p_rating, 5) <= 1 then
    v_discount := 10;
    v_reason := 'We''re sorry that didn''t live up to expectations. Enjoy 10% off your next order.';
  elsif p_trigger_type = 'complaint' then
    v_discount := 8;
    v_reason := 'Thanks for letting us know. Here''s 8% off to make it right.';
  else
    v_discount := 5;
    v_reason := 'We''re sorry the experience wasn''t great. Here''s 5% off your next meal.';
  end if;

  v_code := 'SORRY' || upper(substr(gen_random_uuid()::text, 1, 6));

  insert into public.user_coupons (user_id, code, discount_percent, min_order, reason, expires_at)
  values (p_user_id, v_code, v_discount, v_min_order, v_reason, v_expires)
  returning id into v_coupon_id;

  insert into public.promo_codes (
    code, description, discount_type, discount_value,
    min_order_amount, max_uses, usage_count, is_active, expires_at
  ) values (
    v_code, v_reason, 'percentage', v_discount,
    v_min_order, 1, 0, true, v_expires
  ) on conflict (code) do nothing;

  insert into public.apology_coupon_log (user_id, coupon_id, trigger_type, trigger_ref, rating, notes)
  values (p_user_id, v_coupon_id, p_trigger_type, p_trigger_ref, p_rating, p_notes);

  return jsonb_build_object(
    'issued', true,
    'code', v_code,
    'discount_percent', v_discount,
    'reason', v_reason,
    'expires_at', v_expires
  );
end;
$$;

-- 3. Trigger: on a low review (<= 2 stars), call the brain.
create or replace function public.trg_low_review_apology()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.rating is not null and new.rating <= 2 then
    perform public.issue_apology_coupon(
      new.user_id,
      'low_review',
      new.order_id,
      new.rating,
      left(coalesce(new.review_text, ''), 200)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_low_review_apology on public.reviews;
create trigger trg_low_review_apology
  after insert on public.reviews
  for each row
  execute function public.trg_low_review_apology();

-- 4. Trigger: on a customer-impacting cancellation, call the brain.
--    We treat any transition into 'cancelled' as a bad experience for the
--    customer, regardless of who cancelled — admins can clean up false
--    positives later. The 24h cooldown + 1-pending rule prevents abuse.
create or replace function public.trg_cancellation_apology()
returns trigger
language plpgsql
security definer
as $$
begin
  if new.status = 'cancelled'
     and (old.status is distinct from new.status)
     and new.user_id is not null then
    perform public.issue_apology_coupon(
      new.user_id,
      'cancellation',
      new.id,
      null,
      'Order cancelled'
    );
  end if;
  return new;
end;
$$;

drop trigger if exists trg_cancellation_apology on public.orders;
create trigger trg_cancellation_apology
  after update of status on public.orders
  for each row
  execute function public.trg_cancellation_apology();

-- 5. Allow service role + authenticated users to read their own log.
alter table public.apology_coupon_log enable row level security;

drop policy if exists apology_log_self_read on public.apology_coupon_log;
create policy apology_log_self_read on public.apology_coupon_log
  for select
  using (auth.uid() = user_id);

-- HotBite+ Membership — foundation (Phase 1): plans, memberships, business-
-- funded deals, vouchers, per-order discount records, config + feature flags,
-- RLS, and the trusted membership-status/eligibility RPCs. Everything money- or
-- eligibility-related is decided server-side; the client only displays it.
-- Reuses app_config for settings and is_admin() for admin gating.

-- ── 1. Membership plans (admin-priced) ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.membership_plans (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name          text NOT NULL,
  description   text,
  price         numeric NOT NULL CHECK (price >= 0),
  currency      text NOT NULL DEFAULT 'JMD',
  duration_days integer NOT NULL CHECK (duration_days > 0),
  is_active     boolean NOT NULL DEFAULT true,
  is_recommended boolean NOT NULL DEFAULT false,
  display_order integer NOT NULL DEFAULT 0,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.membership_plans (name, description, price, duration_days, display_order, is_recommended)
SELECT * FROM (VALUES
  ('7-Day Trial', 'Try HotBite+ for a week', 199::numeric, 7, 1, false),
  ('Monthly',     '30 days of member deals & benefits', 499::numeric, 30, 2, true),
  ('90-Day',      'Best value — 3 months of HotBite+', 1199::numeric, 90, 3, false)
) v(name, description, price, duration_days, display_order, is_recommended)
WHERE NOT EXISTS (SELECT 1 FROM public.membership_plans);

-- ── 2. Customer memberships (history preserved) ───────────────────────────
CREATE TABLE IF NOT EXISTS public.customer_memberships (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id            uuid NOT NULL,
  membership_plan_id uuid REFERENCES public.membership_plans(id),
  status             text NOT NULL DEFAULT 'pending'
                       CHECK (status IN ('active','expired','cancelled','pending','paused')),
  start_date         timestamptz,
  end_date           timestamptz,
  auto_renew         boolean NOT NULL DEFAULT false,
  price_paid         numeric,
  payment_reference  text,
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cust_mem_user ON public.customer_memberships(user_id, status);
CREATE INDEX IF NOT EXISTS idx_cust_mem_dates ON public.customer_memberships(start_date, end_date);

-- ── 3. Business-funded membership deals (with admin approval) ──────────────
CREATE TABLE IF NOT EXISTS public.membership_deals (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  business_id   uuid NOT NULL,          -- restaurants.id (food or grocery store)
  business_type text NOT NULL DEFAULT 'restaurant'
                  CHECK (business_type IN ('restaurant','supermarket')),
  title         text NOT NULL,
  description   text,
  image_url     text,
  discount_type text NOT NULL CHECK (discount_type IN
                  ('percentage','fixed_amount','special_price','free_delivery','free_item')),
  discount_value numeric NOT NULL DEFAULT 0,
  minimum_order_amount numeric NOT NULL DEFAULT 0,
  maximum_discount_amount numeric,
  start_date    timestamptz,
  end_date      timestamptz,
  usage_limit   integer,                -- null = unlimited
  usage_limit_per_customer integer DEFAULT 1,
  -- who absorbs the discount, for partner settlement/reporting
  funded_by     text NOT NULL DEFAULT 'business'
                  CHECK (funded_by IN ('business','hotbite','shared')),
  business_funded_pct numeric NOT NULL DEFAULT 100,
  status        text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','pending_approval','approved','rejected','expired','disabled')),
  is_active     boolean NOT NULL DEFAULT true,
  requires_membership boolean NOT NULL DEFAULT true,
  reviewed_by   uuid,
  reviewed_at   timestamptz,
  rejection_reason text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_mdeals_business ON public.membership_deals(business_id, status, is_active);
CREATE INDEX IF NOT EXISTS idx_mdeals_dates ON public.membership_deals(start_date, end_date);

-- ── 4. Member vouchers ────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.membership_vouchers (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL,
  membership_id uuid REFERENCES public.customer_memberships(id),
  voucher_type  text NOT NULL CHECK (voucher_type IN
                  ('fixed_amount','percentage','free_delivery')),
  value         numeric NOT NULL DEFAULT 0,
  minimum_order numeric NOT NULL DEFAULT 0,
  maximum_discount numeric,
  valid_from    timestamptz NOT NULL DEFAULT now(),
  valid_until   timestamptz,
  status        text NOT NULL DEFAULT 'available'
                  CHECK (status IN ('available','used','expired','cancelled')),
  order_id      uuid,                   -- set when redeemed
  source        text,                   -- 'monthly_reward' | 'birthday' | 'admin' | ...
  created_at    timestamptz NOT NULL DEFAULT now(),
  used_at       timestamptz
);
CREATE INDEX IF NOT EXISTS idx_mvouchers_user ON public.membership_vouchers(user_id, status);

-- ── 5. Per-order membership discount record (reporting/settlement) ─────────
CREATE TABLE IF NOT EXISTS public.order_membership_discounts (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id       uuid NOT NULL,
  membership_id  uuid,
  deal_id        uuid,
  voucher_id     uuid,
  business_id    uuid,
  discount_type  text,
  discount_amount numeric NOT NULL DEFAULT 0,
  business_funded_amount numeric NOT NULL DEFAULT 0,
  hotbite_funded_amount  numeric NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_omd_order ON public.order_membership_discounts(order_id);
CREATE INDEX IF NOT EXISTS idx_omd_business ON public.order_membership_discounts(business_id);

-- ── 6. Config + feature flags (admin-editable, no app release) ─────────────
INSERT INTO public.app_config (key, value) VALUES
  ('hotbite_plus_enabled', 'true'),
  ('membership_deals_enabled', 'true'),
  ('membership_delivery_benefits_enabled', 'false'),
  ('membership_priority_enabled', 'false'),
  ('membership_vouchers_enabled', 'true'),
  ('birthday_rewards_enabled', 'false'),
  ('membership_monthly_rewards_enabled', 'false'),
  ('membership_delivery_discount', '0'),
  ('membership_free_delivery_minimum', '0'),
  ('membership_priority_fee', '150'),
  ('allow_membership_with_promotion', 'false'),
  ('allow_membership_with_coupon', 'false'),
  ('allow_membership_with_voucher', 'false'),
  ('membership_expiry_reminder_days', '7,3,1')
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';

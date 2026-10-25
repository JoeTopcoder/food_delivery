-- ============================================================================
-- HotBite Host Rewards — Phase 2: DB + backend foundation.
--
-- Property hosts (Airbnb/guesthouse owners) earn a commission when a guest who
-- registered via the property's QR code has an order DELIVERED TO THAT SAME
-- registered property. Funded by HotBite (its own ledger line), never from
-- merchant proceeds. Admin-managed for v1 (no host login yet).
--
-- Reuses the platform's proven patterns: the Company-Sponsored Ordering model
-- (deliver-to-location + per-order credit + immutable snapshot) and the Member
-- Referral Rewards model (attribution + reward-on-delivery + ledger + caps).
--
-- EVERYTHING here is inert until app_config.host_rewards_enabled = 'true'
-- (seeded 'false'). Money is stored in integer minor units (cents). All
-- commission logic is server-side, idempotent and audited.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- 0. Master feature flag (read at app start, like other HotBite flags).
-- ---------------------------------------------------------------------------
INSERT INTO public.app_config (key, value, category)
VALUES ('host_rewards_enabled', 'false', 'general')
ON CONFLICT (key) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 1. Programme config (single row, id=1).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_rewards_config (
  id                    int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  default_commission_cents int NOT NULL DEFAULT 10000,   -- J$100
  commission_type       text NOT NULL DEFAULT 'fixed' CHECK (commission_type IN ('fixed','percent')),
  currency              text NOT NULL DEFAULT 'JMD',
  referral_days         int NOT NULL DEFAULT 30,         -- referral validity
  hold_period_days      int NOT NULL DEFAULT 7,          -- pending->payable hold
  updated_at            timestamptz NOT NULL DEFAULT now()
);
INSERT INTO public.host_rewards_config (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 2. Hosts.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.hosts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  full_name     text NOT NULL,
  email         text,
  phone         text,
  business_name text,
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','active','suspended','inactive')),
  payout_method_reference text,     -- opaque ref ONLY (never plaintext bank details)
  notes         text,
  created_by    uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 3. Host properties (each has its own unique referral code / QR).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_properties (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id       uuid NOT NULL REFERENCES public.hosts(id) ON DELETE CASCADE,
  property_name text NOT NULL,
  address       text NOT NULL,
  parish        text,
  area          text,
  latitude      double precision,
  longitude     double precision,
  delivery_instructions text,
  referral_code text NOT NULL UNIQUE,
  -- Optional per-property commission override (else the global default applies).
  commission_type       text CHECK (commission_type IN ('fixed','percent')),
  commission_value_cents int,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','suspended','inactive')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_host_properties_host ON public.host_properties(host_id);

-- ---------------------------------------------------------------------------
-- 4. Referrals (customer <-> property attribution).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_referrals (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id       uuid NOT NULL REFERENCES public.hosts(id) ON DELETE CASCADE,
  property_id   uuid NOT NULL REFERENCES public.host_properties(id) ON DELETE CASCADE,
  customer_id   uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  referral_code text NOT NULL,
  referred_at   timestamptz NOT NULL DEFAULT now(),
  expires_at    timestamptz NOT NULL,
  status        text NOT NULL DEFAULT 'active' CHECK (status IN ('active','expired','revoked')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
-- Attribution policy: at most ONE active referral per customer.
CREATE UNIQUE INDEX IF NOT EXISTS uq_host_referral_active_per_customer
  ON public.host_referrals(customer_id) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_host_referrals_property ON public.host_referrals(property_id);

-- ---------------------------------------------------------------------------
-- 5. Commissions (one per qualifying order).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_commissions (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id       uuid NOT NULL REFERENCES public.hosts(id),
  property_id   uuid NOT NULL REFERENCES public.host_properties(id),
  referral_id   uuid NOT NULL REFERENCES public.host_referrals(id),
  order_id      uuid NOT NULL UNIQUE,            -- idempotency: one commission per order
  amount_cents  int NOT NULL,
  currency      text NOT NULL DEFAULT 'JMD',
  status        text NOT NULL DEFAULT 'pending'
                 CHECK (status IN ('pending','approved','payable','paid','reversed','rejected')),
  order_total_cents int,
  property_snapshot jsonb,                       -- immutable record of what qualified
  eligibility_checked_at timestamptz NOT NULL DEFAULT now(),
  payable_at    timestamptz,
  payout_id     uuid,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_host_commissions_host ON public.host_commissions(host_id, status);

-- ---------------------------------------------------------------------------
-- 6. Payouts + ledger (append-only, idempotent).
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_payouts (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id       uuid NOT NULL REFERENCES public.hosts(id),
  amount_cents  int NOT NULL,
  currency      text NOT NULL DEFAULT 'JMD',
  status        text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','approved','paid','rejected')),
  payout_reference text,
  approved_by   uuid,
  paid_at       timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.host_commission_ledger (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  host_id       uuid NOT NULL REFERENCES public.hosts(id),
  commission_id uuid REFERENCES public.host_commissions(id),
  payout_id     uuid REFERENCES public.host_payouts(id),
  entry_type    text NOT NULL CHECK (entry_type IN ('accrual','reversal','payout')),
  amount_cents  int NOT NULL,                    -- signed: +accrual, -reversal, -payout
  currency      text NOT NULL DEFAULT 'JMD',
  idempotency_key text NOT NULL UNIQUE,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_host_ledger_host ON public.host_commission_ledger(host_id);

-- ---------------------------------------------------------------------------
-- 7. Audit log.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.host_audit_logs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    uuid,
  action      text NOT NULL,
  entity_type text,
  entity_id   uuid,
  metadata    jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- 8. Order linkage: which registered property an order was delivered to.
--    Set at checkout (Phase 4). Nullable + non-destructive.
-- ---------------------------------------------------------------------------
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS host_property_id uuid REFERENCES public.host_properties(id);

-- ---------------------------------------------------------------------------
-- 9. RLS — admin-only (v1 has no host login). Engine runs as definer/service.
-- ---------------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['host_rewards_config','hosts','host_properties','host_referrals',
      'host_commissions','host_payouts','host_commission_ledger','host_audit_logs']
  LOOP
    EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
    IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE schemaname='public' AND tablename=t AND policyname=t||'_admin_all') THEN
      EXECUTE format($p$CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (public.is_admin()) WITH CHECK (public.is_admin())$p$, t||'_admin_all', t);
    END IF;
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 10. Helpers.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.host_rewards_enabled()
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $$
  SELECT COALESCE((SELECT value='true' FROM app_config WHERE key='host_rewards_enabled'), false);
$$;

-- Unique referral code: HBHOST-<8 base32 chars>. Retries on the rare collision.
CREATE OR REPLACE FUNCTION public.host_generate_referral_code()
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE code text; i int := 0;
BEGIN
  LOOP
    code := 'HBHOST-' || upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
    EXIT WHEN NOT EXISTS (SELECT 1 FROM host_properties WHERE referral_code = code);
    i := i + 1; IF i > 10 THEN RAISE EXCEPTION 'could not generate unique referral code'; END IF;
  END LOOP;
  RETURN code;
END $$;

CREATE OR REPLACE FUNCTION public.host_audit(p_action text, p_entity text, p_id uuid, p_meta jsonb DEFAULT '{}'::jsonb)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path TO 'public' AS $$
  INSERT INTO host_audit_logs(actor_id, action, entity_type, entity_id, metadata)
  VALUES (auth.uid(), p_action, p_entity, p_id, p_meta);
$$;

-- ---------------------------------------------------------------------------
-- 11. Customer: claim a referral by QR code. Pinned to auth.uid().
--     New-customer-only attribution: refuses if the customer already has an
--     active referral. Returns the property so the app can offer it as a saved
--     delivery address.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.host_claim_referral(p_code text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_uid uuid := auth.uid(); v_prop host_properties; v_host hosts; v_days int; v_ref uuid;
BEGIN
  IF NOT host_rewards_enabled() THEN RETURN jsonb_build_object('ok',false,'error','disabled'); END IF;
  IF v_uid IS NULL THEN RETURN jsonb_build_object('ok',false,'error','unauthenticated'); END IF;

  SELECT * INTO v_prop FROM host_properties WHERE referral_code = p_code;
  IF v_prop.id IS NULL OR v_prop.status <> 'active' THEN
    RETURN jsonb_build_object('ok',false,'error','invalid_or_inactive_property');
  END IF;
  SELECT * INTO v_host FROM hosts WHERE id = v_prop.host_id;
  IF v_host.status <> 'active' THEN RETURN jsonb_build_object('ok',false,'error','inactive_host'); END IF;

  -- New-customer-only: don't overwrite an existing active referral.
  IF EXISTS (SELECT 1 FROM host_referrals WHERE customer_id = v_uid AND status='active') THEN
    RETURN jsonb_build_object('ok',false,'error','already_referred');
  END IF;

  SELECT referral_days INTO v_days FROM host_rewards_config WHERE id=1;
  INSERT INTO host_referrals(host_id, property_id, customer_id, referral_code, expires_at)
  VALUES (v_prop.host_id, v_prop.id, v_uid, p_code, now() + make_interval(days => v_days))
  RETURNING id INTO v_ref;

  PERFORM host_audit('referral_claimed','host_referral',v_ref, jsonb_build_object('customer',v_uid,'code',p_code));

  RETURN jsonb_build_object('ok',true,'referral_id',v_ref,
    'property', jsonb_build_object('id',v_prop.id,'name',v_prop.property_name,'address',v_prop.address,
      'parish',v_prop.parish,'area',v_prop.area,'latitude',v_prop.latitude,'longitude',v_prop.longitude,
      'instructions',v_prop.delivery_instructions));
END $$;

-- ---------------------------------------------------------------------------
-- 12. Commission engine (service/trigger only). Idempotent + audited.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.host_award_commission(p_order_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  o orders; ref host_referrals; prop host_properties; cfg host_rewards_config;
  v_amount int; v_total_cents int; v_cid uuid;
BEGIN
  IF NOT host_rewards_enabled() THEN RETURN; END IF;

  SELECT * INTO o FROM orders WHERE id = p_order_id;
  IF o.id IS NULL OR o.status <> 'delivered' THEN RETURN; END IF;
  IF o.host_property_id IS NULL THEN RETURN; END IF;             -- not delivered to a registered property
  IF EXISTS (SELECT 1 FROM host_commissions WHERE order_id = p_order_id) THEN RETURN; END IF; -- already awarded

  -- Payment settled: COD counts on delivery; card must be paid/captured.
  IF NOT (o.payment_method = 'cash'
          OR lower(coalesce(o.payment_status,'')) IN ('paid','completed','succeeded','captured','settled')) THEN
    RETURN;
  END IF;

  -- The customer's active, unexpired referral must point at the SAME property
  -- the order was delivered to.
  SELECT * INTO ref FROM host_referrals
   WHERE customer_id = o.user_id AND status='active' AND expires_at >= o.created_at
   ORDER BY referred_at DESC LIMIT 1;
  IF ref.id IS NULL OR ref.property_id <> o.host_property_id THEN RETURN; END IF;

  SELECT * INTO prop FROM host_properties WHERE id = ref.property_id;
  IF prop.status <> 'active' THEN RETURN; END IF;
  SELECT * INTO cfg FROM host_rewards_config WHERE id=1;

  v_total_cents := round(coalesce(o.total_amount, o.subtotal, 0) * 100)::int;
  -- Fixed by default; percent uses order total. Property override wins.
  IF coalesce(prop.commission_type, cfg.commission_type) = 'percent' THEN
    v_amount := round(v_total_cents * coalesce(prop.commission_value_cents, cfg.default_commission_cents) / 10000.0)::int;
  ELSE
    v_amount := coalesce(prop.commission_value_cents, cfg.default_commission_cents);
  END IF;
  IF v_amount <= 0 THEN RETURN; END IF;

  INSERT INTO host_commissions(host_id, property_id, referral_id, order_id, amount_cents, currency,
      status, order_total_cents, property_snapshot, payable_at)
  VALUES (ref.host_id, ref.property_id, ref.id, o.id, v_amount, cfg.currency, 'pending', v_total_cents,
      jsonb_build_object('property_name',prop.property_name,'address',prop.address,
        'referral_code',ref.referral_code,'delivered_to',o.host_property_id),
      now() + make_interval(days => cfg.hold_period_days))
  RETURNING id INTO v_cid;

  INSERT INTO host_commission_ledger(host_id, commission_id, entry_type, amount_cents, currency, idempotency_key)
  VALUES (ref.host_id, v_cid, 'accrual', v_amount, cfg.currency, 'accrual:'||o.id::text)
  ON CONFLICT (idempotency_key) DO NOTHING;

  PERFORM host_audit('commission_accrued','host_commission',v_cid,
    jsonb_build_object('order',o.id,'amount_cents',v_amount));
END $$;

-- Reverse a commission when its order is refunded/cancelled after award.
CREATE OR REPLACE FUNCTION public.host_reverse_commission(p_order_id uuid, p_reason text DEFAULT 'refund')
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE c host_commissions;
BEGIN
  SELECT * INTO c FROM host_commissions WHERE order_id = p_order_id;
  IF c.id IS NULL OR c.status = 'reversed' THEN RETURN; END IF;

  INSERT INTO host_commission_ledger(host_id, commission_id, entry_type, amount_cents, currency, idempotency_key)
  VALUES (c.host_id, c.id, 'reversal', -c.amount_cents, c.currency, 'reversal:'||p_order_id::text)
  ON CONFLICT (idempotency_key) DO NOTHING;

  UPDATE host_commissions SET status='reversed', updated_at=now() WHERE id=c.id;
  PERFORM host_audit('commission_reversed','host_commission',c.id, jsonb_build_object('order',p_order_id,'reason',p_reason));
END $$;

-- ---------------------------------------------------------------------------
-- 13. Order-lifecycle triggers (mirror auto_cashback_on_delivery).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_host_commission_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.status = 'delivered' AND coalesce(OLD.status,'') <> 'delivered' THEN
    PERFORM host_award_commission(NEW.id);
  ELSIF NEW.status = 'cancelled' AND coalesce(OLD.status,'') <> 'cancelled' THEN
    -- A rare post-delivery cancellation reverses any commission.
    PERFORM host_reverse_commission(NEW.id, 'cancelled');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_host_commission ON public.orders;
CREATE TRIGGER trg_host_commission AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.trg_host_commission_fn();

-- Refunds live in their own table; an APPROVED/PROCESSED refund reverses the
-- order's commission (pending/rejected refunds do not).
CREATE OR REPLACE FUNCTION public.trg_host_commission_refund_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.status IN ('approved','processed') THEN
    PERFORM host_reverse_commission(NEW.order_id, 'refund');
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_host_commission_refund ON public.refunds;
CREATE TRIGGER trg_host_commission_refund AFTER INSERT OR UPDATE OF status ON public.refunds
  FOR EACH ROW EXECUTE FUNCTION public.trg_host_commission_refund_fn();

-- ---------------------------------------------------------------------------
-- 14. Admin management RPCs (is_admin gated).
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.host_admin_create_host(
  p_full_name text, p_email text, p_phone text, p_business_name text DEFAULT NULL,
  p_status text DEFAULT 'active', p_notes text DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  INSERT INTO hosts(full_name,email,phone,business_name,status,notes,created_by)
  VALUES (p_full_name,p_email,p_phone,p_business_name,p_status,p_notes,auth.uid())
  RETURNING id INTO v_id;
  PERFORM host_audit('host_created','host',v_id, jsonb_build_object('name',p_full_name));
  RETURN v_id;
END $$;

CREATE OR REPLACE FUNCTION public.host_admin_create_property(
  p_host_id uuid, p_name text, p_address text, p_parish text DEFAULT NULL, p_area text DEFAULT NULL,
  p_lat double precision DEFAULT NULL, p_lng double precision DEFAULT NULL, p_instructions text DEFAULT NULL,
  p_commission_type text DEFAULT NULL, p_commission_value_cents int DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_id uuid; v_code text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  v_code := host_generate_referral_code();
  INSERT INTO host_properties(host_id,property_name,address,parish,area,latitude,longitude,
      delivery_instructions,referral_code,commission_type,commission_value_cents)
  VALUES (p_host_id,p_name,p_address,p_parish,p_area,p_lat,p_lng,p_instructions,v_code,p_commission_type,p_commission_value_cents)
  RETURNING id INTO v_id;
  PERFORM host_audit('property_created','host_property',v_id, jsonb_build_object('code',v_code));
  RETURN jsonb_build_object('id',v_id,'referral_code',v_code);
END $$;

-- Rotate a property's referral code (compromise); old code stops working.
CREATE OR REPLACE FUNCTION public.host_admin_rotate_code(p_property_id uuid)
RETURNS text LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_code text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  v_code := host_generate_referral_code();
  UPDATE host_properties SET referral_code=v_code, updated_at=now() WHERE id=p_property_id;
  PERFORM host_audit('code_rotated','host_property',p_property_id, jsonb_build_object('code',v_code));
  RETURN v_code;
END $$;

-- Payout workflow: create (from payable commissions) -> approve -> mark paid.
CREATE OR REPLACE FUNCTION public.host_admin_approve_payout(p_host_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE v_total int; v_payout uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  -- payable = pending commissions past their hold, not reversed/paid.
  UPDATE host_commissions SET status='payable', updated_at=now()
   WHERE host_id=p_host_id AND status='pending' AND payable_at <= now();
  SELECT COALESCE(SUM(amount_cents),0) INTO v_total FROM host_commissions
   WHERE host_id=p_host_id AND status='payable';
  IF v_total <= 0 THEN RETURN jsonb_build_object('ok',false,'error','nothing_payable'); END IF;

  INSERT INTO host_payouts(host_id,amount_cents,status,approved_by)
  VALUES (p_host_id,v_total,'approved',auth.uid()) RETURNING id INTO v_payout;
  UPDATE host_commissions SET status='paid', payout_id=v_payout, updated_at=now()
   WHERE host_id=p_host_id AND status='payable';
  INSERT INTO host_commission_ledger(host_id,payout_id,entry_type,amount_cents,idempotency_key)
  VALUES (p_host_id,v_payout,'payout',-v_total,'payout:'||v_payout::text);
  PERFORM host_audit('payout_approved','host_payout',v_payout, jsonb_build_object('amount_cents',v_total));
  RETURN jsonb_build_object('ok',true,'payout_id',v_payout,'amount_cents',v_total);
END $$;

CREATE OR REPLACE FUNCTION public.host_admin_mark_payout_paid(p_payout_id uuid, p_reference text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'forbidden'; END IF;
  UPDATE host_payouts SET status='paid', payout_reference=p_reference, paid_at=now(), updated_at=now()
   WHERE id=p_payout_id;
  PERFORM host_audit('payout_marked_paid','host_payout',p_payout_id, jsonb_build_object('ref',p_reference));
END $$;

-- ---------------------------------------------------------------------------
-- 15. Grants — engine/admin fns locked to service_role; claim to authenticated.
-- ---------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.host_award_commission(uuid)          FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.host_reverse_commission(uuid, text)  FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.host_generate_referral_code()        FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.host_audit(text, text, uuid, jsonb)  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.host_claim_referral(text)         TO authenticated;
GRANT EXECUTE ON FUNCTION public.host_rewards_enabled()            TO authenticated;
-- Supabase default-grants EXECUTE to anon; remove it so these are authenticated-only.
REVOKE ALL ON FUNCTION public.host_claim_referral(text)            FROM public, anon;
REVOKE ALL ON FUNCTION public.host_rewards_enabled()               FROM public, anon;
-- Admin RPCs: revoke anon, keep authenticated (guarded by is_admin() inside).
REVOKE ALL ON FUNCTION public.host_admin_create_host(text,text,text,text,text,text) FROM public, anon;
REVOKE ALL ON FUNCTION public.host_admin_create_property(uuid,text,text,text,text,double precision,double precision,text,text,int) FROM public, anon;
REVOKE ALL ON FUNCTION public.host_admin_rotate_code(uuid)         FROM public, anon;
REVOKE ALL ON FUNCTION public.host_admin_approve_payout(uuid)      FROM public, anon;
REVOKE ALL ON FUNCTION public.host_admin_mark_payout_paid(uuid, text) FROM public, anon;

NOTIFY pgrst, 'reload schema';

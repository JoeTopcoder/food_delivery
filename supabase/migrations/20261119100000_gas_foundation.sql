-- ============================================================================
-- HotBite Cooking Gas Delivery — Foundation (schema + security + flags)
--
-- Adds an LPG cooking-gas vertical ALONGSIDE food/grocery, WITHOUT touching the
-- existing `orders`, `place-order`, driver dispatch, or financial math. Gas has
-- its own order tables, its own state machine, supplier-managed delivery, and a
-- SEPARATE fulfilment path — cooking gas is hazardous and must never auto-enter
-- the food rider pool.
--
-- Money is stored in integer minor units (JMD cents), matching ad_* / host_*.
-- Dates are UTC; display converts to America/Jamaica. Cylinder DEPOSITS are a
-- refundable LIABILITY, never platform revenue.
--
-- This migration is FOUNDATION ONLY: tables, RLS, the supplier-permission
-- helper, settings + feature flag (OFF). Lifecycle RPCs, the place-gas-order
-- edge function, financial rollup and all Flutter UI are later steps.
--
-- SAFETY / COMPLIANCE: driver/operator eligibility fields here are CONFIGURABLE
-- placeholders. They assert no legal compliance. Live LPG ordering stays gated
-- behind gas_enabled='false' until HotBite verifies Jamaican LPG transport,
-- insurance and emergency requirements and approves real suppliers.
-- ============================================================================

-- NOTE: the can_manage_gas_supplier() helper is defined AFTER the tables it
-- references (gas_suppliers, gas_supplier_staff), since a SQL function body is
-- validated against existing relations at CREATE time. See below, before RLS.

-- ── Settings (single row) + feature flag ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gas_settings (
  id                     int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  enabled                boolean NOT NULL DEFAULT false,  -- master kill switch
  service_fee_cents      bigint  NOT NULL DEFAULT 0 CHECK (service_fee_cents >= 0),
  default_delivery_cents bigint  NOT NULL DEFAULT 0 CHECK (default_delivery_cents >= 0),
  max_doc_bytes          bigint  NOT NULL DEFAULT 10485760, -- 10 MB supplier docs
  require_operator_checks boolean NOT NULL DEFAULT true,  -- enforce delivery-operator eligibility
  allow_new_cylinders    boolean NOT NULL DEFAULT true,
  updated_at             timestamptz NOT NULL DEFAULT now(),
  updated_by             uuid
);
INSERT INTO public.gas_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.gas_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY gas_settings_read ON public.gas_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY gas_settings_admin_write ON public.gas_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- mirror the flag into app_config so it follows the existing feature-flag pattern
INSERT INTO public.app_config (key, value) VALUES ('gas_enabled', 'false')
ON CONFLICT (key) DO NOTHING;

-- ── Suppliers ───────────────────────────────────────────────────────────────
-- A gas supplier is the existing owner-role user wearing a supplier hat. Not
-- live until verification_status='approved' AND is_active AND delivery operational.
CREATE TABLE IF NOT EXISTS public.gas_suppliers (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id             uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  business_name        text NOT NULL,
  contact_name         text,
  contact_phone        text,
  contact_email        text,
  address              text,
  latitude             double precision,
  longitude            double precision,
  logo_url             text,
  approved_brands      text[]  NOT NULL DEFAULT '{}',   -- e.g. {'IGL','GasPro','FESGAS'}
  fulfilment_method    text    NOT NULL DEFAULT 'supplier_managed'
                         CHECK (fulfilment_method IN ('supplier_managed')),
  accepting_orders     boolean NOT NULL DEFAULT false,  -- supplier's own open/closed toggle
  delivery_operational boolean NOT NULL DEFAULT false,  -- admin: delivery service is live
  verification_status  text    NOT NULL DEFAULT 'pending'
                         CHECK (verification_status IN ('pending','in_review','approved','suspended','rejected')),
  is_active            boolean NOT NULL DEFAULT true,
  commission_bps       int     NOT NULL DEFAULT 0 CHECK (commission_bps BETWEEN 0 AND 10000), -- platform take, basis points
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_suppliers_owner_idx ON public.gas_suppliers(owner_id);
CREATE INDEX IF NOT EXISTS gas_suppliers_live_idx ON public.gas_suppliers(verification_status, is_active)
  WHERE verification_status = 'approved' AND is_active = true;

-- supplier staff (same shape as restaurant_staff)
CREATE TABLE IF NOT EXISTS public.gas_supplier_staff (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid NOT NULL REFERENCES public.gas_suppliers(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role        text NOT NULL DEFAULT 'staff' CHECK (role IN ('manager','staff')),
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (supplier_id, user_id)
);
CREATE INDEX IF NOT EXISTS gas_supplier_staff_user_idx ON public.gas_supplier_staff(user_id, is_active);

-- supplier compliance documents (licence / insurance). Raw files live in a
-- PRIVATE storage bucket; this row holds the path + review state only.
CREATE TABLE IF NOT EXISTS public.gas_supplier_verifications (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id   uuid NOT NULL REFERENCES public.gas_suppliers(id) ON DELETE CASCADE,
  doc_type      text NOT NULL CHECK (doc_type IN ('lpg_licence','insurance','business_reg','other')),
  doc_path      text,           -- PRIVATE bucket path (signed URL only)
  reference_no  text,
  expires_on    date,
  status        text NOT NULL DEFAULT 'submitted'
                  CHECK (status IN ('submitted','approved','rejected','expired')),
  review_reason text,
  reviewed_by   uuid,
  reviewed_at   timestamptz,
  created_by    uuid NOT NULL DEFAULT auth.uid(),
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_supplier_verif_idx ON public.gas_supplier_verifications(supplier_id, status);

-- supplier delivery service areas (simple radius; polygon later if needed)
CREATE TABLE IF NOT EXISTS public.gas_delivery_zones (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id uuid NOT NULL REFERENCES public.gas_suppliers(id) ON DELETE CASCADE,
  name        text NOT NULL,
  center_lat  double precision NOT NULL,
  center_lng  double precision NOT NULL,
  radius_km   numeric NOT NULL CHECK (radius_km > 0),
  delivery_fee_cents bigint NOT NULL DEFAULT 0 CHECK (delivery_fee_cents >= 0),
  is_active   boolean NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_zones_supplier_idx ON public.gas_delivery_zones(supplier_id, is_active);

-- authorised delivery operators (per-supplier; eligibility is CONFIGURABLE and
-- asserts no legal compliance — see header). Gas orders only go to eligible ops.
CREATE TABLE IF NOT EXISTS public.gas_delivery_operators (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id    uuid NOT NULL REFERENCES public.gas_suppliers(id) ON DELETE CASCADE,
  user_id        uuid REFERENCES public.users(id) ON DELETE SET NULL, -- optional app login
  name           text NOT NULL,
  phone          text,
  vehicle_info   text,
  transport_auth_ref text,        -- transport authorisation reference (configurable)
  insurance_ref  text,
  training_ref   text,
  eligible       boolean NOT NULL DEFAULT false, -- supplier/admin attests eligibility
  is_active      boolean NOT NULL DEFAULT true,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_operators_supplier_idx ON public.gas_delivery_operators(supplier_id, is_active, eligible);

-- ── Products (supplier-specific cylinders) ──────────────────────────────────
CREATE TABLE IF NOT EXISTS public.gas_products (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  supplier_id          uuid NOT NULL REFERENCES public.gas_suppliers(id) ON DELETE CASCADE,
  brand                text NOT NULL,
  size_label           text NOT NULL,                 -- '20 lb','25 lb','100 lb' (configurable)
  size_lb              numeric,                        -- numeric weight for sorting/matching
  description          text,
  image_url            text,
  exchange_price_cents bigint CHECK (exchange_price_cents IS NULL OR exchange_price_cents >= 0),
  new_price_cents      bigint CHECK (new_price_cents IS NULL OR new_price_cents >= 0),
  deposit_cents        bigint NOT NULL DEFAULT 0 CHECK (deposit_cents >= 0), -- refundable liability
  stock_qty            int    NOT NULL DEFAULT 0 CHECK (stock_qty >= 0),
  exchange_available   boolean NOT NULL DEFAULT true,
  new_available        boolean NOT NULL DEFAULT false,
  is_active            boolean NOT NULL DEFAULT true,
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  -- a product must be buyable at least one way when active
  CHECK (exchange_available OR new_available),
  CHECK (NOT exchange_available OR exchange_price_cents IS NOT NULL),
  CHECK (NOT new_available OR new_price_cents IS NOT NULL)
);
CREATE INDEX IF NOT EXISTS gas_products_supplier_idx ON public.gas_products(supplier_id, is_active);

-- inventory movement ledger (auditable; stock_qty on gas_products is authoritative,
-- adjusted atomically by RPCs — mirrors grocery inventory pattern)
CREATE TABLE IF NOT EXISTS public.gas_inventory_movements (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  product_id  uuid NOT NULL REFERENCES public.gas_products(id) ON DELETE CASCADE,
  delta       int NOT NULL,                   -- negative = reserved/sold, positive = restock/restore
  reason      text NOT NULL CHECK (reason IN ('restock','reserve','sale','restore','adjust')),
  order_id    uuid,                            -- references gas_orders(id); set after order exists
  actor_id    uuid DEFAULT auth.uid(),
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_inv_moves_product_idx ON public.gas_inventory_movements(product_id, created_at);

-- ── Orders (separate from `orders`; own state machine) ──────────────────────
CREATE TABLE IF NOT EXISTS public.gas_orders (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id        uuid NOT NULL REFERENCES public.users(id) ON DELETE RESTRICT,
  supplier_id        uuid NOT NULL REFERENCES public.gas_suppliers(id) ON DELETE RESTRICT,
  address_id         uuid,                      -- references user address; snapshot below
  delivery_address   text,
  delivery_lat       double precision,
  delivery_lng       double precision,
  delivery_type      text NOT NULL DEFAULT 'gas' CHECK (delivery_type = 'gas'), -- excludes food dispatch
  -- money (JMD cents; backend-authoritative, never trust client totals)
  items_cents        bigint NOT NULL DEFAULT 0 CHECK (items_cents >= 0),
  deposit_cents      bigint NOT NULL DEFAULT 0 CHECK (deposit_cents >= 0),  -- liability, not revenue
  delivery_cents     bigint NOT NULL DEFAULT 0 CHECK (delivery_cents >= 0),
  service_fee_cents  bigint NOT NULL DEFAULT 0 CHECK (service_fee_cents >= 0),
  tax_cents          bigint NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
  discount_cents     bigint NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  total_cents        bigint NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  currency           text NOT NULL DEFAULT 'JMD',
  -- fulfilment state machine (SEPARATE from payment state)
  status             text NOT NULL DEFAULT 'pending_supplier'
                       CHECK (status IN (
                         'pending_supplier','supplier_accepted','awaiting_payment',
                         'payment_confirmed','preparing','assigned','out_for_delivery',
                         'delivered','exchange_completed','completed',
                         'cancelled','rejected','failed_delivery','refund_pending','refunded')),
  payment_status     text NOT NULL DEFAULT 'unpaid'
                       CHECK (payment_status IN ('unpaid','authorized','paid','refunded','partial_refund','failed')),
  payment_method     text,                      -- wallet | stripe | ncb | cash
  payment_ref        text,
  operator_id        uuid REFERENCES public.gas_delivery_operators(id) ON DELETE SET NULL,
  notes              text,
  reject_reason      text,
  cancel_reason      text,
  placed_at          timestamptz NOT NULL DEFAULT now(),
  accepted_at        timestamptz,
  delivered_at       timestamptz,
  completed_at       timestamptz,
  updated_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_orders_customer_idx ON public.gas_orders(customer_id, status);
CREATE INDEX IF NOT EXISTS gas_orders_supplier_idx ON public.gas_orders(supplier_id, status, placed_at);

-- order line items (snapshot of product + price at order time; immutable)
CREATE TABLE IF NOT EXISTS public.gas_order_items (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id           uuid NOT NULL REFERENCES public.gas_orders(id) ON DELETE CASCADE,
  product_id         uuid REFERENCES public.gas_products(id) ON DELETE SET NULL,
  brand              text NOT NULL,
  size_label         text NOT NULL,
  purchase_type      text NOT NULL CHECK (purchase_type IN ('exchange','new')),
  qty                int  NOT NULL CHECK (qty > 0),
  unit_price_cents   bigint NOT NULL CHECK (unit_price_cents >= 0),
  deposit_cents      bigint NOT NULL DEFAULT 0 CHECK (deposit_cents >= 0),
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_order_items_order_idx ON public.gas_order_items(order_id);

-- cylinder exchange records (one per exchange line; supplier must approve)
CREATE TABLE IF NOT EXISTS public.gas_cylinder_exchanges (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id           uuid NOT NULL REFERENCES public.gas_orders(id) ON DELETE CASCADE,
  order_item_id      uuid REFERENCES public.gas_order_items(id) ON DELETE CASCADE,
  existing_brand     text,
  existing_size      text,
  condition_declared text,                      -- customer declaration
  photo_path         text,                      -- optional, PRIVATE bucket
  collectible        boolean NOT NULL DEFAULT true,
  -- supplier compatibility decision — NEVER auto-approved from a photo
  supplier_decision  text NOT NULL DEFAULT 'pending'
                       CHECK (supplier_decision IN ('pending','approved','rejected','alternative_offered')),
  decision_reason    text,
  price_adjust_cents bigint NOT NULL DEFAULT 0,  -- may be negative
  replacement_brand  text,
  replacement_size   text,
  collected_at       timestamptz,               -- operator confirms collection
  completed          boolean NOT NULL DEFAULT false,
  decided_by         uuid,
  created_at         timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_exchanges_order_idx ON public.gas_cylinder_exchanges(order_id, supplier_decision);

-- delivery assignment (supplier-managed; separate from driver dispatch)
CREATE TABLE IF NOT EXISTS public.gas_delivery_assignments (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     uuid NOT NULL REFERENCES public.gas_orders(id) ON DELETE CASCADE,
  operator_id  uuid NOT NULL REFERENCES public.gas_delivery_operators(id) ON DELETE RESTRICT,
  status       text NOT NULL DEFAULT 'assigned'
                 CHECK (status IN ('assigned','picked_up','delivered','failed','unassigned')),
  payout_cents bigint NOT NULL DEFAULT 0 CHECK (payout_cents >= 0), -- operator liability until paid
  assigned_by  uuid DEFAULT auth.uid(),
  assigned_at  timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_assign_order_idx ON public.gas_delivery_assignments(order_id);
CREATE INDEX IF NOT EXISTS gas_assign_operator_idx ON public.gas_delivery_assignments(operator_id, status);

-- immutable order event / audit history (every status transition)
CREATE TABLE IF NOT EXISTS public.gas_order_events (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id     uuid NOT NULL REFERENCES public.gas_orders(id) ON DELETE CASCADE,
  prev_status  text,
  new_status   text NOT NULL,
  actor_id     uuid DEFAULT auth.uid(),
  actor_role   text,                             -- customer | supplier | operator | admin | system
  reason       text,
  meta         jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS gas_order_events_idx ON public.gas_order_events(order_id, created_at);

-- ── Permission helper: may the caller manage this gas supplier? ──────────────
-- Defined here, after its referenced tables exist. True for platform admins,
-- the supplier owner, or an active supplier staffer. Mirrors
-- can_manage_restaurant(). SECURITY DEFINER + auth.uid() (never a caller-supplied
-- id) so it cannot be used to act as another user.
CREATE OR REPLACE FUNCTION public.can_manage_gas_supplier(p_supplier uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.gas_suppliers s
               WHERE s.id = p_supplier AND s.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.gas_supplier_staff st
               WHERE st.supplier_id = p_supplier
                 AND st.user_id = auth.uid()
                 AND st.is_active = true);
$$;
REVOKE ALL ON FUNCTION public.can_manage_gas_supplier(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_gas_supplier(uuid) TO authenticated;

-- ============================================================================
-- RLS — supplier-scoped for supplier users, customer-owns-their-own, admin full.
-- Customers NEVER see supplier internals (verifications, operators, payouts).
-- All status transitions go through SECURITY DEFINER lifecycle RPCs (next
-- migration), not raw UPDATE — these policies only cover direct row access.
-- ============================================================================
ALTER TABLE public.gas_suppliers             ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_supplier_staff        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_supplier_verifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_delivery_zones        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_delivery_operators    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_products              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_inventory_movements   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_orders                ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_order_items           ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_cylinder_exchanges    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_delivery_assignments  ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gas_order_events          ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.gas_suppliers, public.gas_supplier_staff,
  public.gas_supplier_verifications, public.gas_delivery_zones,
  public.gas_delivery_operators, public.gas_products,
  public.gas_inventory_movements, public.gas_orders, public.gas_order_items,
  public.gas_cylinder_exchanges, public.gas_delivery_assignments,
  public.gas_order_events FROM anon;

-- suppliers: customers READ only live suppliers; managers read/write their own; admin full.
CREATE POLICY gas_suppliers_public_read ON public.gas_suppliers FOR SELECT TO authenticated
  USING (verification_status = 'approved' AND is_active = true
         OR public.can_manage_gas_supplier(id));
CREATE POLICY gas_suppliers_manage ON public.gas_suppliers FOR UPDATE TO authenticated
  USING (public.can_manage_gas_supplier(id))
  WITH CHECK (public.can_manage_gas_supplier(id));
CREATE POLICY gas_suppliers_admin_write ON public.gas_suppliers FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- supplier staff / verifications / zones / operators: supplier-scoped; admin full.
CREATE POLICY gas_staff_manage ON public.gas_supplier_staff FOR ALL TO authenticated
  USING (public.can_manage_gas_supplier(supplier_id))
  WITH CHECK (public.can_manage_gas_supplier(supplier_id));

CREATE POLICY gas_verif_manage ON public.gas_supplier_verifications FOR ALL TO authenticated
  USING (public.can_manage_gas_supplier(supplier_id))
  WITH CHECK (public.can_manage_gas_supplier(supplier_id));

CREATE POLICY gas_zones_read ON public.gas_delivery_zones FOR SELECT TO authenticated
  USING (is_active OR public.can_manage_gas_supplier(supplier_id));
CREATE POLICY gas_zones_manage ON public.gas_delivery_zones FOR ALL TO authenticated
  USING (public.can_manage_gas_supplier(supplier_id))
  WITH CHECK (public.can_manage_gas_supplier(supplier_id));

CREATE POLICY gas_operators_manage ON public.gas_delivery_operators FOR ALL TO authenticated
  USING (public.can_manage_gas_supplier(supplier_id))
  WITH CHECK (public.can_manage_gas_supplier(supplier_id));

-- products: customers READ active products of live suppliers; managers manage own; admin full.
CREATE POLICY gas_products_public_read ON public.gas_products FOR SELECT TO authenticated
  USING (
    public.can_manage_gas_supplier(supplier_id)
    OR (is_active AND EXISTS (
          SELECT 1 FROM public.gas_suppliers s
          WHERE s.id = supplier_id AND s.verification_status = 'approved' AND s.is_active = true)));
CREATE POLICY gas_products_manage ON public.gas_products FOR ALL TO authenticated
  USING (public.can_manage_gas_supplier(supplier_id))
  WITH CHECK (public.can_manage_gas_supplier(supplier_id));

-- inventory movements: supplier-scoped read; writes happen in RPCs only.
CREATE POLICY gas_inv_read ON public.gas_inventory_movements FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.gas_products p
                 WHERE p.id = product_id AND public.can_manage_gas_supplier(p.supplier_id)));

-- orders: the customer who placed it OR the managing supplier OR admin.
CREATE POLICY gas_orders_read ON public.gas_orders FOR SELECT TO authenticated
  USING (customer_id = auth.uid() OR public.can_manage_gas_supplier(supplier_id));
-- No direct INSERT/UPDATE: placing & status changes go through place-gas-order /
-- lifecycle RPCs (SECURITY DEFINER). Admin override for support only.
CREATE POLICY gas_orders_admin_write ON public.gas_orders FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

CREATE POLICY gas_order_items_read ON public.gas_order_items FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.gas_orders o WHERE o.id = order_id
                 AND (o.customer_id = auth.uid() OR public.can_manage_gas_supplier(o.supplier_id))));

CREATE POLICY gas_exchanges_read ON public.gas_cylinder_exchanges FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.gas_orders o WHERE o.id = order_id
                 AND (o.customer_id = auth.uid() OR public.can_manage_gas_supplier(o.supplier_id))));

-- delivery assignments / payouts: supplier + admin only (never the customer).
CREATE POLICY gas_assign_manage ON public.gas_delivery_assignments FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM public.gas_orders o WHERE o.id = order_id
                 AND public.can_manage_gas_supplier(o.supplier_id)))
  WITH CHECK (EXISTS (SELECT 1 FROM public.gas_orders o WHERE o.id = order_id
                 AND public.can_manage_gas_supplier(o.supplier_id)));

-- order events: readable by order participants; written only inside RPCs.
CREATE POLICY gas_order_events_read ON public.gas_order_events FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM public.gas_orders o WHERE o.id = order_id
                 AND (o.customer_id = auth.uid() OR public.can_manage_gas_supplier(o.supplier_id))));

NOTIFY pgrst, 'reload schema';

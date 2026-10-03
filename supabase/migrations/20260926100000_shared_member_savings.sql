-- ============================================================================
-- Shared Member Savings — revise HotBite+ item pricing so the member saving is
-- split 50/50 between the customer and HotBite.
-- ============================================================================
-- store sets: menus.price/discount → regular_price; menus.hotbite_plus_price →
-- store_member_price (the amount the store agrees to receive).
-- For an active member on an eligible item:
--   available_saving  = regular_price - store_member_price
--   customer_saving   = floor(available_saving / 2)          (customer gets the floor)
--   hotbite_share     = available_saving - customer_saving   (HotBite gets the remainder)
--   customer_price    = regular_price - customer_saving      (= store_member + hotbite_share)
--   store_payout      = store_member_price
-- customer_saving + hotbite_share always equals available_saving (no lost cents).
-- All math is done in integer cents (bigint) — never floating point.

CREATE OR REPLACE FUNCTION public.hotbite_member_split(
  p_regular numeric, p_store_member numeric
) RETURNS TABLE(
  customer_price numeric, customer_saving numeric, hotbite_share numeric,
  store_payout numeric, available_saving numeric, eligible boolean
)
LANGUAGE plpgsql IMMUTABLE
AS $fn$
-- JMD is a whole-number currency here, so the split is computed in integer JMD:
-- customer_saving = floor(available/2), HotBite takes the odd unit. This matches
-- the spec's odd-difference example (available 99 → 49 / 50) and never uses float.
DECLARE reg_j bigint; sm_j bigint; avail_j bigint; cust_j bigint; hb_j bigint;
BEGIN
  IF p_store_member IS NULL OR p_store_member <= 0 OR p_regular IS NULL
     OR round(p_store_member) >= round(p_regular) THEN
    RETURN QUERY SELECT p_regular, 0::numeric, 0::numeric, p_regular, 0::numeric, false;
    RETURN;
  END IF;
  reg_j := round(p_regular)::bigint;
  sm_j  := round(p_store_member)::bigint;
  avail_j := reg_j - sm_j;
  cust_j  := avail_j / 2;            -- integer floor
  hb_j    := avail_j - cust_j;       -- remainder (odd JMD to HotBite)
  RETURN QUERY SELECT
    (reg_j - cust_j)::numeric,       -- customer_price
    cust_j::numeric,                 -- customer_saving
    hb_j::numeric,                   -- hotbite_share
    sm_j::numeric,                   -- store_payout
    avail_j::numeric,                -- available_saving
    true;
END;
$fn$;
GRANT EXECUTE ON FUNCTION public.hotbite_member_split(numeric,numeric) TO authenticated, service_role, anon;

-- ── immutable per-item snapshot columns (reconcilable ledger) ──────────────
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS store_member_price   numeric;  -- agreed store receive / unit
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS customer_saving      numeric;  -- per unit
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS hotbite_savings_share numeric; -- per unit
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS store_payout_total   numeric;  -- store_member_price * qty
ALTER TABLE public.order_items ADD COLUMN IF NOT EXISTS pricing_version      int NOT NULL DEFAULT 2; -- v2 = shared savings
-- (regular_price, member_discount, membership_applied already exist.)

-- Order-level HotBite savings-share revenue (distinct from commission, fees).
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS hotbite_savings_share numeric NOT NULL DEFAULT 0;

-- ── audit: who changed a member price and when ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.menu_member_price_audit (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id  uuid NOT NULL REFERENCES public.menus(id) ON DELETE CASCADE,
  restaurant_id uuid,
  old_value     numeric,
  new_value     numeric,
  changed_by    uuid REFERENCES public.users(id) ON DELETE SET NULL,
  created_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_member_price_audit_item ON public.menu_member_price_audit(menu_item_id);
ALTER TABLE public.menu_member_price_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS member_price_audit_read ON public.menu_member_price_audit;
CREATE POLICY member_price_audit_read ON public.menu_member_price_audit FOR SELECT TO authenticated
  USING (public.current_user_owns_restaurant(restaurant_id) OR public.is_admin());
GRANT SELECT ON public.menu_member_price_audit TO authenticated;

CREATE OR REPLACE FUNCTION public.audit_menu_member_price()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $t$
BEGIN
  IF TG_OP='UPDATE' AND NEW.hotbite_plus_price IS DISTINCT FROM OLD.hotbite_plus_price THEN
    INSERT INTO menu_member_price_audit(menu_item_id, restaurant_id, old_value, new_value, changed_by)
    VALUES (NEW.id, NEW.restaurant_id, OLD.hotbite_plus_price, NEW.hotbite_plus_price, auth.uid());
  END IF;
  RETURN NEW;
END; $t$;
DROP TRIGGER IF EXISTS trg_audit_member_price ON public.menus;
CREATE TRIGGER trg_audit_member_price AFTER UPDATE ON public.menus
  FOR EACH ROW EXECUTE FUNCTION public.audit_menu_member_price();

NOTIFY pgrst, 'reload schema';

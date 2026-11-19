-- Promo management was failing to save because the admin Promos screen writes
-- DIRECTLY to promo_codes, whose RLS INSERT/UPDATE/DELETE policies require
-- is_admin() — which demands an aal2 (2FA-elevated) session. The rest of the
-- admin app writes through SECURITY DEFINER RPCs gated by require_admin()
-- (role='admin', no aal2 requirement), so promo management is the odd one out
-- and silently fails whenever the admin session is aal1.
--
-- Add promo RPCs that match the rest of the admin surface: SECURITY DEFINER,
-- gated by require_admin(). No RLS policy is weakened; direct-table writes still
-- need aal2, but admins can manage promos through these audited RPCs.
CREATE OR REPLACE FUNCTION public.admin_create_promo(
  p_code text,
  p_discount_type text,
  p_discount_value numeric,
  p_min_order_amount numeric DEFAULT NULL,
  p_max_uses integer DEFAULT NULL,
  p_expires_at timestamptz DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_id uuid;
BEGIN
  PERFORM public.require_admin(auth.uid());
  IF p_discount_type NOT IN ('percentage','fixed') THEN
    RAISE EXCEPTION 'Invalid discount type: %', p_discount_type;
  END IF;
  IF COALESCE(p_discount_value,0) <= 0 THEN
    RAISE EXCEPTION 'Discount value must be positive';
  END IF;
  INSERT INTO promo_codes (code, discount_type, discount_value,
    min_order_amount, max_uses, expires_at, is_active)
  VALUES (upper(trim(p_code)), p_discount_type, p_discount_value,
    p_min_order_amount, p_max_uses, p_expires_at, true)
  RETURNING id INTO v_id;
  RETURN v_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.admin_set_promo_active(
  p_promo_id uuid, p_is_active boolean
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  PERFORM public.require_admin(auth.uid());
  UPDATE promo_codes SET is_active = p_is_active WHERE id = p_promo_id;
END; $fn$;

CREATE OR REPLACE FUNCTION public.admin_delete_promo(p_promo_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
BEGIN
  PERFORM public.require_admin(auth.uid());
  DELETE FROM promo_codes WHERE id = p_promo_id;
END; $fn$;

GRANT EXECUTE ON FUNCTION public.admin_create_promo(text,text,numeric,numeric,integer,timestamptz) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_promo_active(uuid,boolean) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_delete_promo(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

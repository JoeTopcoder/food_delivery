-- HotBite+ checkout discount engine. Server-authoritative: given a user, a
-- business and the food subtotal, it returns the member discount for the single
-- best eligible, approved, in-window deal — honouring minimum order, usage
-- limits (total + per-customer) and funding split. Returns zero for non-members
-- or when nothing qualifies. The client can never inflate this.
CREATE OR REPLACE FUNCTION public.calculate_membership_discount(
  p_user_id       uuid,
  p_business_id   uuid,
  p_subtotal      numeric
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $fn$
DECLARE
  d record;
  v_amount numeric := 0;
  v_used_total int;
  v_used_customer int;
  v_biz_pct numeric;
BEGIN
  -- Non-members get nothing.
  IF NOT public.is_hotbite_plus_member(p_user_id) THEN
    RETURN jsonb_build_object('discount_amount', 0);
  END IF;

  -- Pick the deal that yields the largest valid discount for this business.
  FOR d IN
    SELECT * FROM public.membership_deals md
    WHERE md.business_id = p_business_id
      AND md.status = 'approved'
      AND md.is_active = true
      AND md.requires_membership = true
      AND (md.start_date IS NULL OR md.start_date <= now())
      AND (md.end_date IS NULL OR md.end_date >= now())
      AND p_subtotal >= COALESCE(md.minimum_order_amount, 0)
      AND md.discount_type IN ('percentage','fixed_amount','special_price')
  LOOP
    -- Usage limits.
    SELECT count(*) INTO v_used_total
      FROM public.order_membership_discounts WHERE deal_id = d.id;
    IF d.usage_limit IS NOT NULL AND v_used_total >= d.usage_limit THEN
      CONTINUE;
    END IF;
    SELECT count(*) INTO v_used_customer
      FROM public.order_membership_discounts omd
      JOIN public.orders o ON o.id = omd.order_id
      WHERE omd.deal_id = d.id AND o.user_id = p_user_id;
    IF COALESCE(d.usage_limit_per_customer, 1) IS NOT NULL
       AND v_used_customer >= COALESCE(d.usage_limit_per_customer, 1) THEN
      CONTINUE;
    END IF;

    -- Discount by type.
    DECLARE v_this numeric := 0;
    BEGIN
      IF d.discount_type = 'percentage' THEN
        v_this := p_subtotal * (d.discount_value / 100.0);
      ELSIF d.discount_type = 'fixed_amount' THEN
        v_this := d.discount_value;
      ELSIF d.discount_type = 'special_price' THEN
        v_this := GREATEST(0, p_subtotal - d.discount_value);
      END IF;
      IF d.maximum_discount_amount IS NOT NULL THEN
        v_this := LEAST(v_this, d.maximum_discount_amount);
      END IF;
      v_this := LEAST(v_this, p_subtotal);   -- never exceed the subtotal
      IF v_this > v_amount THEN
        v_amount := v_this;
        v_biz_pct := COALESCE(d.business_funded_pct, 100);
        -- stash the winning deal id via a temp on the record
        PERFORM set_config('hotbite.deal_id', d.id::text, true);
        PERFORM set_config('hotbite.deal_type', d.discount_type, true);
      END IF;
    END;
  END LOOP;

  IF v_amount <= 0 THEN
    RETURN jsonb_build_object('discount_amount', 0);
  END IF;

  v_amount := round(v_amount, 2);
  RETURN jsonb_build_object(
    'discount_amount', v_amount,
    'deal_id', current_setting('hotbite.deal_id', true),
    'discount_type', current_setting('hotbite.deal_type', true),
    'business_funded_amount', round(v_amount * v_biz_pct / 100.0, 2),
    'hotbite_funded_amount', round(v_amount * (100 - v_biz_pct) / 100.0, 2)
  );
END;
$fn$;

GRANT EXECUTE ON FUNCTION public.calculate_membership_discount(uuid, uuid, numeric)
  TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

-- Record COD collections in the driver float ledger so the float history
-- reconciles with the balance. Previously the COD credit updated cash_float
-- directly (via increment_cash_float) with no driver_float_transactions row, so
-- only restaurant payments showed in the history. This adds an idempotent,
-- audited COD credit that writes a 'cod_collection' entry.
CREATE OR REPLACE FUNCTION public.collect_cod_to_float(
  p_driver_id uuid,
  p_order_id  uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pay_method text;
  v_total numeric;
  v_existing driver_float_transactions%ROWTYPE;
  v_new_float double precision;
BEGIN
  SELECT payment_method, total_amount INTO v_pay_method, v_total
  FROM orders WHERE id = p_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'order % not found', p_order_id;
  END IF;

  -- Only cash (COD) orders put collected cash on the float.
  IF COALESCE(v_pay_method, '') <> 'cash' OR COALESCE(v_total, 0) <= 0 THEN
    RETURN jsonb_build_object('collected', 0);
  END IF;

  -- Idempotency: never credit the same COD collection twice.
  SELECT * INTO v_existing FROM driver_float_transactions
   WHERE driver_id = p_driver_id AND order_id = p_order_id
     AND type = 'cod_collection'
   LIMIT 1;
  IF FOUND THEN
    RETURN jsonb_build_object('collected', v_existing.amount,
                              'balance_after', v_existing.balance_after,
                              'idempotent', true);
  END IF;

  v_new_float := apply_driver_float_change(
    p_driver_id, v_total, 'cod_collection', p_order_id,
    'Cash collected from customer (COD)'
  );

  RETURN jsonb_build_object('collected', v_total, 'balance_after', v_new_float);
END;
$$;

REVOKE ALL ON FUNCTION public.collect_cod_to_float(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.collect_cod_to_float(uuid, uuid) TO service_role;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- Dynamic Peak Time system
-- Peak Time turns ON when the number of ACTIVE orders strictly exceeds a
-- configurable threshold (active_order_count > threshold; never >=), and OFF
-- otherwise. Backend-authoritative: the count, threshold, fee and ETA
-- adjustment are all decided here, never trusted from a client.
-- Food and grocery orders share the single `orders` table, so one aggregate
-- counts both without double-counting.
-- ============================================================================

-- 1. Configuration (reuses the existing app_config key/value store) ----------
INSERT INTO app_config (key, value, value_type, category, description, updated_at)
VALUES
  ('peak_time_enabled',                'true',  'bool', 'peak_time',
   'Master switch for Dynamic Peak Time. When false, Peak Time is always OFF.', now()),
  ('peak_time_order_threshold',        '80',    'int',  'peak_time',
   'Peak Time turns ON when active orders > this value. Default 80.', now()),
  ('peak_time_fee_enabled',            'false', 'bool', 'peak_time',
   'When true, a Peak Time delivery surcharge applies while Peak Time is ON.', now()),
  ('peak_time_fee',                    '0',     'double','peak_time',
   'Peak Time delivery surcharge amount (in the app currency).', now()),
  ('peak_time_eta_adjustment_minutes', '0',     'int',  'peak_time',
   'Minutes added to ETA while Peak Time is ON.', now())
ON CONFLICT (key) DO NOTHING;

-- 2. Per-order Peak Time surcharge captured at order creation ----------------
ALTER TABLE orders ADD COLUMN IF NOT EXISTS peak_fee double precision NOT NULL DEFAULT 0;

-- 3. Efficient active-order aggregate ----------------------------------------
-- Partial index over exactly the active statuses so the count is an index-only
-- scan even with thousands of live orders. Excludes mock/test orders.
CREATE INDEX IF NOT EXISTS idx_orders_active_peak
  ON orders (status)
  WHERE status IN ('pending','confirmed','preparing','ready','picked_up','on_the_way')
    AND is_mock_data IS NOT TRUE;

-- Small helper so the active-status set is defined in exactly one place.
CREATE OR REPLACE FUNCTION public.peak_time_active_order_count()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT count(*)::integer
  FROM orders
  WHERE status IN ('pending','confirmed','preparing','ready','picked_up','on_the_way')
    AND is_mock_data IS NOT TRUE;
$$;

-- 4. Authoritative Peak Time state -------------------------------------------
-- Returns ONLY aggregate state (no individual order data). SECURITY DEFINER so
-- callers never need to read the orders table directly.
CREATE OR REPLACE FUNCTION public.get_peak_time_state()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled       boolean;
  v_fee_enabled   boolean;
  v_threshold_txt text;
  v_fee_txt       text;
  v_eta_txt       text;
  v_threshold     integer;
  v_fee           double precision;
  v_eta_adj       integer;
  v_updated       timestamptz;
  v_count         integer;
  v_is_peak       boolean;
BEGIN
  SELECT
    coalesce(bool_or(key = 'peak_time_enabled'     AND lower(value) IN ('true','1')), false),
    coalesce(bool_or(key = 'peak_time_fee_enabled' AND lower(value) IN ('true','1')), false),
    max(value) FILTER (WHERE key = 'peak_time_order_threshold'),
    max(value) FILTER (WHERE key = 'peak_time_fee'),
    max(value) FILTER (WHERE key = 'peak_time_eta_adjustment_minutes'),
    max(updated_at)
  INTO v_enabled, v_fee_enabled, v_threshold_txt, v_fee_txt, v_eta_txt, v_updated
  FROM app_config
  WHERE key IN ('peak_time_enabled','peak_time_order_threshold','peak_time_fee_enabled',
                'peak_time_fee','peak_time_eta_adjustment_minutes');

  v_threshold := coalesce(nullif(v_threshold_txt,'')::numeric::int, 80);
  v_fee       := coalesce(nullif(v_fee_txt,'')::numeric, 0);
  v_eta_adj   := coalesce(nullif(v_eta_txt,'')::numeric::int, 0);

  v_count   := public.peak_time_active_order_count();
  v_is_peak := v_enabled AND v_count > v_threshold;   -- strict >, never >=

  RETURN jsonb_build_object(
    'active_order_count',     v_count,
    'threshold',              v_threshold,
    'enabled',                v_enabled,
    'is_peak_time',           v_is_peak,
    'fee_enabled',            v_fee_enabled,
    'fee',                    CASE WHEN v_is_peak AND v_fee_enabled THEN v_fee ELSE 0 END,
    'eta_adjustment_minutes', CASE WHEN v_is_peak THEN v_eta_adj ELSE 0 END,
    'updated_at',             v_updated
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_peak_time_state() TO authenticated, anon;
REVOKE EXECUTE ON FUNCTION public.peak_time_active_order_count() FROM anon;

-- 5. Admin configuration write + audit ---------------------------------------
CREATE TABLE IF NOT EXISTS peak_time_config_audit (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id     uuid REFERENCES users(id),
  config_key   text NOT NULL,
  old_value    text,
  new_value    text,
  changed_at   timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE peak_time_config_audit ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS peak_audit_admin_read ON peak_time_config_audit;
CREATE POLICY peak_audit_admin_read ON peak_time_config_audit FOR SELECT
  USING (EXISTS (SELECT 1 FROM users WHERE users.id = auth.uid() AND users.role = 'admin'));

-- Validates and writes the five Peak Time settings in one atomic call, gated to
-- admins, recording an audit row per changed key. NULL args leave a key
-- unchanged. Returns the fresh authoritative state.
CREATE OR REPLACE FUNCTION public.admin_set_peak_time_config(
  p_enabled        boolean DEFAULT NULL,
  p_threshold      integer DEFAULT NULL,
  p_fee_enabled    boolean DEFAULT NULL,
  p_fee            double precision DEFAULT NULL,
  p_eta_adjustment integer DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF NOT EXISTS (SELECT 1 FROM users WHERE id = v_uid AND role = 'admin') THEN
    RAISE EXCEPTION 'not_authorized' USING ERRCODE = '42501';
  END IF;

  IF p_threshold IS NOT NULL AND p_threshold < 0 THEN
    RAISE EXCEPTION 'invalid_threshold' USING ERRCODE = '22023';
  END IF;
  IF p_fee IS NOT NULL AND p_fee < 0 THEN
    RAISE EXCEPTION 'invalid_fee' USING ERRCODE = '22023';
  END IF;
  IF p_eta_adjustment IS NOT NULL AND p_eta_adjustment < 0 THEN
    RAISE EXCEPTION 'invalid_eta' USING ERRCODE = '22023';
  END IF;

  PERFORM _peak_set(v_uid, 'peak_time_enabled',                CASE WHEN p_enabled     THEN 'true' WHEN p_enabled IS FALSE THEN 'false' END);
  PERFORM _peak_set(v_uid, 'peak_time_order_threshold',        p_threshold::text);
  PERFORM _peak_set(v_uid, 'peak_time_fee_enabled',            CASE WHEN p_fee_enabled THEN 'true' WHEN p_fee_enabled IS FALSE THEN 'false' END);
  PERFORM _peak_set(v_uid, 'peak_time_fee',                    p_fee::text);
  PERFORM _peak_set(v_uid, 'peak_time_eta_adjustment_minutes', p_eta_adjustment::text);

  RETURN public.get_peak_time_state();
END;
$$;

-- Internal: write one key if the new value is non-null and changed, with audit.
CREATE OR REPLACE FUNCTION public._peak_set(p_admin uuid, p_key text, p_new text)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old text;
BEGIN
  IF p_new IS NULL THEN
    RETURN;
  END IF;
  SELECT value INTO v_old FROM app_config WHERE key = p_key;
  IF v_old IS DISTINCT FROM p_new THEN
    UPDATE app_config SET value = p_new, updated_at = now() WHERE key = p_key;
    INSERT INTO peak_time_config_audit (admin_id, config_key, old_value, new_value)
    VALUES (p_admin, p_key, v_old, p_new);
  END IF;
END;
$$;

REVOKE EXECUTE ON FUNCTION public._peak_set(uuid, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_peak_time_config(boolean, integer, boolean, double precision, integer) TO authenticated;

NOTIFY pgrst, 'reload schema';

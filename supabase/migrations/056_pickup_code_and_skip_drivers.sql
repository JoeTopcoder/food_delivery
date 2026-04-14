-- Migration 056: Pickup code for restaurant→customer verification + skip driver notification for pickup orders
-- 1. Add pickup_code column to orders table
-- 2. Update notify_drivers_new_order() to skip pickup orders
-- 3. Update claim_order() to reject pickup orders

-- ── 1. Add pickup_code column ─────────────────────────────────────────────────
ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS pickup_code TEXT;

-- ── 2. Update driver notification to skip pickup orders ────────────────────────
CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url  text := current_setting('app.settings.supabase_url', true);
  _service_key   text := current_setting('app.settings.service_role_key', true);
  _edge_url      text;
  _short_id      text;
BEGIN
  -- Never notify drivers for pickup orders
  IF NEW.is_pickup = TRUE THEN
    RETURN NEW;
  END IF;

  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';
  _short_id := UPPER(LEFT(NEW.id::text, 8));

  IF (
    (TG_OP = 'INSERT' AND NEW.driver_id IS NULL AND NEW.status IN ('ready', 'pending'))
    OR
    (TG_OP = 'UPDATE' AND NEW.status = 'ready' AND (OLD.status IS DISTINCT FROM 'ready') AND NEW.driver_id IS NULL)
  ) THEN
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'available_drivers',
        'title', 'New Order Available! 🍔',
        'body',  'A new delivery order #' || _short_id || ' is waiting for pickup.',
        'data',  jsonb_build_object(
          'type',     'new_order',
          'order_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, 'sb_publishable_e-McqdkcLyoxV89A86lWGw_hD3vyVP6')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

-- ── 3. Update claim_order to reject pickup orders ──────────────────────────────
CREATE OR REPLACE FUNCTION claim_order(p_order_id UUID, p_driver_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  rows_updated INT;
BEGIN
  UPDATE orders
  SET driver_id = p_driver_id,
      status = 'picked_up',
      updated_at = NOW()
  WHERE id = p_order_id
    AND driver_id IS NULL
    AND is_pickup = FALSE;

  GET DIAGNOSTICS rows_updated = ROW_COUNT;
  RETURN rows_updated > 0;
END;
$$;

-- ============================================================================
-- Migration 109: Auto-Approve Orders (skip restaurant acceptance step)
-- ============================================================================
-- Cash/wallet orders are now created directly with status = 'preparing',
-- bypassing the 'pending' (restaurant must accept) stage entirely.
-- Card orders (Stripe) are set to 'preparing' by the webhook instead of 'pending'.
--
-- This migration:
--   1. Updates the driver notification trigger to fire for 'preparing' inserts
--      (previously only 'pending' and 'ready' were included)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_drivers_new_order()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  _supabase_url text := current_setting('app.settings.supabase_url', true);
  _service_key  text := current_setting('app.settings.service_role_key', true);
  _edge_url     text;
BEGIN
  IF _supabase_url IS NULL OR _supabase_url = '' THEN
    _supabase_url := 'https://yharweliruemjexmuuxn.supabase.co';
  END IF;
  _edge_url := _supabase_url || '/functions/v1/send-fcm-notification';

  IF (
    -- Non-card order created directly as active (cash / wallet).
    -- Now includes 'preparing' because orders skip 'pending' (auto-approved).
    (TG_OP = 'INSERT'
     AND NEW.driver_id IS NULL
     AND NEW.status IN ('pending', 'preparing', 'ready')
     AND NEW.payment_method NOT IN ('stripe', 'card')
     AND NEW.is_pickup IS NOT TRUE)
    OR
    -- Card order: payment just confirmed by webhook (webhook sets status='preparing')
    (TG_OP = 'UPDATE'
     AND NEW.payment_status = 'completed'
     AND OLD.payment_status IS DISTINCT FROM 'completed'
     AND NEW.driver_id IS NULL
     AND NEW.is_pickup IS NOT TRUE)
    OR
    -- Order became 'ready' with no driver (restaurant marked ready)
    (TG_OP = 'UPDATE'
     AND NEW.status = 'ready'
     AND OLD.status IS DISTINCT FROM 'ready'
     AND NEW.driver_id IS NULL
     AND NEW.payment_status = 'completed')
  ) THEN
    PERFORM extensions.http_post(
      url     := _edge_url,
      body    := jsonb_build_object(
        'topic', 'available_drivers',
        'title', 'New Order Available! 🍔',
        'body',  'A new delivery order is waiting for pickup.',
        'data',  jsonb_build_object(
          'type',     'new_order',
          'order_id', NEW.id::text
        )
      )::text,
      headers := jsonb_build_object(
        'Content-Type',  'application/json',
        'Authorization', 'Bearer ' || COALESCE(_service_key, '')
      )
    );
  END IF;

  RETURN NEW;
END;
$$;

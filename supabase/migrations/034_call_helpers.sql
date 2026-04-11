-- ====================================================================
-- 034: Call Helper Functions
-- 1. resolve_driver_user_id: Converts a drivers.id to the user_id
-- 2. initiate_call: Server-side call creation that resolves driver IDs
-- 3. notify_incoming_call: Sends FCM push to the receiver
-- ====================================================================

-- 1. Resolve a driver record ID to its user_id
-- SECURITY DEFINER so any authenticated user can look up the mapping
CREATE OR REPLACE FUNCTION public.resolve_driver_user_id(p_driver_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID;
BEGIN
  SELECT d.user_id INTO v_user_id
  FROM public.drivers d
  WHERE d.id = p_driver_id;
  
  RETURN v_user_id; -- NULL if not found (means it's already a user_id)
END;
$$;

-- 2. Server-side call initiation that auto-resolves driver_id → user_id
CREATE OR REPLACE FUNCTION public.initiate_call(
  p_order_id UUID,
  p_receiver_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller_id UUID;
  v_resolved_receiver UUID;
  v_driver_user_id UUID;
  v_channel TEXT;
  v_conv_id UUID;
  v_call JSONB;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Try to resolve receiver as a driver record
  SELECT d.user_id INTO v_driver_user_id
  FROM public.drivers d WHERE d.id = p_receiver_id;

  IF v_driver_user_id IS NOT NULL THEN
    v_resolved_receiver := v_driver_user_id;
  ELSE
    -- Check if it's a valid user ID already
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_receiver_id) THEN
      RAISE EXCEPTION 'Receiver not found';
    END IF;
    v_resolved_receiver := p_receiver_id;
  END IF;

  -- Prevent calling yourself
  IF v_caller_id = v_resolved_receiver THEN
    RAISE EXCEPTION 'Cannot call yourself';
  END IF;

  -- Generate channel name
  v_channel := 'call_' || p_order_id::TEXT || '_' || EXTRACT(EPOCH FROM NOW())::BIGINT::TEXT;

  -- Get existing conversation
  SELECT id INTO v_conv_id
  FROM public.conversations
  WHERE order_id = p_order_id
  LIMIT 1;

  -- Insert the call record
  INSERT INTO public.calls (order_id, conversation_id, caller_id, receiver_id, channel_name, status)
  VALUES (p_order_id, v_conv_id, v_caller_id, v_resolved_receiver, v_channel, 'ringing')
  RETURNING to_jsonb(calls.*) INTO v_call;

  RETURN v_call;
END;
$$;

-- Grant execute to authenticated users
GRANT EXECUTE ON FUNCTION public.resolve_driver_user_id(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.initiate_call(UUID, UUID) TO authenticated;

-- Note: Incoming call FCM notifications are sent app-side via
-- the send-fcm-notification edge function after the RPC call.
-- The Supabase realtime subscription on the calls table is used
-- for foreground call detection (IncomingCallListener widget).

-- Allow chat_messages and conversations to be linked to rides.
-- Makes order_id nullable so ride-linked messages have order_id = NULL.

-- 1. Make order_id nullable in chat_messages
ALTER TABLE public.chat_messages ALTER COLUMN order_id DROP NOT NULL;

-- 2. Add ride_id to chat_messages
ALTER TABLE public.chat_messages
  ADD COLUMN IF NOT EXISTS ride_id UUID REFERENCES public.ride_requests(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_chat_messages_ride_id ON public.chat_messages(ride_id);

-- 3. Make order_id nullable in conversations
ALTER TABLE public.conversations ALTER COLUMN order_id DROP NOT NULL;

-- 4. Add ride_id to conversations
ALTER TABLE public.conversations
  ADD COLUMN IF NOT EXISTS ride_id UUID REFERENCES public.ride_requests(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_conversations_ride_id ON public.conversations(ride_id);

-- 5. RPC to send a message on a ride
CREATE OR REPLACE FUNCTION public.send_ride_message(
  p_ride_id      UUID,
  p_message      TEXT,
  p_message_type TEXT    DEFAULT 'text',
  p_metadata     JSONB   DEFAULT '{}'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_sender_id        UUID;
  v_sender_role      TEXT;
  v_customer_id      UUID;
  v_driver_profile   UUID;
  v_driver_user_id   UUID;
  v_conv_id          UUID;
  v_msg_id           UUID;
  v_participant_ids  UUID[];
BEGIN
  v_sender_id := auth.uid();
  IF v_sender_id IS NULL THEN RAISE EXCEPTION 'Not authenticated'; END IF;

  SELECT role INTO v_sender_role FROM public.users WHERE id = v_sender_id;
  IF v_sender_role IS NULL THEN RAISE EXCEPTION 'User not found'; END IF;

  SELECT customer_id, driver_id
  INTO v_customer_id, v_driver_profile
  FROM public.ride_requests
  WHERE id = p_ride_id;
  IF v_customer_id IS NULL THEN RAISE EXCEPTION 'Ride not found'; END IF;

  -- Resolve driver profile id → auth user_id
  IF v_driver_profile IS NOT NULL THEN
    SELECT user_id INTO v_driver_user_id
    FROM public.drivers WHERE id = v_driver_profile;
  END IF;

  -- Check caller is customer, driver, or admin
  IF v_sender_role != 'admin'
     AND v_sender_id != v_customer_id
     AND v_sender_id != COALESCE(v_driver_user_id, '00000000-0000-0000-0000-000000000000'::UUID)
  THEN
    RAISE EXCEPTION 'Not authorized to message on this ride';
  END IF;

  -- Build participant list
  v_participant_ids := ARRAY[v_customer_id];
  IF v_driver_user_id IS NOT NULL THEN
    v_participant_ids := v_participant_ids || v_driver_user_id;
  END IF;
  IF NOT v_sender_id = ANY(v_participant_ids) THEN
    v_participant_ids := v_participant_ids || v_sender_id;
  END IF;

  -- Get or create ride conversation
  SELECT id INTO v_conv_id
  FROM public.conversations
  WHERE ride_id = p_ride_id
  LIMIT 1;

  IF v_conv_id IS NULL THEN
    INSERT INTO public.conversations (ride_id, participant_ids)
    VALUES (p_ride_id, v_participant_ids)
    RETURNING id INTO v_conv_id;
  ELSE
    UPDATE public.conversations
    SET participant_ids = (
      SELECT ARRAY(SELECT DISTINCT unnest(participant_ids || v_participant_ids))
    ),
    updated_at = NOW()
    WHERE id = v_conv_id;
  END IF;

  -- Insert message
  INSERT INTO public.chat_messages (
    ride_id, conversation_id, sender_id, sender_role,
    message, message_type, status, metadata
  )
  VALUES (
    p_ride_id, v_conv_id, v_sender_id, v_sender_role,
    p_message, p_message_type, 'sent', p_metadata
  )
  RETURNING id INTO v_msg_id;

  -- Update conversation summary
  UPDATE public.conversations
  SET last_message_text = CASE
        WHEN p_message_type = 'text' THEN p_message
        ELSE '[' || p_message_type || ']'
      END,
      last_message_at = NOW(),
      updated_at = NOW()
  WHERE id = v_conv_id;

  RETURN v_msg_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_ride_message(UUID, TEXT, TEXT, JSONB) TO authenticated;

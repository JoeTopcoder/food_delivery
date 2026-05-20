-- Allow calls to be created for rides (not just food orders).
-- Makes calls.order_id nullable so ride calls can have order_id = NULL,
-- and updates initiate_call to check whether p_order_id is a real order
-- before inserting it (avoids the foreign-key violation for ride IDs).

-- 1. Make order_id nullable (remove NOT NULL, keep FK for valid order IDs)
ALTER TABLE public.calls ALTER COLUMN order_id DROP NOT NULL;

-- 2. Add optional ride_id column so calls can be linked to a ride
ALTER TABLE public.calls ADD COLUMN IF NOT EXISTS ride_id UUID REFERENCES public.ride_requests(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_calls_ride_id ON public.calls(ride_id);

-- 3. Update initiate_call: if p_order_id is not in orders, treat it as a
--    ride_id instead. order_id stays NULL; ride_id is set.
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
  v_caller_id          UUID;
  v_resolved_receiver  UUID;
  v_driver_user_id     UUID;
  v_channel            TEXT;
  v_conv_id            UUID;
  v_call               JSONB;
  v_real_order_id      UUID;
  v_real_ride_id       UUID;
BEGIN
  v_caller_id := auth.uid();
  IF v_caller_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Resolve receiver: driver record ID → user_id, or validate as user
  SELECT d.user_id INTO v_driver_user_id
  FROM public.drivers d WHERE d.id = p_receiver_id;

  IF v_driver_user_id IS NOT NULL THEN
    v_resolved_receiver := v_driver_user_id;
  ELSE
    IF NOT EXISTS (SELECT 1 FROM public.users WHERE id = p_receiver_id) THEN
      RAISE EXCEPTION 'Receiver not found';
    END IF;
    v_resolved_receiver := p_receiver_id;
  END IF;

  IF v_caller_id = v_resolved_receiver THEN
    RAISE EXCEPTION 'Cannot call yourself';
  END IF;

  -- Determine whether p_order_id belongs to orders or ride_requests
  SELECT id INTO v_real_order_id FROM public.orders WHERE id = p_order_id;

  IF v_real_order_id IS NULL THEN
    -- Not a food order — check if it is a ride
    SELECT id INTO v_real_ride_id FROM public.ride_requests WHERE id = p_order_id;
    -- (If it's neither, both stay NULL — call is still created without a link)
  END IF;

  -- Channel name is unique regardless of order/ride
  v_channel := 'call_' || p_order_id::TEXT || '_' || EXTRACT(EPOCH FROM NOW())::BIGINT::TEXT;

  -- Existing conversation (food orders only)
  IF v_real_order_id IS NOT NULL THEN
    SELECT id INTO v_conv_id
    FROM public.conversations
    WHERE order_id = v_real_order_id
    LIMIT 1;
  END IF;

  INSERT INTO public.calls (
    order_id, ride_id, conversation_id,
    caller_id, receiver_id, channel_name, status
  )
  VALUES (
    v_real_order_id, v_real_ride_id, v_conv_id,
    v_caller_id, v_resolved_receiver, v_channel, 'ringing'
  )
  RETURNING to_jsonb(calls.*) INTO v_call;

  RETURN v_call;
END;
$$;

GRANT EXECUTE ON FUNCTION public.initiate_call(UUID, UUID) TO authenticated;

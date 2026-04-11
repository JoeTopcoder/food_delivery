-- ====================================================================
-- 033: Unified Communication System
-- 1. Create conversations table
-- 2. Upgrade chat_messages with message_type, status, conversation_id
-- 3. Create calls table for Agora voice calls
-- 4. Create typing_indicators table
-- 5. RLS policies for all new tables
-- 6. Backfill existing chat_messages into conversations
-- 7. Helper functions
-- ====================================================================

-- 1. Create conversations table
CREATE TABLE IF NOT EXISTS public.conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  participant_ids UUID[] NOT NULL DEFAULT '{}',
  last_message_text TEXT,
  last_message_at TIMESTAMP WITH TIME ZONE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_conversations_order_id ON public.conversations(order_id);
CREATE INDEX IF NOT EXISTS idx_conversations_last_message_at ON public.conversations(last_message_at DESC);
CREATE INDEX IF NOT EXISTS idx_conversations_participant_ids ON public.conversations USING GIN(participant_ids);

-- 2. Add new columns to chat_messages
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS conversation_id UUID REFERENCES public.conversations(id) ON DELETE CASCADE;
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS message_type TEXT NOT NULL DEFAULT 'text' CHECK (message_type IN ('text', 'image', 'system', 'call_event'));
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'delivered', 'seen'));
ALTER TABLE public.chat_messages ADD COLUMN IF NOT EXISTS metadata JSONB DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_chat_messages_conversation_id ON public.chat_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_status ON public.chat_messages(status);

-- 3. Create calls table
CREATE TABLE IF NOT EXISTS public.calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  conversation_id UUID REFERENCES public.conversations(id) ON DELETE SET NULL,
  caller_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  receiver_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  channel_name TEXT NOT NULL,
  agora_token TEXT,
  status TEXT NOT NULL DEFAULT 'ringing' CHECK (status IN ('ringing', 'accepted', 'ended', 'missed', 'declined', 'failed')),
  started_at TIMESTAMP WITH TIME ZONE,
  ended_at TIMESTAMP WITH TIME ZONE,
  duration_seconds INTEGER DEFAULT 0,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_calls_order_id ON public.calls(order_id);
CREATE INDEX IF NOT EXISTS idx_calls_caller_id ON public.calls(caller_id);
CREATE INDEX IF NOT EXISTS idx_calls_receiver_id ON public.calls(receiver_id);
CREATE INDEX IF NOT EXISTS idx_calls_status ON public.calls(status);

-- 4. Create typing_indicators table (ephemeral, cleaned up)
CREATE TABLE IF NOT EXISTS public.typing_indicators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  is_typing BOOLEAN NOT NULL DEFAULT FALSE,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  UNIQUE(conversation_id, user_id)
);

-- 5. Enable RLS on all new tables
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.calls ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.typing_indicators ENABLE ROW LEVEL SECURITY;

-- 6. RLS Policies

-- Conversations: participants + admins can read
DO $$ BEGIN
  DROP POLICY IF EXISTS "conversations_select" ON public.conversations;
  DROP POLICY IF EXISTS "conversations_insert" ON public.conversations;
  DROP POLICY IF EXISTS "conversations_update" ON public.conversations;
END $$;

CREATE POLICY "conversations_select" ON public.conversations
  FOR SELECT USING (
    auth.uid() = ANY(participant_ids)
    OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "conversations_insert" ON public.conversations
  FOR INSERT WITH CHECK (
    auth.uid() = ANY(participant_ids)
    OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "conversations_update" ON public.conversations
  FOR UPDATE USING (
    auth.uid() = ANY(participant_ids)
    OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Calls: caller, receiver, or admin
DO $$ BEGIN
  DROP POLICY IF EXISTS "calls_select" ON public.calls;
  DROP POLICY IF EXISTS "calls_insert" ON public.calls;
  DROP POLICY IF EXISTS "calls_update" ON public.calls;
END $$;

CREATE POLICY "calls_select" ON public.calls
  FOR SELECT USING (
    caller_id = auth.uid()
    OR receiver_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "calls_insert" ON public.calls
  FOR INSERT WITH CHECK (
    caller_id = auth.uid()
  );

CREATE POLICY "calls_update" ON public.calls
  FOR UPDATE USING (
    caller_id = auth.uid()
    OR receiver_id = auth.uid()
  );

-- Typing indicators: conversation participants
DO $$ BEGIN
  DROP POLICY IF EXISTS "typing_select" ON public.typing_indicators;
  DROP POLICY IF EXISTS "typing_upsert" ON public.typing_indicators;
  DROP POLICY IF EXISTS "typing_delete" ON public.typing_indicators;
END $$;

CREATE POLICY "typing_select" ON public.typing_indicators
  FOR SELECT USING (
    conversation_id IN (
      SELECT id FROM public.conversations WHERE auth.uid() = ANY(participant_ids)
    )
  );

CREATE POLICY "typing_upsert" ON public.typing_indicators
  FOR INSERT WITH CHECK (user_id = auth.uid());

CREATE POLICY "typing_delete" ON public.typing_indicators
  FOR DELETE USING (user_id = auth.uid());

-- Allow update on typing indicators by the owner
DO $$ BEGIN
  DROP POLICY IF EXISTS "typing_update" ON public.typing_indicators;
END $$;

CREATE POLICY "typing_update" ON public.typing_indicators
  FOR UPDATE USING (user_id = auth.uid());

-- 7. Enable Realtime on new tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.conversations;
ALTER PUBLICATION supabase_realtime ADD TABLE public.calls;
ALTER PUBLICATION supabase_realtime ADD TABLE public.typing_indicators;

-- Also ensure chat_messages is in realtime (may already be)
DO $$ BEGIN
  ALTER PUBLICATION supabase_realtime ADD TABLE public.chat_messages;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- 8. Function to get or create a conversation for an order
CREATE OR REPLACE FUNCTION public.get_or_create_conversation(
  p_order_id UUID,
  p_participant_ids UUID[]
) RETURNS UUID AS $$
DECLARE
  v_conv_id UUID;
BEGIN
  -- Try to find existing conversation for this order
  SELECT id INTO v_conv_id
  FROM public.conversations
  WHERE order_id = p_order_id
  LIMIT 1;

  -- If not found, create one
  IF v_conv_id IS NULL THEN
    INSERT INTO public.conversations (order_id, participant_ids)
    VALUES (p_order_id, p_participant_ids)
    RETURNING id INTO v_conv_id;
  ELSE
    -- Merge in any new participants
    UPDATE public.conversations
    SET participant_ids = (
      SELECT ARRAY(SELECT DISTINCT unnest(participant_ids || p_participant_ids))
    ),
    updated_at = NOW()
    WHERE id = v_conv_id;
  END IF;

  RETURN v_conv_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 9. Function to send a message (server-validated)
CREATE OR REPLACE FUNCTION public.send_message_secure(
  p_order_id UUID,
  p_message TEXT,
  p_message_type TEXT DEFAULT 'text',
  p_metadata JSONB DEFAULT '{}'
) RETURNS UUID AS $$
DECLARE
  v_sender_id UUID;
  v_sender_role TEXT;
  v_conv_id UUID;
  v_order RECORD;
  v_msg_id UUID;
  v_participant_ids UUID[];
  v_driver_user_id UUID;
BEGIN
  v_sender_id := auth.uid();
  IF v_sender_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  -- Get sender role
  SELECT role INTO v_sender_role FROM public.users WHERE id = v_sender_id;
  IF v_sender_role IS NULL THEN
    RAISE EXCEPTION 'User not found';
  END IF;

  -- Validate order exists and user is a participant
  SELECT o.id, o.user_id, o.driver_id, o.restaurant_id
  INTO v_order
  FROM public.orders o
  WHERE o.id = p_order_id;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Order not found';
  END IF;

  -- Resolve driver_id (drivers table PK) to the driver's user_id
  IF v_order.driver_id IS NOT NULL THEN
    SELECT d.user_id INTO v_driver_user_id FROM public.drivers d WHERE d.id = v_order.driver_id;
  END IF;

  -- Check participation (customer, driver by user_id, restaurant owner, or admin)
  IF v_sender_role != 'admin' AND
     v_sender_id != v_order.user_id AND
     v_sender_id != COALESCE(v_driver_user_id, '00000000-0000-0000-0000-000000000000'::UUID) AND
     NOT EXISTS (
       SELECT 1 FROM public.restaurants
       WHERE id = v_order.restaurant_id AND owner_id = v_sender_id
     )
  THEN
    RAISE EXCEPTION 'Not authorized to message on this order';
  END IF;

  -- Build participant array (use actual user IDs, not driver record IDs)
  v_participant_ids := ARRAY[v_order.user_id];
  IF v_driver_user_id IS NOT NULL THEN
    v_participant_ids := v_participant_ids || v_driver_user_id;
  END IF;
  -- Add restaurant owner
  v_participant_ids := v_participant_ids || (
    SELECT owner_id FROM public.restaurants WHERE id = v_order.restaurant_id
  );
  -- Add sender if not already included
  IF NOT v_sender_id = ANY(v_participant_ids) THEN
    v_participant_ids := v_participant_ids || v_sender_id;
  END IF;

  -- Get or create conversation
  v_conv_id := public.get_or_create_conversation(p_order_id, v_participant_ids);

  -- Insert message
  INSERT INTO public.chat_messages (
    order_id, conversation_id, sender_id, sender_role,
    message, message_type, status, metadata
  )
  VALUES (
    p_order_id, v_conv_id, v_sender_id, v_sender_role,
    p_message, p_message_type, 'sent', p_metadata
  )
  RETURNING id INTO v_msg_id;

  -- Update conversation last message
  UPDATE public.conversations
  SET last_message_text = CASE WHEN p_message_type = 'text' THEN p_message ELSE '[' || p_message_type || ']' END,
      last_message_at = NOW(),
      updated_at = NOW()
  WHERE id = v_conv_id;

  RETURN v_msg_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 10. Function to mark messages as delivered/seen
CREATE OR REPLACE FUNCTION public.mark_messages_status(
  p_conversation_id UUID,
  p_new_status TEXT
) RETURNS VOID AS $$
DECLARE
  v_user_id UUID;
BEGIN
  v_user_id := auth.uid();
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Not authenticated';
  END IF;

  IF p_new_status = 'delivered' THEN
    UPDATE public.chat_messages
    SET status = 'delivered', is_read = FALSE
    WHERE conversation_id = p_conversation_id
      AND sender_id != v_user_id
      AND status = 'sent';
  ELSIF p_new_status = 'seen' THEN
    UPDATE public.chat_messages
    SET status = 'seen', is_read = TRUE
    WHERE conversation_id = p_conversation_id
      AND sender_id != v_user_id
      AND status IN ('sent', 'delivered');
  END IF;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 11. Backfill: create conversations for existing chat_messages
DO $$
DECLARE
  r RECORD;
  v_conv_id UUID;
  v_participants UUID[];
BEGIN
  FOR r IN (
    SELECT DISTINCT order_id FROM public.chat_messages WHERE conversation_id IS NULL
  ) LOOP
    -- Build participants from the order
    SELECT ARRAY_AGG(DISTINCT uid) INTO v_participants
    FROM (
      SELECT user_id AS uid FROM public.orders WHERE id = r.order_id
      UNION
      SELECT driver_id FROM public.orders WHERE id = r.order_id AND driver_id IS NOT NULL
      UNION
      SELECT owner_id FROM public.restaurants
        WHERE id = (SELECT restaurant_id FROM public.orders WHERE id = r.order_id)
    ) sub;

    -- Remove NULLs
    v_participants := ARRAY(SELECT u FROM unnest(v_participants) AS u WHERE u IS NOT NULL);

    IF array_length(v_participants, 1) > 0 THEN
      v_conv_id := public.get_or_create_conversation(r.order_id, v_participants);

      UPDATE public.chat_messages
      SET conversation_id = v_conv_id
      WHERE order_id = r.order_id AND conversation_id IS NULL;

      -- Set conversation's last message
      UPDATE public.conversations
      SET last_message_text = (
        SELECT message FROM public.chat_messages
        WHERE conversation_id = v_conv_id
        ORDER BY created_at DESC LIMIT 1
      ),
      last_message_at = (
        SELECT created_at FROM public.chat_messages
        WHERE conversation_id = v_conv_id
        ORDER BY created_at DESC LIMIT 1
      )
      WHERE id = v_conv_id;
    END IF;
  END LOOP;
END $$;

-- 12. Trigger: auto-update conversation.updated_at when new message
CREATE OR REPLACE FUNCTION public.trg_update_conversation_on_message()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.conversation_id IS NOT NULL THEN
    UPDATE public.conversations
    SET last_message_text = CASE WHEN NEW.message_type = 'text' THEN NEW.message ELSE '[' || NEW.message_type || ']' END,
        last_message_at = NEW.created_at,
        updated_at = NOW()
    WHERE id = NEW.conversation_id;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_chat_msg_update_conv ON public.chat_messages;
CREATE TRIGGER trg_chat_msg_update_conv
  AFTER INSERT ON public.chat_messages
  FOR EACH ROW EXECUTE FUNCTION public.trg_update_conversation_on_message();

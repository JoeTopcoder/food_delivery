-- Fix chat_messages SELECT RLS to include ride participants.
--
-- The original "chat_select_own" policy (migration 029) only checks order_id,
-- so for ride messages (order_id IS NULL) each user could only see their OWN
-- sent messages. The other party's messages were invisible — and Supabase
-- Realtime also applies RLS to change events, so real-time delivery was
-- blocked too.

DROP POLICY IF EXISTS "chat_select_own" ON public.chat_messages;

CREATE POLICY "chat_select_own" ON public.chat_messages
  FOR SELECT USING (
    -- Sender can always read their own messages
    sender_id = auth.uid()

    -- Order chat: customer, driver assigned to the order, or restaurant owner
    OR order_id IN (
      SELECT id FROM public.orders
      WHERE user_id = auth.uid()
         OR driver_id = auth.uid()
         OR restaurant_id IN (
              SELECT id FROM public.restaurants WHERE owner_id = auth.uid()
            )
    )

    -- Ride chat: customer or driver on the ride
    OR (
      ride_id IS NOT NULL
      AND ride_id IN (
        SELECT rr.id
        FROM public.ride_requests rr
        LEFT JOIN public.drivers d ON d.id = rr.driver_id
        WHERE rr.customer_id = auth.uid()
           OR d.user_id = auth.uid()
      )
    )

    -- Admin can read everything
    OR EXISTS (
      SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin'
    )
  );

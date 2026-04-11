-- ====================================================================
-- 029: Fix notifications & messaging
-- 1. Add fcm_token column to users table
-- 2. Create chat_messages table (was missing)
-- 3. Create order_issues table if missing
-- 4. RLS policies for chat_messages and order_issues
-- ====================================================================

-- 1. Add fcm_token to users
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS fcm_token TEXT;

-- 2. Create chat_messages table
CREATE TABLE IF NOT EXISTS public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  sender_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  sender_role TEXT NOT NULL CHECK (sender_role IN ('user', 'driver', 'restaurant', 'admin')),
  message TEXT NOT NULL,
  is_read BOOLEAN DEFAULT FALSE,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_chat_messages_order_id ON public.chat_messages(order_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_sender_id ON public.chat_messages(sender_id);
CREATE INDEX IF NOT EXISTS idx_chat_messages_created_at ON public.chat_messages(created_at);

-- 3. Create order_issues table
CREATE TABLE IF NOT EXISTS public.order_issues (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id UUID NOT NULL REFERENCES public.orders(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  issue_type TEXT NOT NULL,
  description TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'in_review', 'resolved')),
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_order_issues_order_id ON public.order_issues(order_id);
CREATE INDEX IF NOT EXISTS idx_order_issues_user_id ON public.order_issues(user_id);

-- 4. Enable RLS
ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_issues ENABLE ROW LEVEL SECURITY;

-- 5. RLS for chat_messages: participants of the order can read/write
DO $$ BEGIN
  -- Drop existing policies if they exist (idempotent)
  DROP POLICY IF EXISTS "chat_select_own" ON public.chat_messages;
  DROP POLICY IF EXISTS "chat_insert_own" ON public.chat_messages;
  DROP POLICY IF EXISTS "admin_select_all_chat_messages" ON public.chat_messages;
  DROP POLICY IF EXISTS "admin_insert_chat_messages" ON public.chat_messages;
END $$;

-- Users can read chat messages for orders they are part of
CREATE POLICY "chat_select_own" ON public.chat_messages
  FOR SELECT USING (
    sender_id = auth.uid()
    OR order_id IN (
      SELECT id FROM public.orders
      WHERE user_id = auth.uid()
         OR driver_id = auth.uid()
         OR restaurant_id IN (
              SELECT id FROM public.restaurants WHERE owner_id = auth.uid()
            )
    )
    OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

-- Users can insert messages for orders they are part of
CREATE POLICY "chat_insert_own" ON public.chat_messages
  FOR INSERT WITH CHECK (
    sender_id = auth.uid()
    AND (
      order_id IN (
        SELECT id FROM public.orders
        WHERE user_id = auth.uid()
           OR driver_id = auth.uid()
           OR restaurant_id IN (
                SELECT id FROM public.restaurants WHERE owner_id = auth.uid()
              )
      )
      OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
    )
  );

-- 6. RLS for order_issues
DO $$ BEGIN
  DROP POLICY IF EXISTS "issues_select_own" ON public.order_issues;
  DROP POLICY IF EXISTS "issues_insert_own" ON public.order_issues;
END $$;

CREATE POLICY "issues_select_own" ON public.order_issues
  FOR SELECT USING (
    user_id = auth.uid()
    OR EXISTS (SELECT 1 FROM public.users WHERE id = auth.uid() AND role = 'admin')
  );

CREATE POLICY "issues_insert_own" ON public.order_issues
  FOR INSERT WITH CHECK (user_id = auth.uid());

-- 7. Allow users to update their own fcm_token
-- (The existing users update policy should cover this, but make sure)
DO $$ BEGIN
  DROP POLICY IF EXISTS "users_update_own_fcm" ON public.users;
EXCEPTION WHEN undefined_object THEN NULL;
END $$;

CREATE POLICY "users_update_own_fcm" ON public.users
  FOR UPDATE USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

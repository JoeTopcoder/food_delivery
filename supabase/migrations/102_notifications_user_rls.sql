-- Migration 102: Add RLS policies for users to read and update their own notifications
-- Without these, authenticated users cannot SELECT or UPDATE their notification rows.

-- Users can read their own notifications
DO $$ BEGIN
  DROP POLICY IF EXISTS "users_select_own_notifications" ON public.notifications;
END $$;

CREATE POLICY "users_select_own_notifications" ON public.notifications
  FOR SELECT TO authenticated
  USING (auth.uid() = user_id);

-- Users can update their own notifications (e.g. mark is_read = true)
DO $$ BEGIN
  DROP POLICY IF EXISTS "users_update_own_notifications" ON public.notifications;
END $$;

CREATE POLICY "users_update_own_notifications" ON public.notifications
  FOR UPDATE TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

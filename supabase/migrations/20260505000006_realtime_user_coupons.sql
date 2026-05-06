-- Make sure user_coupons is part of the realtime publication so the
-- Flutter home screen can subscribe to live changes (apology banner
-- disappears the moment the order trigger flips is_used=true).
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.user_coupons;
  EXCEPTION WHEN duplicate_object THEN
    -- already a member, ignore
    NULL;
  END;
END$$;

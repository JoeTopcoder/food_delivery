-- Track which mobile platform each user last opened the app on, so admins can
-- see Android vs iOS in the customer list. Written by the client on login/app
-- start (alongside the FCM token). Nullable: populated going forward as users
-- open the app; historical rows stay NULL until their next session.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS device_platform text;
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_device_platform_check;
ALTER TABLE public.users ADD CONSTRAINT users_device_platform_check
  CHECK (device_platform IS NULL OR device_platform IN ('android','ios','web','other'));
NOTIFY pgrst, 'reload schema';

-- iOS VoIP push token (PushKit), separate from fcm_token. The call push goes to
-- this token for iOS so CallKit rings when the app is backgrounded/locked.
ALTER TABLE public.users ADD COLUMN IF NOT EXISTS voip_token text;
NOTIFY pgrst, 'reload schema';

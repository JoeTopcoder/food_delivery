-- Enable Supabase Realtime on app_config so pricing changes
-- are pushed instantly to all connected clients.
ALTER PUBLICATION supabase_realtime ADD TABLE public.app_config;

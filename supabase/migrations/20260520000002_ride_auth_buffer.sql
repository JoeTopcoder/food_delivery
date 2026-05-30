-- Add card authorization buffer percent to ride pricing settings.
-- Default 50 % (1.5×) so the hold covers wait fees and fare overruns.
ALTER TABLE public.ride_pricing_settings
  ADD COLUMN IF NOT EXISTS card_auth_buffer_percent NUMERIC NOT NULL DEFAULT 50;

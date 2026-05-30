-- Add Stripe manual-capture fields to ride_requests.
-- stripe_payment_intent_id : Stripe PI id (pi_xxx) created at booking with capture_method=manual
-- authorized_amount        : amount authorized (estimated_fare × 1.20 buffer)
-- saved_card_id            : FK to saved_cards so the edge function can look up stripe_payment_method_id later

ALTER TABLE public.ride_requests
  ADD COLUMN IF NOT EXISTS stripe_payment_intent_id TEXT,
  ADD COLUMN IF NOT EXISTS authorized_amount         NUMERIC(10, 2),
  ADD COLUMN IF NOT EXISTS saved_card_id             UUID REFERENCES public.saved_cards(id) ON DELETE SET NULL;

-- Fast webhook lookup: "which ride belongs to this PI?"
CREATE INDEX IF NOT EXISTS idx_ride_requests_stripe_pi
  ON public.ride_requests (stripe_payment_intent_id)
  WHERE stripe_payment_intent_id IS NOT NULL;

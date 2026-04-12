-- Add 'verified' status to card_verifications for amount-match confirmation
ALTER TABLE public.card_verifications
  DROP CONSTRAINT IF EXISTS card_verifications_status_check;

ALTER TABLE public.card_verifications
  ADD CONSTRAINT card_verifications_status_check
  CHECK (status IN ('pending', 'completed', 'failed', 'refunded', 'verified'));

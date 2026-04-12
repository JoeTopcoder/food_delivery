-- Add cardholder details to card_verifications so the callback can save them
-- with the card instead of falling back to the users table.
ALTER TABLE public.card_verifications
  ADD COLUMN IF NOT EXISTS cardholder_name TEXT,
  ADD COLUMN IF NOT EXISTS email TEXT,
  ADD COLUMN IF NOT EXISTS phone TEXT;

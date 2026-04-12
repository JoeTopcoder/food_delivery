-- Ensure saved_cards table exists (may be missing on remote)
-- then add status and verification tracking so admin can see
-- all card addition attempts (pending, verified, failed).
-- Users get 10-15 min to verify after charge.

CREATE TABLE IF NOT EXISTS public.saved_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  card_brand TEXT NOT NULL,
  last_four TEXT NOT NULL,
  cardholder_name TEXT NOT NULL DEFAULT '',
  email TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL DEFAULT '',
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_saved_cards_user_id ON public.saved_cards(user_id);

-- RLS
ALTER TABLE public.saved_cards ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saved_cards' AND policyname = 'saved_cards_select') THEN
    CREATE POLICY saved_cards_select ON public.saved_cards FOR SELECT USING (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saved_cards' AND policyname = 'saved_cards_insert') THEN
    CREATE POLICY saved_cards_insert ON public.saved_cards FOR INSERT WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saved_cards' AND policyname = 'saved_cards_update') THEN
    CREATE POLICY saved_cards_update ON public.saved_cards FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (auth.uid() = user_id);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_policies WHERE tablename = 'saved_cards' AND policyname = 'saved_cards_delete') THEN
    CREATE POLICY saved_cards_delete ON public.saved_cards FOR DELETE USING (auth.uid() = user_id);
  END IF;
END $$;

-- Add verification tracking columns
ALTER TABLE public.saved_cards
  ADD COLUMN IF NOT EXISTS status TEXT NOT NULL DEFAULT 'verified',
  ADD COLUMN IF NOT EXISTS verification_id TEXT,
  ADD COLUMN IF NOT EXISTS verification_expires_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS verification_attempts INT NOT NULL DEFAULT 0;

-- Add check constraint for status
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.check_constraints
    WHERE constraint_name = 'saved_cards_status_check'
  ) THEN
    ALTER TABLE public.saved_cards
      ADD CONSTRAINT saved_cards_status_check
      CHECK (status IN ('pending', 'verified', 'failed'));
  END IF;
END $$;

-- Index for quick lookup of pending cards
CREATE INDEX IF NOT EXISTS idx_saved_cards_status ON public.saved_cards(status);
CREATE INDEX IF NOT EXISTS idx_saved_cards_verification_id ON public.saved_cards(verification_id);

-- Saved cards: stores masked card info for reuse (no sensitive data)
CREATE TABLE IF NOT EXISTS saved_cards (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  card_brand TEXT NOT NULL,           -- 'visa', 'mastercard', 'keycard'
  last_four TEXT NOT NULL,            -- last 4 digits only
  cardholder_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT NOT NULL,
  is_default BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_saved_cards_user_id ON saved_cards(user_id);

-- RLS
ALTER TABLE saved_cards ENABLE ROW LEVEL SECURITY;

-- Users can only see/manage their own saved cards
CREATE POLICY saved_cards_select ON saved_cards FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY saved_cards_insert ON saved_cards FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY saved_cards_update ON saved_cards FOR UPDATE
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY saved_cards_delete ON saved_cards FOR DELETE
  USING (auth.uid() = user_id);

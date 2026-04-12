-- Card verification table for small reversible charges to confirm card ownership
CREATE TABLE IF NOT EXISTS public.card_verifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  amount NUMERIC(10,2) NOT NULL DEFAULT 1.00,
  transaction_id TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'completed', 'failed', 'refunded')),
  card_last4 TEXT,
  card_brand TEXT,
  refund_status TEXT DEFAULT 'none' CHECK (refund_status IN ('none', 'pending', 'refunded', 'failed')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ
);

CREATE INDEX idx_card_verifications_user_id ON public.card_verifications(user_id);
CREATE INDEX idx_card_verifications_status ON public.card_verifications(status);

ALTER TABLE public.card_verifications ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users_read_own_verifications" ON public.card_verifications
  FOR SELECT TO authenticated USING (user_id = auth.uid());

GRANT SELECT ON public.card_verifications TO authenticated;
GRANT INSERT, UPDATE ON public.card_verifications TO service_role;

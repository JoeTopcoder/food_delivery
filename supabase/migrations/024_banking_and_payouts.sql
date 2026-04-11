-- ============================================================
-- Banking & Payout System
-- ============================================================

-- 1. Add bank fields to restaurants table
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS bank_name TEXT,
  ADD COLUMN IF NOT EXISTS bank_branch TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_holder TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_type TEXT DEFAULT 'checking',
  ADD COLUMN IF NOT EXISTS total_earnings DOUBLE PRECISION DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_paid_out DOUBLE PRECISION DEFAULT 0;

-- 2. Add bank fields to drivers table (some may already exist in schema.sql)
ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS bank_name TEXT,
  ADD COLUMN IF NOT EXISTS bank_branch TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_number TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_holder TEXT,
  ADD COLUMN IF NOT EXISTS bank_account_type TEXT DEFAULT 'checking',
  ADD COLUMN IF NOT EXISTS total_paid_out DOUBLE PRECISION DEFAULT 0;

-- 3. Payout requests table
CREATE TABLE IF NOT EXISTS public.payout_requests (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  requester_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  requester_type TEXT NOT NULL CHECK (requester_type IN ('driver', 'restaurant')),
  driver_id UUID REFERENCES public.drivers(id),
  restaurant_id UUID REFERENCES public.restaurants(id),
  amount DOUBLE PRECISION NOT NULL CHECK (amount > 0),
  bank_name TEXT NOT NULL,
  bank_branch TEXT,
  bank_account_number TEXT NOT NULL,
  bank_account_holder TEXT NOT NULL,
  bank_account_type TEXT DEFAULT 'checking',
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'processing', 'completed', 'rejected', 'failed')),
  admin_notes TEXT,
  wipay_transaction_id TEXT,
  processed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. Enable RLS
ALTER TABLE public.payout_requests ENABLE ROW LEVEL SECURITY;

-- Users can view their own payout requests
CREATE POLICY "Users can view own payouts"
  ON public.payout_requests FOR SELECT
  USING (requester_id = auth.uid());

-- Users can insert their own payout requests
CREATE POLICY "Users can request payouts"
  ON public.payout_requests FOR INSERT
  WITH CHECK (requester_id = auth.uid());

-- Admin full access (service_role bypasses RLS, but for admin users via app)
CREATE POLICY "Admins can manage all payouts"
  ON public.payout_requests FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.users
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- 5. Index for fast lookups
CREATE INDEX IF NOT EXISTS idx_payout_requests_requester
  ON public.payout_requests(requester_id);
CREATE INDEX IF NOT EXISTS idx_payout_requests_status
  ON public.payout_requests(status);

-- 6. Grant access
GRANT ALL ON public.payout_requests TO authenticated;

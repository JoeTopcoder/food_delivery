-- Contracts table: stores proprietor-client service agreements
CREATE TABLE IF NOT EXISTS public.contracts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  doc_ref TEXT NOT NULL DEFAULT '',
  proprietor_name TEXT NOT NULL DEFAULT 'Innovative Menu Solutions Limited',
  trading_as TEXT NOT NULL DEFAULT '7Krave',
  client_name TEXT NOT NULL DEFAULT '',
  fee_percent NUMERIC(5,2) NOT NULL DEFAULT 10,
  fee_cap_percent NUMERIC(5,2) NOT NULL DEFAULT 5,
  fee_cap_months INTEGER NOT NULL DEFAULT 24,
  support_email TEXT NOT NULL DEFAULT 'support@7krave.com',
  bank_name TEXT NOT NULL DEFAULT '',
  account_number TEXT NOT NULL DEFAULT '',
  account_name TEXT NOT NULL DEFAULT '',
  branch TEXT NOT NULL DEFAULT '',
  account_type TEXT NOT NULL DEFAULT 'Saving',
  restaurant_name TEXT NOT NULL DEFAULT '',
  authorized_personnel TEXT NOT NULL DEFAULT '',
  restaurant_email TEXT NOT NULL DEFAULT '',
  contract_date DATE,
  ceo_name TEXT NOT NULL DEFAULT 'Mr. Rory White',
  ceo_title TEXT NOT NULL DEFAULT 'Chief Executive Officer',
  ceo_company TEXT NOT NULL DEFAULT 'Innovative Menu Solutions Ltd',
  ceo_date DATE,
  status TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('draft','active','terminated')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_contracts_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_contracts_updated_at
  BEFORE UPDATE ON public.contracts
  FOR EACH ROW
  EXECUTE FUNCTION update_contracts_updated_at();

-- RLS: only service_role (edge function) touches this table
ALTER TABLE public.contracts ENABLE ROW LEVEL SECURITY;

-- Admin read access
CREATE POLICY contracts_admin_read ON public.contracts
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.users u
      WHERE u.id = auth.uid() AND u.role = 'admin'
    )
  );

-- Service role has full access by default (bypasses RLS)

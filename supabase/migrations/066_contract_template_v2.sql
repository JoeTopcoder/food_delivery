-- ====================================================================
-- 066: Update contracts table for new partnership agreement template
-- Adds new columns for V2 contract (intro days, commission ranges,
-- payment terms, support phone, termination notice period)
-- ====================================================================

-- New columns for V2 partnership agreement
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS intro_days INTEGER NOT NULL DEFAULT 14;
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS commission_min NUMERIC(5,2) NOT NULL DEFAULT 10;
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS commission_max NUMERIC(5,2) NOT NULL DEFAULT 15;
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS own_driver_commission_min NUMERIC(5,2) NOT NULL DEFAULT 5;
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS own_driver_commission_max NUMERIC(5,2) NOT NULL DEFAULT 10;
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS payment_hours TEXT NOT NULL DEFAULT '24-48';
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS termination_days INTEGER NOT NULL DEFAULT 14;
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS support_phone TEXT NOT NULL DEFAULT '876-305-4847';
ALTER TABLE public.contracts ADD COLUMN IF NOT EXISTS restaurant_id UUID REFERENCES public.restaurants(id) ON DELETE SET NULL;

-- Update defaults for V2 template
ALTER TABLE public.contracts ALTER COLUMN proprietor_name SET DEFAULT 'Joel Scott';
ALTER TABLE public.contracts ALTER COLUMN trading_as SET DEFAULT '';
ALTER TABLE public.contracts ALTER COLUMN support_email SET DEFAULT 'support@applizonecentralja.com';
ALTER TABLE public.contracts ALTER COLUMN ceo_name SET DEFAULT 'Joel Scott';
ALTER TABLE public.contracts ALTER COLUMN ceo_title SET DEFAULT '';
ALTER TABLE public.contracts ALTER COLUMN ceo_company SET DEFAULT '';

-- Index for restaurant_id lookups (restaurant viewing their own contract)
CREATE INDEX IF NOT EXISTS idx_contracts_restaurant_id ON public.contracts(restaurant_id);

-- Allow restaurant owners to read their own contract
CREATE POLICY contracts_restaurant_read ON public.contracts
  FOR SELECT USING (
    restaurant_id IN (
      SELECT id FROM public.restaurants WHERE owner_id = auth.uid()
    )
  );

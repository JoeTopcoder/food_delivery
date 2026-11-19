-- Cooking Gas — supplier display fields for the redesigned customer UI.
ALTER TABLE public.gas_suppliers
  ADD COLUMN IF NOT EXISTS rating       numeric(2,1) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS total_orders int          NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS hours_label  text,
  ADD COLUMN IF NOT EXISTS eta_label    text,
  ADD COLUMN IF NOT EXISTS banner_url   text;

UPDATE public.gas_suppliers SET rating=4.7, total_orders=320, hours_label='8:00 AM - 8:00 PM', eta_label='~45 min - 1 hr'
  WHERE business_name='Portmore Gas Express';
UPDATE public.gas_suppliers SET rating=4.6, total_orders=210, hours_label='8:00 AM - 9:00 PM', eta_label='~40 min - 1 hr'
  WHERE business_name='Kingston LPG Depot';
UPDATE public.gas_suppliers SET rating=4.5, total_orders=180, hours_label='7:00 AM - 8:00 PM', eta_label='~50 min - 1.5 hr'
  WHERE business_name='Half Way Tree Cylinder Co';

NOTIFY pgrst, 'reload schema';

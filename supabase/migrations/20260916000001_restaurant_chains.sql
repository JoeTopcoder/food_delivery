-- Multi-location chains: restaurants sharing a chain_id are shown to customers
-- as ONE store (the nearest branch), displayed under chain_name. Ordering
-- routes to whichever branch is shown (the nearest).
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS chain_id text,
  ADD COLUMN IF NOT EXISTS chain_name text;

UPDATE restaurants SET chain_id='kfc', chain_name='KFC' WHERE name ILIKE 'KFC%';
UPDATE restaurants SET chain_id='island-grill', chain_name='Island Grill' WHERE name ILIKE 'Island Grill%';
UPDATE restaurants SET chain_id='popeyes', chain_name='Popeyes' WHERE name ILIKE 'Popeyes%';

NOTIFY pgrst, 'reload schema';

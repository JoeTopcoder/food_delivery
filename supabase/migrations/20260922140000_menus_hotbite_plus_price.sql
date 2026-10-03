-- Item-level HotBite+ member pricing. A store sets an optional second price on
-- a menu item / grocery product; active members pay it instead of the regular
-- price. Covers both restaurants and supermarkets (both use public.menus).
ALTER TABLE public.menus ADD COLUMN IF NOT EXISTS hotbite_plus_price numeric;
COMMENT ON COLUMN public.menus.hotbite_plus_price IS
  'Optional HotBite+ member price. When set (and below the regular price), active members pay this instead of price.';
NOTIFY pgrst, 'reload schema';

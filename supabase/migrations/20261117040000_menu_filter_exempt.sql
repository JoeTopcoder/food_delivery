-- Per-item exemption from the menu word filter. The word list matches on name +
-- category, which produces false positives in a supermarket catalogue: Scotch-
-- Brite sponges ("scotch"), Scotch Bonnet pepper ("scotch"), rum cake / rum &
-- raisin ice cream ("rum"), ginger beer & kola champagne sodas ("beer"/"champagne"),
-- apple cider vinegar ("cider"), fruit cocktail & cocktail peanuts ("cocktail"),
-- non-alcoholic sparkling grape drinks ("wine"), bourbon cream biscuits ("bourbon"),
-- red wine vinegar ("wine"), etc. — all non-alcoholic.
--
-- `filter_exempt` lets an owner/admin mark a specific product as never-filtered,
-- regardless of word matches. It overrides the word match in both the trigger and
-- the bulk recompute.

ALTER TABLE public.menus
  ADD COLUMN IF NOT EXISTS filter_exempt boolean NOT NULL DEFAULT false;

-- Trigger now honours the exemption.
CREATE OR REPLACE FUNCTION public.set_menu_is_filtered()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  NEW.is_filtered := (NOT COALESCE(NEW.filter_exempt, false))
    AND public.compute_menu_filtered(NEW.name, NEW.category, NEW.description);
  RETURN NEW;
END;
$$;

-- Re-fire the trigger when the exemption itself is toggled.
DROP TRIGGER IF EXISTS trg_menus_set_filtered ON public.menus;
CREATE TRIGGER trg_menus_set_filtered
  BEFORE INSERT OR UPDATE OF name, category, description, filter_exempt ON public.menus
  FOR EACH ROW EXECUTE FUNCTION public.set_menu_is_filtered();

-- Bulk recompute honours the exemption too.
CREATE OR REPLACE FUNCTION public.recompute_menus_is_filtered()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  UPDATE public.menus m
     SET is_filtered = (NOT COALESCE(m.filter_exempt, false))
       AND public.compute_menu_filtered(m.name, m.category, m.description)
   WHERE m.is_filtered IS DISTINCT FROM (
       (NOT COALESCE(m.filter_exempt, false))
       AND public.compute_menu_filtered(m.name, m.category, m.description)
     );
END;
$$;

-- Exempt the non-alcoholic false positives: every currently-filtered grocery item
-- that is NOT in a genuine alcohol category (Liquor / Beer), minus the three real
-- alcohol strays that happen to sit in other categories.
UPDATE public.menus
   SET filter_exempt = true
 WHERE product_type = 'grocery'
   AND is_filtered = true
   AND category NOT IN ('Liquor', 'Beer')
   AND name NOT ILIKE '%fruit wine%'   -- CALS FRUIT WINE (real)
   AND name NOT ILIKE 'RUM BAR RUM%'   -- RUM BAR RUM (real)
   AND name NOT ILIKE 'RUFF RIDER%';   -- RUFF RIDER POWER BLEND RUM (real)

-- Non-alcoholic sparkling grape juices the store miscategorised under "Liquor"
-- (Chamdor, May Sparkling Fruit Juice). Andre / Korbel in the same category are
-- real sparkling wine and stay hidden.
UPDATE public.menus
   SET filter_exempt = true
 WHERE product_type = 'grocery'
   AND category = 'Liquor'
   AND (name ILIKE 'CHAMDOR%' OR name ILIKE 'MAY SPARKLING FRUIT JUICE%');

-- The UPDATEs above fire the trigger (filter_exempt changed), so is_filtered is
-- already recomputed for those rows. A full sweep keeps everything consistent.
SELECT public.recompute_menus_is_filtered();

NOTIFY pgrst, 'reload schema';

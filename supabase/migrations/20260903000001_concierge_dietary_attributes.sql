-- Migration: structured dietary/flavour attributes for the AI Food Concierge
--
-- The concierge has to answer requests like "spicy, no pork, under $30, here by
-- 7". Today none of that is answerable from structured data: spice_level is
-- populated on 0 of 211 items, there is no pork column at all, and
-- is_vegetarian is true on only 10 rows. The only signal is free-text
-- description, which means keyword guessing.
--
-- Guessing is fine for "spicy" and NOT fine for "no pork" — that is usually a
-- religious or medical constraint, and a confident wrong answer is worse than
-- no answer. So the attributes become real columns, classified once, and every
-- concierge query becomes an indexed SQL filter instead of an LLM judgement
-- call. Restaurants can correct any row, and corrections outrank the AI.
--
-- Provenance is the important part: dietary_source records WHO asserted each
-- row. The concierge is required to treat 'ai' as advisory (it must surface a
-- caveat) and 'restaurant' as authoritative. An unclassified row is never
-- silently treated as safe.

-- ── Allergen / dietary flags ────────────────────────────────────────────────
-- Deliberately nullable with no default: NULL means "nobody has said", which is
-- different from FALSE ("confirmed absent"). Defaulting these to false would
-- silently mark all 211 existing items pork-free, which is exactly the failure
-- this migration exists to prevent.
ALTER TABLE public.menus
  ADD COLUMN IF NOT EXISTS contains_pork      BOOLEAN,
  ADD COLUMN IF NOT EXISTS contains_shellfish BOOLEAN,
  ADD COLUMN IF NOT EXISTS contains_beef      BOOLEAN,
  ADD COLUMN IF NOT EXISTS contains_dairy     BOOLEAN,
  ADD COLUMN IF NOT EXISTS contains_egg       BOOLEAN,
  ADD COLUMN IF NOT EXISTS contains_alcohol   BOOLEAN,
  ADD COLUMN IF NOT EXISTS is_halal           BOOLEAN,
  ADD COLUMN IF NOT EXISTS is_kosher          BOOLEAN;

-- ── Flavour profile ─────────────────────────────────────────────────────────
-- spice_level already exists as free text and is entirely unpopulated; a
-- numeric scale is what "something spicy" actually needs to filter and rank on.
-- 0 = not spicy … 4 = very hot. Left NULL when unknown.
ALTER TABLE public.menus
  ADD COLUMN IF NOT EXISTS spice_rating SMALLINT
    CHECK (spice_rating IS NULL OR spice_rating BETWEEN 0 AND 4),
  ADD COLUMN IF NOT EXISTS flavor_tags TEXT[];

-- ── Provenance ──────────────────────────────────────────────────────────────
ALTER TABLE public.menus
  ADD COLUMN IF NOT EXISTS dietary_source TEXT
    CHECK (dietary_source IS NULL OR dietary_source IN ('ai','restaurant','admin')),
  ADD COLUMN IF NOT EXISTS dietary_classified_at TIMESTAMPTZ;

COMMENT ON COLUMN public.menus.dietary_source IS
  'Who asserted the dietary flags: ai (inferred, advisory only — the concierge '
  'must caveat it), restaurant or admin (authoritative). NULL = unclassified; '
  'never treat as safe.';
COMMENT ON COLUMN public.menus.contains_pork IS
  'NULL means unknown, not absent. Exclusion filters must reject NULL as well '
  'as TRUE when the customer asks for no pork.';

-- ── Indexes for the concierge''s hot filter path ────────────────────────────
CREATE INDEX IF NOT EXISTS idx_menus_concierge_filter
  ON public.menus (restaurant_id, is_available)
  WHERE is_available;

CREATE INDEX IF NOT EXISTS idx_menus_spice_rating
  ON public.menus (spice_rating) WHERE spice_rating IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_menus_flavor_tags
  ON public.menus USING GIN (flavor_tags);

-- ── Restaurant price tier ───────────────────────────────────────────────────
-- The contract filters on max_price_tier 1-4. Derived from the restaurant's own
-- median item price rather than stored by hand, so it can't drift from the menu.
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS price_tier SMALLINT
    CHECK (price_tier IS NULL OR price_tier BETWEEN 1 AND 4);

CREATE OR REPLACE FUNCTION public.refresh_restaurant_price_tiers()
RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE public.restaurants r
  SET    price_tier = t.tier
  FROM (
    SELECT m.restaurant_id,
           CASE
             WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY m.price) <  10 THEN 1
             WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY m.price) <  20 THEN 2
             WHEN percentile_cont(0.5) WITHIN GROUP (ORDER BY m.price) <  35 THEN 3
             ELSE 4
           END AS tier
    FROM   public.menus m
    WHERE  m.is_available
    GROUP  BY m.restaurant_id
  ) t
  WHERE r.id = t.restaurant_id;
$$;

SELECT public.refresh_restaurant_price_tiers();

NOTIFY pgrst, 'reload schema';

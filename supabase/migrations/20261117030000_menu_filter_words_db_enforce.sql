-- Enforce the admin menu_filter_words list in the DATABASE (not just the app),
-- so filtered items (alcohol, etc.) are hidden from customers for BOTH restaurant
-- menus AND grocery products — immediately, with no app rebuild — while store
-- owners and admins still see everything.
--
-- Design: a fast boolean column `menus.is_filtered`, kept current by a trigger on
-- every insert/update of name/category/description, and recomputed wholesale when
-- an admin edits the word list. RLS then does a cheap boolean check (no per-row
-- regex), so large grocery catalogues stay fast.

-- 1. Whole-word, case-insensitive match against the configured word list.
--    Mirrors lib/utils/menu_filter.dart: a word boundary is any non-alphanumeric
--    char, so "wine" hides "Red Wine" but not "winery"… and "cocktail" hides a
--    whole "Signature Cocktails" category.
CREATE OR REPLACE FUNCTION public.compute_menu_filtered(
  p_name text, p_category text, p_description text
) RETURNS boolean
LANGUAGE plpgsql
STABLE
SET search_path TO 'public', 'pg_temp'
AS $$
DECLARE
  v_words text;
  v_word  text;
  v_hay   text;
BEGIN
  SELECT value INTO v_words FROM public.app_config WHERE key = 'menu_filter_words';
  IF v_words IS NULL OR btrim(v_words) = '' THEN
    RETURN false;
  END IF;
  v_hay := lower(
    coalesce(p_name, '') || ' ' || coalesce(p_category, '') || ' ' || coalesce(p_description, '')
  );
  FOREACH v_word IN ARRAY string_to_array(v_words, ',') LOOP
    v_word := btrim(lower(v_word));
    IF v_word = '' THEN CONTINUE; END IF;
    -- Escape any regex metacharacters in the word, then require a non-alphanumeric
    -- (or string edge) on both sides.
    IF v_hay ~ ('(^|[^a-z0-9])' || regexp_replace(v_word, '([^a-z0-9])', '\\\1', 'g') || '([^a-z0-9]|$)')
    THEN
      RETURN true;
    END IF;
  END LOOP;
  RETURN false;
END;
$$;

-- 2. Column + per-row trigger.
ALTER TABLE public.menus
  ADD COLUMN IF NOT EXISTS is_filtered boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.set_menu_is_filtered()
RETURNS trigger
LANGUAGE plpgsql
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  NEW.is_filtered := public.compute_menu_filtered(NEW.name, NEW.category, NEW.description);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_menus_set_filtered ON public.menus;
CREATE TRIGGER trg_menus_set_filtered
  BEFORE INSERT OR UPDATE OF name, category, description ON public.menus
  FOR EACH ROW EXECUTE FUNCTION public.set_menu_is_filtered();

-- 3. Recompute everything (used for the backfill and whenever the word list changes).
CREATE OR REPLACE FUNCTION public.recompute_menus_is_filtered()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  UPDATE public.menus m
     SET is_filtered = public.compute_menu_filtered(m.name, m.category, m.description)
   WHERE m.is_filtered IS DISTINCT FROM
         public.compute_menu_filtered(m.name, m.category, m.description);
END;
$$;

-- 4. When an admin saves a new word list (app_config.menu_filter_words), recompute.
CREATE OR REPLACE FUNCTION public.app_config_menu_filter_changed()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $$
BEGIN
  IF NEW.key = 'menu_filter_words'
     AND (TG_OP = 'INSERT' OR NEW.value IS DISTINCT FROM OLD.value) THEN
    PERFORM public.recompute_menus_is_filtered();
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_app_config_menu_filter ON public.app_config;
CREATE TRIGGER trg_app_config_menu_filter
  AFTER INSERT OR UPDATE ON public.app_config
  FOR EACH ROW
  WHEN (NEW.key = 'menu_filter_words')
  EXECUTE FUNCTION public.app_config_menu_filter_changed();

-- 5. Backfill existing rows.
SELECT public.recompute_menus_is_filtered();

-- 6. Hide filtered items from customers at the RLS layer. The owner/admin branches
--    are untouched, so they still see everything. Only the public branch gains the
--    extra "AND not filtered" condition.
ALTER POLICY public_read_menus ON public.menus
  USING (
    (
      (COALESCE(is_available, true) = true AND COALESCE(is_filtered, false) = false)
      OR current_user_owns_restaurant(restaurant_id)
      OR current_user_is_admin()
    )
  );

NOTIFY pgrst, 'reload schema';

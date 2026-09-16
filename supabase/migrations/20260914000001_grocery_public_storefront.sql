-- Grocery white-label storefront masking.
-- Partner grocery stores keep their real name for admin / owner / driver, but
-- customers only ever see a public brand ("Quickdash Groceries") or a per-store
-- public alias. This adds the customer-facing override columns + the global
-- brand fallback. Nothing here changes store identity, orders, or routing.

ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS public_name text,
  ADD COLUMN IF NOT EXISTS public_image_url text;

COMMENT ON COLUMN public.restaurants.public_name IS
  'Customer-facing storefront alias for grocery stores. When set, customers see this instead of the real name. NULL falls back to app_config grocery_public_brand. Admin/owner/driver always see the real name.';
COMMENT ON COLUMN public.restaurants.public_image_url IS
  'Customer-facing storefront logo/banner for grocery stores. NULL hides the real image and the app shows the default Quickdash grocery logo.';

-- Global fallback brand shown when a grocery store has no public_name set.
INSERT INTO public.app_config (key, value, value_type, category, description)
VALUES ('grocery_public_brand', 'Quickdash Groceries', 'string', 'branding',
        'Customer-facing brand name shown for every grocery store that has no per-store public_name alias.')
ON CONFLICT (key) DO NOTHING;

NOTIFY pgrst, 'reload schema';

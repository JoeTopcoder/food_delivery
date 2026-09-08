-- Migration: repaint the app — Cobalt Blue + Coral.
--
-- app_theme row 1 is what the running app actually loads; the Dart defaults and
-- the edge function's DEFAULT_THEME are only fallbacks for when this is
-- unreachable. All three are updated together, because a palette that differs
-- between them shows up as the app changing colour when the network drops.
--
-- Blue carries the technology, payment and delivery side. Coral carries
-- appetite, and is deliberately also the price colour.

UPDATE public.app_theme
   SET colors = jsonb_build_object(
         'primaryColor',    '#155EEF',   -- Cobalt Blue
         'secondaryColor',  '#0B1220',   -- Midnight Navy
         'accentColor',     '#FF6B5A',   -- Coral
         'backgroundColor', '#F8FAFC',   -- Soft White
         'errorColor',      '#D92D20',
         'successColor',    '#12B76A',   -- Emerald
         'warningColor',    '#F79009',
         'priceColor',      '#FF6B5A',   -- Coral
         'textPrimary',     '#101828',   -- Charcoal
         'textSecondary',   '#475467',
         'textLight',       '#667085',
         'borderColor',     '#EAECF0',
         'dividerColor',    '#F2F4F7'
       ),
       updated_at = now()
 WHERE id = 1;

NOTIFY pgrst, 'reload schema';

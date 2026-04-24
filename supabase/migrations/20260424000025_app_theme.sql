-- app_theme table: stores remotely-configurable color palette
-- Admins can update colors from the dashboard without a new app release.

CREATE TABLE IF NOT EXISTS public.app_theme (
  id          INT PRIMARY KEY DEFAULT 1,  -- singleton row
  colors      JSONB NOT NULL DEFAULT '{}'::JSONB,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT  app_theme_singleton CHECK (id = 1)
);

-- Seed the default palette matching the current AppTheme constants
INSERT INTO public.app_theme (id, colors)
VALUES (1, '{
  "primaryColor":       "#7C3AED",
  "secondaryColor":     "#004E89",
  "accentColor":        "#E74C3C",
  "backgroundColor":    "#F7F8FA",
  "errorColor":         "#E63946",
  "successColor":       "#06A77D",
  "warningColor":       "#FFA630",
  "priceColor":         "#E74C3C",
  "textPrimary":        "#111827",
  "textSecondary":      "#374151",
  "textLight":          "#4B5563",
  "borderColor":        "#E5E7EB",
  "dividerColor":       "#F3F4F6"
}'::JSONB)
ON CONFLICT (id) DO NOTHING;

-- Allow authenticated users (and anon) to read the theme
ALTER TABLE public.app_theme ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anyone can read theme" ON public.app_theme
  FOR SELECT USING (true);

CREATE POLICY "service role can update theme" ON public.app_theme
  FOR ALL USING (auth.role() = 'service_role');

-- Grant read to anon + authenticated
GRANT SELECT ON public.app_theme TO anon, authenticated;

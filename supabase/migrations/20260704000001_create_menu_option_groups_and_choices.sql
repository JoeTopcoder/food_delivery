-- Creates menu_option_groups and menu_option_choices tables for item
-- size/flavour/variant selection on the restaurant menu screen.

CREATE TABLE IF NOT EXISTS public.menu_option_groups (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  menu_item_id   UUID NOT NULL REFERENCES public.menu_items(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,
  is_required    BOOLEAN NOT NULL DEFAULT false,
  max_selections INTEGER NOT NULL DEFAULT 1,
  sort_order     INTEGER NOT NULL DEFAULT 0,
  is_mock_data   BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.menu_option_choices (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_id     UUID NOT NULL REFERENCES public.menu_option_groups(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,
  price        NUMERIC(10,2) NOT NULL DEFAULT 0,
  is_available BOOLEAN NOT NULL DEFAULT true,
  sort_order   INTEGER NOT NULL DEFAULT 0,
  is_mock_data BOOLEAN NOT NULL DEFAULT false,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Indexes for common joins
CREATE INDEX IF NOT EXISTS menu_option_groups_menu_item_id_idx
  ON public.menu_option_groups (menu_item_id);

CREATE INDEX IF NOT EXISTS menu_option_choices_group_id_idx
  ON public.menu_option_choices (group_id);

-- Row-Level Security
ALTER TABLE public.menu_option_groups ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.menu_option_choices ENABLE ROW LEVEL SECURITY;

-- Customers and the app can read all option groups and choices
CREATE POLICY "menu_option_groups_select_all"
  ON public.menu_option_groups FOR SELECT USING (true);

CREATE POLICY "menu_option_choices_select_all"
  ON public.menu_option_choices FOR SELECT USING (true);

-- Only service_role (admin panel / backend) may write
CREATE POLICY "menu_option_groups_service_role_all"
  ON public.menu_option_groups FOR ALL TO service_role USING (true);

CREATE POLICY "menu_option_choices_service_role_all"
  ON public.menu_option_choices FOR ALL TO service_role USING (true);

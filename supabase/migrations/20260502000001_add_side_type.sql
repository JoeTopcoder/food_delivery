-- Add side_type column to menu_item_sides to differentiate sides vs drinks.
-- Idempotent: safe to re-run.

ALTER TABLE public.menu_item_sides
  ADD COLUMN IF NOT EXISTS side_type TEXT NOT NULL DEFAULT 'side';

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'menu_item_sides_side_type_check'
  ) THEN
    ALTER TABLE public.menu_item_sides
      ADD CONSTRAINT menu_item_sides_side_type_check
      CHECK (side_type IN ('side', 'drink'));
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_menu_item_sides_side_type
  ON public.menu_item_sides(side_type);

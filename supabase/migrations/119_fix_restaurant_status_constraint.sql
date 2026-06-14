-- Drop the old growth-check constraint that only allows ('draft','active')
-- and replace with the full lifecycle set.
ALTER TABLE public.restaurants
  DROP CONSTRAINT IF EXISTS restaurants_status_growth_check;

-- Ensure the full lifecycle constraint exists (idempotent)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'restaurants_status_check'
  ) THEN
    ALTER TABLE public.restaurants
      ADD CONSTRAINT restaurants_status_check
        CHECK (status IN ('draft', 'pending_review', 'under_review', 'approved', 'rejected'));
  END IF;
END $$;

-- Extend package_records to store tracking data returned from shipping company APIs.
-- tracking_number already exists (NOT NULL); we relax it to nullable so that
-- packages can be created before the external API returns the official number.
-- A partial unique index keeps the original guarantee for non-empty values.

ALTER TABLE public.package_records
  ALTER COLUMN tracking_number DROP NOT NULL,
  ALTER COLUMN tracking_number SET DEFAULT NULL;

-- Replace the table-level UNIQUE constraint with a partial index on non-null values.
ALTER TABLE public.package_records
  DROP CONSTRAINT IF EXISTS package_records_shipping_company_id_tracking_number_key;

CREATE UNIQUE INDEX IF NOT EXISTS pkg_records_company_tracking_unique
  ON public.package_records (shipping_company_id, tracking_number)
  WHERE tracking_number IS NOT NULL AND tracking_number <> '';

-- New tracking columns.
ALTER TABLE public.package_records
  ADD COLUMN IF NOT EXISTS tracking_url             text,
  ADD COLUMN IF NOT EXISTS external_shipment_id     text,
  ADD COLUMN IF NOT EXISTS tracking_status          text NOT NULL DEFAULT 'tracking_pending'
      CHECK (tracking_status IN ('tracking_pending','tracking_active','tracking_error','tracking_delivered')),
  ADD COLUMN IF NOT EXISTS tracking_last_synced_at  timestamptz,
  ADD COLUMN IF NOT EXISTS tracking_error_message   text;

-- Existing rows that already have a tracking_number → mark as active.
UPDATE public.package_records
  SET tracking_status = 'tracking_active'
  WHERE tracking_number IS NOT NULL AND tracking_number <> ''
    AND tracking_status = 'tracking_pending';

-- webhook_endpoint and api_key were added in migration 20260514000005; ensure they exist.
ALTER TABLE public.shipping_companies
  ADD COLUMN IF NOT EXISTS webhook_endpoint  text,
  ADD COLUMN IF NOT EXISTS api_key           text;

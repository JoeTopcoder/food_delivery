-- Add webhook_endpoint and api_key columns to shipping_companies.
-- webhook_endpoint: URL we POST events to (or receive from company).
-- api_key: auth key for calling the company's verification API.
ALTER TABLE public.shipping_companies
  ADD COLUMN IF NOT EXISTS webhook_endpoint  text,
  ADD COLUMN IF NOT EXISTS api_key           text,
  ADD COLUMN IF NOT EXISTS logo_url          text; -- ensure exists (was in seed but not schema)

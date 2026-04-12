-- Fix card_verifications.id column: change from uuid to text
-- so it can store orderId values like "verify-card-1776020386988"

-- Drop existing primary key constraint
ALTER TABLE card_verifications DROP CONSTRAINT IF EXISTS card_verifications_pkey;

-- Change id column from uuid to text
ALTER TABLE card_verifications ALTER COLUMN id SET DATA TYPE text USING id::text;

-- Re-add primary key
ALTER TABLE card_verifications ADD PRIMARY KEY (id);

-- Add cash_float column to drivers table
-- Tracks money collected from cash orders that driver owes back to the platform
ALTER TABLE drivers ADD COLUMN IF NOT EXISTS cash_float DOUBLE PRECISION DEFAULT 0;

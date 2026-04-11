-- Migration 022: Add driver rating and tip columns to orders
ALTER TABLE orders
ADD COLUMN IF NOT EXISTS driver_rating INTEGER CHECK (driver_rating >= 1 AND driver_rating <= 5),
ADD COLUMN IF NOT EXISTS driver_tip DOUBLE PRECISION DEFAULT 0;

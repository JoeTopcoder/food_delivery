-- Migration 026: Add commission system and per-day operating hours
-- Adds commission_rate to restaurants, operating_hours JSONB for daily schedules,
-- and commission_amount/platform_fee to orders.

-- ── Restaurants: commission rate and operating hours ──────────────────────────
ALTER TABLE restaurants
  ADD COLUMN IF NOT EXISTS commission_rate DOUBLE PRECISION DEFAULT 0.15,
  ADD COLUMN IF NOT EXISTS operating_hours JSONB DEFAULT '{
    "monday":    {"open": "08:00", "close": "22:00", "is_open": true},
    "tuesday":   {"open": "08:00", "close": "22:00", "is_open": true},
    "wednesday": {"open": "08:00", "close": "22:00", "is_open": true},
    "thursday":  {"open": "08:00", "close": "22:00", "is_open": true},
    "friday":    {"open": "08:00", "close": "22:00", "is_open": true},
    "saturday":  {"open": "09:00", "close": "23:00", "is_open": true},
    "sunday":    {"open": "09:00", "close": "21:00", "is_open": true}
  }'::jsonb;

-- ── Orders: commission tracking ──────────────────────────────────────────────
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS commission_amount DOUBLE PRECISION DEFAULT 0,
  ADD COLUMN IF NOT EXISTS commission_rate DOUBLE PRECISION DEFAULT 0;

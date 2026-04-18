-- Migration 072: Add receipt_emailed_at column to orders
-- Tracks when a receipt email was sent to the customer

ALTER TABLE public.orders ADD COLUMN IF NOT EXISTS receipt_emailed_at TIMESTAMPTZ;

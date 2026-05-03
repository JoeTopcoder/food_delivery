-- Migration: Enable RLS and allow authenticated user inserts on users table
-- Date: 2026-04-28

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated can insert own user"
  ON public.users
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = id);

-- Allow customers to read their own payment records while keeping writes
-- on the server via Supabase Edge Functions.

GRANT USAGE ON SCHEMA public TO authenticated;
GRANT SELECT ON public.payments TO authenticated;

ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "users_select_own_payments" ON public.payments;

CREATE POLICY "users_select_own_payments"
ON public.payments
FOR SELECT
TO authenticated
USING (user_id = auth.uid());
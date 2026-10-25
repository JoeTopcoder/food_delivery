-- Zero out restaurant commission platform-wide and make 0 the default for any
-- newly created restaurant (was 0.15). Applied live via supabase db query.
UPDATE restaurants SET commission_rate = 0, updated_at = now()
WHERE commission_rate IS DISTINCT FROM 0;

ALTER TABLE restaurants ALTER COLUMN commission_rate SET DEFAULT 0;

NOTIFY pgrst, 'reload schema';

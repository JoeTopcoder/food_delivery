-- Migration: fix the default-address trigger to run BEFORE insert.
--
-- 20260908000006 used an AFTER INSERT trigger to demote the previous default.
-- Too late: idx_user_addresses_one_default_per_user is a partial unique index
-- on (user_id) WHERE is_default, and it rejects the row before any AFTER
-- trigger runs. Saving a new address and asking for it to be the default
-- failed outright with a duplicate-key error.
--
-- A BEFORE trigger can demote the siblings first, and can set the flag on NEW
-- directly instead of issuing a second UPDATE.
--
-- The index already guaranteed AT MOST one default. What was missing, and what
-- this adds, is AT LEAST one.

DROP TRIGGER IF EXISTS trg_address_first_default ON public.user_addresses;
DROP FUNCTION IF EXISTS public.address_first_becomes_default();

CREATE OR REPLACE FUNCTION public.address_default_before_insert()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.is_default THEN
    -- Asked to be the default: clear the old one before the unique index sees
    -- two of them.
    UPDATE public.user_addresses
       SET is_default = FALSE
     WHERE user_id = NEW.user_id AND is_default;
  ELSIF NOT EXISTS (
    SELECT 1 FROM public.user_addresses
    WHERE user_id = NEW.user_id AND is_default
  ) THEN
    -- Nothing is the default yet, so this is. Set on NEW, which costs no
    -- second write and cannot race the index.
    NEW.is_default := TRUE;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_address_default_before_insert
BEFORE INSERT ON public.user_addresses
FOR EACH ROW EXECUTE FUNCTION public.address_default_before_insert();

NOTIFY pgrst, 'reload schema';

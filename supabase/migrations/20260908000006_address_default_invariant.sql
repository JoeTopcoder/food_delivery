-- Migration: every customer always has exactly one default address.
--
-- Not one user in the database had a default set. selectedAddressProvider falls
-- back to "whichever row came first", so the app picked arbitrarily — and with
-- distance filtering live that is no longer cosmetic. One test account's first
-- row was in Grand Cayman, so the app hid every Jamaican restaurant and showed
-- Caymanian ones. It was right to; it was just asked the wrong question.
--
-- Enforced with triggers rather than in the app because several paths write
-- this table (address book, checkout, the map picker, admin), and an invariant
-- that depends on every caller remembering is not an invariant.

-- ── On insert: the first address a user saves becomes their default ─────────
CREATE OR REPLACE FUNCTION public.address_first_becomes_default()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.is_default THEN
    -- Explicitly marked default: demote the others.
    UPDATE public.user_addresses
       SET is_default = FALSE
     WHERE user_id = NEW.user_id AND id <> NEW.id AND is_default;
  ELSIF NOT EXISTS (
    SELECT 1 FROM public.user_addresses
    WHERE user_id = NEW.user_id AND id <> NEW.id AND is_default
  ) THEN
    -- No default exists yet, so this one becomes it.
    UPDATE public.user_addresses SET is_default = TRUE WHERE id = NEW.id;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_address_first_default ON public.user_addresses;
CREATE TRIGGER trg_address_first_default
AFTER INSERT ON public.user_addresses
FOR EACH ROW EXECUTE FUNCTION public.address_first_becomes_default();

-- ── On delete: deleting the default promotes the newest survivor ────────────
-- Without this, deleting your default drops you back to no default at all and
-- the app resumes guessing.
CREATE OR REPLACE FUNCTION public.address_promote_after_delete()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF OLD.is_default THEN
    UPDATE public.user_addresses
       SET is_default = TRUE
     WHERE id = (
       SELECT id FROM public.user_addresses
       WHERE user_id = OLD.user_id
       ORDER BY created_at DESC
       LIMIT 1
     );
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_address_promote_after_delete ON public.user_addresses;
CREATE TRIGGER trg_address_promote_after_delete
AFTER DELETE ON public.user_addresses
FOR EACH ROW EXECUTE FUNCTION public.address_promote_after_delete();

-- ── Backfill ───────────────────────────────────────────────────────────────
-- The newest address is the best available guess at where someone lives now.
-- It is a guess: a customer whose newest address is stale can still change it,
-- and the app makes the active one visible so they can tell.
UPDATE public.user_addresses a
   SET is_default = TRUE
 WHERE a.id IN (
   SELECT DISTINCT ON (user_id) id
   FROM public.user_addresses
   WHERE user_id NOT IN (
     SELECT user_id FROM public.user_addresses WHERE is_default
   )
   ORDER BY user_id, created_at DESC
 );

NOTIFY pgrst, 'reload schema';

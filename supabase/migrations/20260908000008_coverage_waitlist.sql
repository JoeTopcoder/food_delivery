-- Migration: capture demand from customers we cannot serve yet.
--
-- With distance filtering live, someone outside the delivery radius opens the
-- app to "No restaurants found" and leaves — and we learn nothing. That is the
-- single moment we know both who they are and where they want delivery, and we
-- were throwing it away.
--
-- What this buys, beyond not losing them: which parish to open next, ranked by
-- people who actually asked, rather than a guess.

CREATE TABLE IF NOT EXISTS public.coverage_waitlist (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID REFERENCES public.users(id) ON DELETE SET NULL,
  -- Kept even for signed-in users: the account address is where they are NOW,
  -- and a customer can ask about somewhere they are moving to.
  contact     TEXT NOT NULL,
  latitude    DOUBLE PRECISION,
  longitude   DOUBLE PRECISION,
  address     TEXT,
  -- How far the nearest store was when they asked, so the list can be worked
  -- nearest-first when coverage expands.
  nearest_km  NUMERIC,
  notified_at TIMESTAMPTZ,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One entry per person per place. Asking twice from the same spot should not
-- inflate the demand signal the list exists to measure.
CREATE UNIQUE INDEX IF NOT EXISTS idx_coverage_waitlist_unique
  ON public.coverage_waitlist (
    COALESCE(user_id::text, contact),
    round(COALESCE(latitude, 0)::numeric, 2),
    round(COALESCE(longitude, 0)::numeric, 2)
  );

ALTER TABLE public.coverage_waitlist ENABLE ROW LEVEL SECURITY;

-- Customers may read only their own row; the list itself is an ops asset.
DROP POLICY IF EXISTS coverage_waitlist_own ON public.coverage_waitlist;
CREATE POLICY coverage_waitlist_own ON public.coverage_waitlist
  FOR SELECT USING (user_id = auth.uid());

-- Writes go through the RPC below, never direct.
CREATE OR REPLACE FUNCTION public.join_coverage_waitlist(
  p_contact    TEXT,
  p_latitude   DOUBLE PRECISION DEFAULT NULL,
  p_longitude  DOUBLE PRECISION DEFAULT NULL,
  p_address    TEXT DEFAULT NULL,
  p_nearest_km NUMERIC DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user UUID := auth.uid();
  v_id   UUID;
BEGIN
  IF p_contact IS NULL OR length(btrim(p_contact)) < 5 THEN
    RAISE EXCEPTION 'Enter an email address or phone number so we can reach you';
  END IF;

  INSERT INTO public.coverage_waitlist
    (user_id, contact, latitude, longitude, address, nearest_km)
  VALUES
    (v_user, btrim(p_contact), p_latitude, p_longitude, p_address, p_nearest_km)
  ON CONFLICT DO NOTHING
  RETURNING id INTO v_id;

  -- Already on the list from this spot. Say yes rather than erroring: from the
  -- customer's side asking twice worked both times.
  RETURN jsonb_build_object('joined', TRUE, 'created', v_id IS NOT NULL);
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_coverage_waitlist TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

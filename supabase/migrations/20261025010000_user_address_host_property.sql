-- Host Rewards Phase 4: let a saved delivery address reference a registered
-- host property, so checkout can tag the order with the property it's delivered
-- to (which the commission engine then matches against the customer's referral).
ALTER TABLE public.user_addresses
  ADD COLUMN IF NOT EXISTS host_property_id uuid REFERENCES public.host_properties(id);

NOTIFY pgrst, 'reload schema';

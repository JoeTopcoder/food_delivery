-- Order-item price snapshot for HotBite+ member pricing. Permanently records
-- what each line cost at purchase so historical orders never change when a
-- merchant later edits the member price. Purely additive — no earnings table is
-- touched, and existing orders default to regular pricing (member_discount 0).
ALTER TABLE public.order_items
  ADD COLUMN IF NOT EXISTS regular_price numeric,      -- undiscounted unit price at purchase
  ADD COLUMN IF NOT EXISTS member_discount numeric NOT NULL DEFAULT 0, -- per-unit member saving
  ADD COLUMN IF NOT EXISTS membership_applied boolean NOT NULL DEFAULT false;

-- Total HotBite+ member saving for the whole order (sum of line savings), for
-- customer-facing "You saved $X" display and reporting. Separate from any
-- deal/voucher discount in order_membership_discounts.
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS member_savings numeric NOT NULL DEFAULT 0;

NOTIFY pgrst, 'reload schema';

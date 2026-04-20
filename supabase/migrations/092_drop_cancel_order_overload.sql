-- Migration 092: Remove legacy 2-arg cancel_order_with_penalty overload
-- PostgREST can see both the old 2-arg function and the new 3-arg function,
-- which causes: "Could not choose the best candidate function..."

DROP FUNCTION IF EXISTS public.cancel_order_with_penalty(UUID, UUID);

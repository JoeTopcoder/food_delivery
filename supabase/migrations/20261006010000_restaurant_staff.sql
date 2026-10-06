-- ============================================================================
-- RESTAURANT STAFF — membership, fixed roles, invitations, audit (Phase 1).
--
-- Adds per-restaurant staff memberships (owner/manager/cashier) WITHOUT changing
-- the existing restaurants.owner_id ownership model. A user may belong to many
-- restaurants; every action is authorized server-side against an ACTIVE
-- membership in the selected restaurant, so deactivation revokes access
-- immediately — even with a still-valid access token — without touching the
-- user's customer account or other memberships.
--
-- Preserves all existing order/payment/float/payout behaviour (nothing here
-- moves money). Protected role/membership fields are never client-writable;
-- changes go through SECURITY DEFINER RPCs (next migration).
-- ============================================================================

-- ── Membership ──────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.restaurant_staff (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id   uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  user_id         uuid NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role            text NOT NULL CHECK (role IN ('owner','manager','cashier')),
  is_active       boolean NOT NULL DEFAULT true,
  invited_by      uuid REFERENCES public.users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  deactivated_at  timestamptz,
  UNIQUE (restaurant_id, user_id)                 -- no duplicate memberships
);
CREATE INDEX IF NOT EXISTS idx_rstaff_restaurant ON public.restaurant_staff(restaurant_id);
CREATE INDEX IF NOT EXISTS idx_rstaff_user       ON public.restaurant_staff(user_id);
-- At most ONE active owner-membership row per restaurant is not required (the
-- real owner is restaurants.owner_id); but guard against two active members
-- colliding is handled by the UNIQUE(restaurant_id,user_id).

ALTER TABLE public.restaurant_staff ENABLE ROW LEVEL SECURITY;

-- ── Invitations (token hashed at rest, single-use, 72h) ─────────────────────
CREATE TABLE IF NOT EXISTS public.staff_invitations (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id   uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  email           text NOT NULL,                  -- lowercased
  role            text NOT NULL CHECK (role IN ('manager','cashier')),
  token_hash      text NOT NULL,                  -- sha256 of the raw token
  status          text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','accepted','revoked','expired')),
  invited_by      uuid NOT NULL REFERENCES public.users(id),
  accepted_user_id uuid REFERENCES public.users(id),
  expires_at      timestamptz NOT NULL,
  created_at      timestamptz NOT NULL DEFAULT now(),
  accepted_at     timestamptz
);
-- Only one pending invite per restaurant+email (resend revokes the old one).
CREATE UNIQUE INDEX IF NOT EXISTS uq_staff_invite_pending
  ON public.staff_invitations (restaurant_id, lower(email)) WHERE status='pending';
CREATE INDEX IF NOT EXISTS idx_staff_invite_restaurant ON public.staff_invitations(restaurant_id);

ALTER TABLE public.staff_invitations ENABLE ROW LEVEL SECURITY;

-- ── Audit (append-only; never client-writable) ──────────────────────────────
CREATE TABLE IF NOT EXISTS public.restaurant_staff_audit (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id  uuid NOT NULL,
  actor_user_id  uuid,
  action         text NOT NULL,
  target_user_id uuid,
  reason         text,
  before_data    jsonb,
  after_data     jsonb,
  created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_rstaff_audit_restaurant ON public.restaurant_staff_audit(restaurant_id);
ALTER TABLE public.restaurant_staff_audit ENABLE ROW LEVEL SECURITY;

-- ── Authorization helpers ───────────────────────────────────────────────────
-- Effective role of a user at a restaurant: 'owner' if they own it (or hold an
-- active owner membership), else their active membership role, else NULL.
-- Deactivated or absent membership → NULL → no access.
CREATE OR REPLACE FUNCTION public.restaurant_staff_role(p_restaurant uuid, p_user uuid DEFAULT auth.uid())
  RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT CASE
    WHEN EXISTS (SELECT 1 FROM public.restaurants r WHERE r.id=p_restaurant AND r.owner_id=p_user)
      THEN 'owner'
    ELSE (SELECT s.role FROM public.restaurant_staff s
          WHERE s.restaurant_id=p_restaurant AND s.user_id=p_user AND s.is_active
          LIMIT 1)
  END;
$$;
GRANT EXECUTE ON FUNCTION public.restaurant_staff_role(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_restaurant_staff(p_restaurant uuid, p_user uuid DEFAULT auth.uid())
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT public.restaurant_staff_role(p_restaurant, p_user) IS NOT NULL; $$;
GRANT EXECUTE ON FUNCTION public.is_restaurant_staff(uuid,uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.can_manage_restaurant_staff(p_restaurant uuid, p_user uuid DEFAULT auth.uid())
  RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$ SELECT public.restaurant_staff_role(p_restaurant, p_user) IN ('owner','manager'); $$;
GRANT EXECUTE ON FUNCTION public.can_manage_restaurant_staff(uuid,uuid) TO authenticated, service_role;

-- ── RLS: read for staff of the restaurant; NO direct client writes ──────────
-- restaurant_staff: owner/manager see all members; a cashier sees only their own
-- row. All mutations go through RPCs (SECURITY DEFINER) — no client INSERT/UPDATE.
DROP POLICY IF EXISTS rstaff_select ON public.restaurant_staff;
CREATE POLICY rstaff_select ON public.restaurant_staff FOR SELECT TO authenticated
  USING (public.can_manage_restaurant_staff(restaurant_id) OR user_id = auth.uid());

-- staff_invitations: owner/manager of the restaurant may read; no client writes.
DROP POLICY IF EXISTS sinv_select ON public.staff_invitations;
CREATE POLICY sinv_select ON public.staff_invitations FOR SELECT TO authenticated
  USING (public.can_manage_restaurant_staff(restaurant_id));

-- audit: owner/manager read; no client writes.
DROP POLICY IF EXISTS raudit_select ON public.restaurant_staff_audit;
CREATE POLICY raudit_select ON public.restaurant_staff_audit FOR SELECT TO authenticated
  USING (public.can_manage_restaurant_staff(restaurant_id));

-- Lock down table-level writes (defense in depth; RPCs use service/definer).
REVOKE INSERT, UPDATE, DELETE ON public.restaurant_staff        FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.staff_invitations       FROM anon, authenticated;
REVOKE INSERT, UPDATE, DELETE ON public.restaurant_staff_audit  FROM anon, authenticated;

NOTIFY pgrst, 'reload schema';

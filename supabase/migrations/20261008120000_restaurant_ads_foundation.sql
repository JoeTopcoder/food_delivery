-- ============================================================================
-- HotBite Restaurant Ads — Foundation (schema + security + overbooking guard)
--
-- Adds a paid restaurant-advertising system ALONGSIDE the existing image-only
-- `banners` table (which is left untouched and keeps working). Money is stored
-- in integer minor units (JMD cents). Dates are UTC; display converts to
-- America/Jamaica. Content production and placement are separate line items /
-- charges. Nothing here changes commissions, fees, membership or order math.
--
-- This migration is FOUNDATION ONLY: tables, RLS, a permission helper, the
-- overbooking exclusion guard, settings + feature flag. Lifecycle RPCs, the
-- ad-selection RPC, media processing and all Flutter UI are later steps.
-- ============================================================================

-- ── Permission helper: may the caller manage ads for this restaurant? ───────
-- True for platform admins, the restaurant owner, or an active staff member.
CREATE OR REPLACE FUNCTION public.can_manage_restaurant(p_restaurant uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    public.is_admin()
    OR EXISTS (SELECT 1 FROM public.restaurants r
               WHERE r.id = p_restaurant AND r.owner_id = auth.uid())
    OR EXISTS (SELECT 1 FROM public.restaurant_staff s
               WHERE s.restaurant_id = p_restaurant
                 AND s.user_id = auth.uid()
                 AND s.is_active = true);
$$;
REVOKE ALL ON FUNCTION public.can_manage_restaurant(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.can_manage_restaurant(uuid) TO authenticated;

-- ── Settings (single row) + feature flag ────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ad_settings (
  id                      int PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  enabled                 boolean NOT NULL DEFAULT false,  -- master feature flag
  max_concurrent          int     NOT NULL DEFAULT 3,      -- booking capacity (slots)
  reserved_slots          int     NOT NULL DEFAULT 1,      -- min space kept for sponsored
  default_placement_cents bigint  NOT NULL DEFAULT 0,      -- JMD cents, admin sets real price
  session_exposure_limit  int     NOT NULL DEFAULT 3,      -- max sponsored views per session
  max_video_seconds       int     NOT NULL DEFAULT 20,
  max_upload_bytes        bigint  NOT NULL DEFAULT 52428800, -- 50 MB
  rotation                text    NOT NULL DEFAULT 'fair'  CHECK (rotation IN ('fair','random')),
  updated_at              timestamptz NOT NULL DEFAULT now(),
  updated_by              uuid
);
INSERT INTO public.ad_settings (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.ad_settings ENABLE ROW LEVEL SECURITY;
-- readable by any signed-in user (clients need enabled flag + limits); admin writes.
CREATE POLICY ad_settings_read ON public.ad_settings FOR SELECT TO authenticated USING (true);
CREATE POLICY ad_settings_admin_write ON public.ad_settings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- mirror the flag into app_config so it follows the existing feature-flag pattern
INSERT INTO public.app_config (key, value)
VALUES ('restaurant_ads_enabled', 'false')
ON CONFLICT (key) DO NOTHING;

-- ── Requests ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ad_requests (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id         uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  -- what the restaurant is asking for:
  kind                  text NOT NULL CHECK (kind IN ('self_video','self_image','produce')),
  wants_placement       boolean NOT NULL DEFAULT true,
  title                 text NOT NULL,
  headline              text,
  description           text,
  production_brief      text,                 -- for 'produce'
  preferred_style       text,
  call_to_action        text,
  destination_type      text CHECK (destination_type IN ('menu','dish')),
  destination_dish_id   uuid,                 -- validated to belong to restaurant
  requested_start_date  date,
  duration_days         int CHECK (duration_days IS NULL OR duration_days > 0),
  requested_delivery_date date,               -- for produced content
  target_area           text,
  contact_name          text,
  contact_phone         text,
  contact_email         text,
  notes                 text,
  rights_confirmed      boolean NOT NULL DEFAULT false, -- permission to use media/music/offers
  -- request-review lifecycle (SEPARATE from all other states):
  status                text NOT NULL DEFAULT 'draft'
                          CHECK (status IN ('draft','submitted','in_review','approved','rejected','withdrawn')),
  review_reason         text,
  reviewed_by           uuid,
  reviewed_at           timestamptz,
  created_by            uuid NOT NULL DEFAULT auth.uid(),
  created_at            timestamptz NOT NULL DEFAULT now(),
  updated_at            timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ad_requests_restaurant_idx ON public.ad_requests(restaurant_id, status);

-- ── Creatives (versioned; raw asset private, playback only when approved) ────
CREATE TABLE IF NOT EXISTS public.ad_creatives (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id      uuid NOT NULL REFERENCES public.ad_requests(id) ON DELETE CASCADE,
  restaurant_id   uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  version         int  NOT NULL,
  media_type      text NOT NULL CHECK (media_type IN ('image','video')),
  source          text NOT NULL CHECK (source IN ('restaurant','hotbite')),
  -- creative-approval lifecycle (SEPARATE):
  status          text NOT NULL DEFAULT 'uploaded'
                    CHECK (status IN ('uploaded','processing','ready','failed',
                                      'pending_approval','approved','changes_requested',
                                      'rejected','superseded')),
  raw_asset_path  text,          -- PRIVATE bucket path (never served to customers)
  playback_url    text,          -- set only once approved + processed
  thumbnail_url   text,
  captions_url    text,
  headline        text,
  duration_seconds int,
  width           int,
  height          int,
  bytes           bigint,
  processing_error text,
  rights_confirmed boolean NOT NULL DEFAULT false,
  change_notes    text,
  approved_by     uuid,
  approved_at     timestamptz,
  created_by      uuid NOT NULL DEFAULT auth.uid(),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, version)
);
CREATE INDEX IF NOT EXISTS ad_creatives_request_idx ON public.ad_creatives(request_id, status);

-- ── Quotes + line items (production vs placement kept separate) ──────────────
CREATE TABLE IF NOT EXISTS public.ad_quotes (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id    uuid NOT NULL REFERENCES public.ad_requests(id) ON DELETE CASCADE,
  version       int  NOT NULL,
  currency      text NOT NULL DEFAULT 'JMD',
  total_cents   bigint NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  -- quote-acceptance lifecycle (SEPARATE):
  status        text NOT NULL DEFAULT 'issued'
                  CHECK (status IN ('issued','accepted','declined','superseded','expired')),
  valid_until   timestamptz,
  issued_by     uuid NOT NULL DEFAULT auth.uid(),
  accepted_by   uuid,
  accepted_at   timestamptz,
  created_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (request_id, version)
);
CREATE TABLE IF NOT EXISTS public.ad_quote_items (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id     uuid NOT NULL REFERENCES public.ad_quotes(id) ON DELETE CASCADE,
  kind         text NOT NULL CHECK (kind IN ('production','placement')),
  description  text,
  amount_cents bigint NOT NULL CHECK (amount_cents >= 0)
);
CREATE INDEX IF NOT EXISTS ad_quote_items_quote_idx ON public.ad_quote_items(quote_id);

-- ── Campaigns (the servable unit) ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ad_campaigns (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  request_id         uuid NOT NULL REFERENCES public.ad_requests(id) ON DELETE CASCADE,
  restaurant_id      uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  creative_id        uuid REFERENCES public.ad_creatives(id),   -- approved version
  quote_id           uuid REFERENCES public.ad_quotes(id),
  destination_type   text CHECK (destination_type IN ('menu','dish')),
  destination_dish_id uuid,
  slot_index         int,                 -- which capacity slot the booking holds
  starts_at          timestamptz,         -- UTC
  ends_at            timestamptz,         -- UTC
  -- campaign-delivery lifecycle (SEPARATE):
  status             text NOT NULL DEFAULT 'scheduled'
                       CHECK (status IN ('scheduled','active','paused','completed','cancelled')),
  payment_satisfied  boolean NOT NULL DEFAULT false,
  pause_reason       text,
  cancel_reason      text,
  created_by         uuid NOT NULL DEFAULT auth.uid(),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX IF NOT EXISTS ad_campaigns_serving_idx
  ON public.ad_campaigns(status, starts_at, ends_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS ad_campaigns_restaurant_idx ON public.ad_campaigns(restaurant_id);

-- ── Bookings + overbooking guard ────────────────────────────────────────────
-- A confirmed/reserved booking holds one capacity slot for a time range. The
-- GiST exclusion constraint makes it IMPOSSIBLE for two live bookings to hold
-- the same slot over overlapping times — this is the backend guarantee against
-- overbooking under concurrency (not app logic).
CREATE EXTENSION IF NOT EXISTS btree_gist;
CREATE TABLE IF NOT EXISTS public.ad_bookings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  slot_index  int  NOT NULL,
  during      tstzrange NOT NULL,
  status      text NOT NULL DEFAULT 'reserved'
                CHECK (status IN ('reserved','confirmed','released','cancelled')),
  created_by  uuid NOT NULL DEFAULT auth.uid(),
  created_at  timestamptz NOT NULL DEFAULT now(),
  -- only live (reserved/confirmed) rows participate in the exclusion
  EXCLUDE USING gist (slot_index WITH =, during WITH &&)
    WHERE (status IN ('reserved','confirmed'))
);
CREATE INDEX IF NOT EXISTS ad_bookings_campaign_idx ON public.ad_bookings(campaign_id);

-- ── Payment records (integer cents, idempotent) ─────────────────────────────
CREATE TABLE IF NOT EXISTS public.ad_payment_records (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id     uuid REFERENCES public.ad_campaigns(id) ON DELETE SET NULL,
  quote_id        uuid REFERENCES public.ad_quotes(id) ON DELETE SET NULL,
  restaurant_id   uuid NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  amount_cents    bigint NOT NULL CHECK (amount_cents >= 0),
  kind            text CHECK (kind IN ('production','placement')),
  method          text,          -- stripe | manual | ...
  provider_ref    text,
  status          text NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending','verified','failed','refunded')),
  idempotency_key text UNIQUE,    -- dedupes provider callbacks / double submits
  evidence        jsonb,          -- manual-verification supporting evidence
  verified_by     uuid,
  verified_at     timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ad_payments_campaign_idx ON public.ad_payment_records(campaign_id);

-- ── Events (raw analytics, deduped) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ad_events (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  creative_id uuid REFERENCES public.ad_creatives(id) ON DELETE SET NULL,
  event_type  text NOT NULL CHECK (event_type IN ('impression','video_start','video_complete','cta_click')),
  session_id  text,
  user_id     uuid,              -- for attribution only; not exposed in reports
  dedupe_key  text UNIQUE,       -- (session, creative, type, exposure) — prevents inflation
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ad_events_campaign_idx ON public.ad_events(campaign_id, event_type, created_at);
CREATE INDEX IF NOT EXISTS ad_events_attrib_idx ON public.ad_events(user_id, event_type, created_at)
  WHERE event_type = 'cta_click';

-- ── Daily metrics (aggregated, Jamaica day) ─────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ad_daily_metrics (
  campaign_id       uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  day               date NOT NULL,              -- Jamaica calendar day
  impressions       bigint NOT NULL DEFAULT 0,
  video_starts      bigint NOT NULL DEFAULT 0,
  video_completions bigint NOT NULL DEFAULT 0,
  cta_clicks        bigint NOT NULL DEFAULT 0,
  attributed_orders bigint NOT NULL DEFAULT 0,
  spend_cents       bigint NOT NULL DEFAULT 0,
  updated_at        timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (campaign_id, day)
);

-- ── Audit log ───────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ad_audit_logs (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  entity_type text NOT NULL,
  entity_id   uuid,
  action      text NOT NULL,
  actor_id    uuid DEFAULT auth.uid(),
  reason      text,
  meta        jsonb,
  created_at  timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS ad_audit_entity_idx ON public.ad_audit_logs(entity_type, entity_id, created_at);

-- ============================================================================
-- RLS — restaurant-scoped for restaurant users, full for admins. Customers get
-- NO direct table access; they read eligible ads only via the (later) selection
-- RPC. Financial/production internals are never exposed to restaurant SELECT of
-- quotes/payments beyond their own restaurant, and never to customers.
-- ============================================================================
ALTER TABLE public.ad_requests        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_creatives       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_quotes          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_quote_items     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_campaigns       ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_bookings        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_payment_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_events          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_daily_metrics   ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ad_audit_logs      ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.ad_requests, public.ad_creatives, public.ad_quotes,
  public.ad_quote_items, public.ad_campaigns, public.ad_bookings,
  public.ad_payment_records, public.ad_events, public.ad_daily_metrics,
  public.ad_audit_logs FROM anon;

-- ad_requests: restaurant managers read/insert/update their own (while draft/
-- submitted); admins full. (Status transitions that must stay admin-only are
-- enforced by SECURITY DEFINER lifecycle RPCs in the next migration, not raw UPDATE.)
CREATE POLICY ad_requests_read ON public.ad_requests FOR SELECT TO authenticated
  USING (public.can_manage_restaurant(restaurant_id));
CREATE POLICY ad_requests_insert ON public.ad_requests FOR INSERT TO authenticated
  WITH CHECK (public.can_manage_restaurant(restaurant_id) AND created_by = auth.uid());
CREATE POLICY ad_requests_update_own ON public.ad_requests FOR UPDATE TO authenticated
  USING (public.can_manage_restaurant(restaurant_id)
         AND (public.is_admin() OR status IN ('draft','submitted')))
  WITH CHECK (public.can_manage_restaurant(restaurant_id));

-- creatives: restaurant managers read theirs + insert their own uploads; admins full.
CREATE POLICY ad_creatives_read ON public.ad_creatives FOR SELECT TO authenticated
  USING (public.can_manage_restaurant(restaurant_id));
CREATE POLICY ad_creatives_insert ON public.ad_creatives FOR INSERT TO authenticated
  WITH CHECK (public.can_manage_restaurant(restaurant_id) AND created_by = auth.uid());
CREATE POLICY ad_creatives_admin_write ON public.ad_creatives FOR UPDATE TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- quotes/items: restaurant managers READ their own (to accept/decline via RPC);
-- only admins write.
CREATE POLICY ad_quotes_read ON public.ad_quotes FOR SELECT TO authenticated
  USING (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.ad_requests r
    WHERE r.id = request_id AND public.can_manage_restaurant(r.restaurant_id)));
CREATE POLICY ad_quotes_admin_write ON public.ad_quotes FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY ad_quote_items_read ON public.ad_quote_items FOR SELECT TO authenticated
  USING (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.ad_quotes q JOIN public.ad_requests r ON r.id = q.request_id
    WHERE q.id = quote_id AND public.can_manage_restaurant(r.restaurant_id)));
CREATE POLICY ad_quote_items_admin_write ON public.ad_quote_items FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- campaigns: restaurant managers READ theirs; admins write (via RPCs).
CREATE POLICY ad_campaigns_read ON public.ad_campaigns FOR SELECT TO authenticated
  USING (public.can_manage_restaurant(restaurant_id));
CREATE POLICY ad_campaigns_admin_write ON public.ad_campaigns FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- bookings / payments: admin-only (money + capacity). Restaurant sees payment
-- status through campaign/quote reads + RPC summaries, not raw rows.
CREATE POLICY ad_bookings_admin ON public.ad_bookings FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());
CREATE POLICY ad_payments_admin ON public.ad_payment_records FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- daily metrics: restaurant managers READ their own campaigns' aggregates; admin full.
CREATE POLICY ad_metrics_read ON public.ad_daily_metrics FOR SELECT TO authenticated
  USING (public.is_admin() OR EXISTS (
    SELECT 1 FROM public.ad_campaigns c
    WHERE c.id = campaign_id AND public.can_manage_restaurant(c.restaurant_id)));
CREATE POLICY ad_metrics_admin_write ON public.ad_daily_metrics FOR ALL TO authenticated
  USING (public.is_admin()) WITH CHECK (public.is_admin());

-- events: NO client writes/reads (ingested via rate-limited RPC); admin read.
CREATE POLICY ad_events_admin_read ON public.ad_events FOR SELECT TO authenticated
  USING (public.is_admin());

-- audit: admin read only; writes happen inside SECURITY DEFINER RPCs.
CREATE POLICY ad_audit_admin_read ON public.ad_audit_logs FOR SELECT TO authenticated
  USING (public.is_admin());

NOTIFY pgrst, 'reload schema';

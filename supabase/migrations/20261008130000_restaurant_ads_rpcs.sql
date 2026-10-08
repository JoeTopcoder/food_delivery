-- ============================================================================
-- HotBite Restaurant Ads — Lifecycle RPCs, selection, events, attribution
-- All server-enforced (SECURITY DEFINER). Restaurant RPCs gate on
-- can_manage_restaurant(); money/booking/activation RPCs gate on is_admin().
-- Customers (incl. guests) may only call get_sponsored_ads + ad_record_event.
-- ============================================================================

ALTER TABLE public.ad_settings ADD COLUMN IF NOT EXISTS serve_radius_km numeric NOT NULL DEFAULT 15;

-- Attribution: at most one campaign per completed order (dedup key = order id).
CREATE TABLE IF NOT EXISTS public.ad_order_attributions (
  order_id    uuid PRIMARY KEY,
  campaign_id uuid NOT NULL REFERENCES public.ad_campaigns(id) ON DELETE CASCADE,
  created_at  timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.ad_order_attributions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.ad_order_attributions FROM anon;
CREATE POLICY ad_attrib_admin_read ON public.ad_order_attributions FOR SELECT TO authenticated
  USING (public.is_admin());

-- ── audit helper ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._ad_audit(p_type text, p_id uuid, p_action text,
                                            p_reason text DEFAULT NULL, p_meta jsonb DEFAULT NULL)
RETURNS void LANGUAGE sql SECURITY DEFINER SET search_path=public AS $$
  INSERT INTO public.ad_audit_logs(entity_type, entity_id, action, reason, meta)
  VALUES (p_type, p_id, p_action, p_reason, p_meta);
$$;

-- ── Restaurant: submit a draft request for review ───────────────────────────
CREATE OR REPLACE FUNCTION public.ad_submit_request(p_request_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rest uuid; v_status text;
BEGIN
  SELECT restaurant_id, status INTO v_rest, v_status FROM ad_requests WHERE id=p_request_id;
  IF v_rest IS NULL THEN RAISE EXCEPTION 'request not found'; END IF;
  IF NOT can_manage_restaurant(v_rest) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF v_status <> 'draft' THEN RAISE EXCEPTION 'only drafts can be submitted'; END IF;
  UPDATE ad_requests SET status='submitted', updated_at=now() WHERE id=p_request_id;
  PERFORM _ad_audit('request', p_request_id, 'submitted');
END $$;

-- ── Admin: review a request ─────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ad_review_request(p_request_id uuid, p_decision text, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_decision NOT IN ('approved','rejected','in_review') THEN RAISE EXCEPTION 'bad decision'; END IF;
  UPDATE ad_requests SET status=p_decision, review_reason=p_reason,
         reviewed_by=auth.uid(), reviewed_at=now(), updated_at=now()
  WHERE id=p_request_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'request not found'; END IF;
  PERFORM _ad_audit('request', p_request_id, 'review_'||p_decision, p_reason);
END $$;

-- ── Admin: issue a versioned quote with production/placement line items ──────
-- p_items: jsonb array of {kind, description, amount_cents}. Supersedes prior issued quotes.
CREATE OR REPLACE FUNCTION public.ad_issue_quote(p_request_id uuid, p_items jsonb, p_valid_until timestamptz DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_ver int; v_qid uuid; v_total bigint; it jsonb;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF NOT EXISTS (SELECT 1 FROM ad_requests WHERE id=p_request_id) THEN RAISE EXCEPTION 'request not found'; END IF;
  UPDATE ad_quotes SET status='superseded' WHERE request_id=p_request_id AND status='issued';
  SELECT COALESCE(MAX(version),0)+1 INTO v_ver FROM ad_quotes WHERE request_id=p_request_id;
  SELECT COALESCE(SUM((x->>'amount_cents')::bigint),0) INTO v_total FROM jsonb_array_elements(p_items) x;
  INSERT INTO ad_quotes(request_id, version, total_cents, valid_until)
    VALUES (p_request_id, v_ver, v_total, p_valid_until) RETURNING id INTO v_qid;
  FOR it IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    IF (it->>'kind') NOT IN ('production','placement') THEN RAISE EXCEPTION 'bad line kind'; END IF;
    INSERT INTO ad_quote_items(quote_id, kind, description, amount_cents)
      VALUES (v_qid, it->>'kind', it->>'description', (it->>'amount_cents')::bigint);
  END LOOP;
  PERFORM _ad_audit('quote', v_qid, 'issued', NULL, jsonb_build_object('version',v_ver,'total_cents',v_total));
  RETURN v_qid;
END $$;

-- small helper: quote still valid?
CREATE OR REPLACE FUNCTION public.ad_quote_valid(p_quote_id uuid)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  SELECT valid_until IS NULL OR valid_until > now() FROM ad_quotes WHERE id=p_quote_id;
$$;

-- ── Restaurant: accept / decline a quote ────────────────────────────────────
CREATE OR REPLACE FUNCTION public.ad_respond_quote(p_quote_id uuid, p_accept boolean)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rest uuid; v_status text; v_req uuid;
BEGIN
  SELECT r.restaurant_id, q.status, q.request_id INTO v_rest, v_status, v_req
  FROM ad_quotes q JOIN ad_requests r ON r.id=q.request_id WHERE q.id=p_quote_id;
  IF v_rest IS NULL THEN RAISE EXCEPTION 'quote not found'; END IF;
  IF NOT can_manage_restaurant(v_rest) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF v_status <> 'issued' THEN RAISE EXCEPTION 'quote not open'; END IF;
  IF ad_quote_valid(p_quote_id) IS FALSE THEN RAISE EXCEPTION 'quote expired'; END IF;
  UPDATE ad_quotes SET status=CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END,
         accepted_by=CASE WHEN p_accept THEN auth.uid() END,
         accepted_at=CASE WHEN p_accept THEN now() END
  WHERE id=p_quote_id;
  PERFORM _ad_audit('quote', p_quote_id, CASE WHEN p_accept THEN 'accepted' ELSE 'declined' END);
END $$;

-- ── Creatives: new version (supersedes prior), send for approval, mark ready ─
-- Replacing an approved creative => a NEW version requiring approval.
CREATE OR REPLACE FUNCTION public.ad_new_creative(
  p_request_id uuid, p_media_type text, p_source text, p_raw_path text,
  p_thumbnail_url text DEFAULT NULL, p_captions_url text DEFAULT NULL, p_headline text DEFAULT NULL,
  p_rights boolean DEFAULT false)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rest uuid; v_ver int; v_id uuid;
BEGIN
  SELECT restaurant_id INTO v_rest FROM ad_requests WHERE id=p_request_id;
  IF v_rest IS NULL THEN RAISE EXCEPTION 'request not found'; END IF;
  -- restaurant may add creatives for 'restaurant' source; admin for either
  IF NOT (is_admin() OR (can_manage_restaurant(v_rest) AND p_source='restaurant')) THEN
    RAISE EXCEPTION 'not authorized'; END IF;
  IF p_media_type NOT IN ('image','video') OR p_source NOT IN ('restaurant','hotbite') THEN
    RAISE EXCEPTION 'bad media/source'; END IF;
  -- supersede the current approved/pending creatives for this request
  UPDATE ad_creatives SET status='superseded', updated_at=now()
    WHERE request_id=p_request_id AND status IN ('approved','pending_approval','ready','changes_requested');
  SELECT COALESCE(MAX(version),0)+1 INTO v_ver FROM ad_creatives WHERE request_id=p_request_id;
  INSERT INTO ad_creatives(request_id, restaurant_id, version, media_type, source,
      status, raw_asset_path, thumbnail_url, captions_url, headline, rights_confirmed)
    VALUES (p_request_id, v_rest, v_ver, p_media_type, p_source,
      'uploaded', p_raw_path, p_thumbnail_url, p_captions_url, p_headline, p_rights)
    RETURNING id INTO v_id;
  PERFORM _ad_audit('creative', v_id, 'uploaded', NULL, jsonb_build_object('version',v_ver,'source',p_source));
  RETURN v_id;
END $$;

-- Admin: after processing, mark ready with playback url + send for approval.
CREATE OR REPLACE FUNCTION public.ad_mark_creative_ready(p_creative_id uuid, p_playback_url text,
  p_thumbnail_url text DEFAULT NULL, p_duration int DEFAULT NULL, p_width int DEFAULT NULL, p_height int DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  UPDATE ad_creatives SET status='pending_approval', playback_url=p_playback_url,
    thumbnail_url=COALESCE(p_thumbnail_url,thumbnail_url), duration_seconds=p_duration,
    width=p_width, height=p_height, processing_error=NULL, updated_at=now()
  WHERE id=p_creative_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'creative not found'; END IF;
  PERFORM _ad_audit('creative', p_creative_id, 'ready_for_approval');
END $$;

-- Restaurant/admin: approve a creative version, or request changes.
CREATE OR REPLACE FUNCTION public.ad_decide_creative(p_creative_id uuid, p_approve boolean, p_notes text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_rest uuid; v_status text;
BEGIN
  SELECT restaurant_id, status INTO v_rest, v_status FROM ad_creatives WHERE id=p_creative_id;
  IF v_rest IS NULL THEN RAISE EXCEPTION 'creative not found'; END IF;
  IF NOT can_manage_restaurant(v_rest) THEN RAISE EXCEPTION 'not authorized'; END IF;
  IF v_status <> 'pending_approval' THEN RAISE EXCEPTION 'creative not awaiting approval'; END IF;
  IF p_approve THEN
    UPDATE ad_creatives SET status='approved', approved_by=auth.uid(), approved_at=now(),
           change_notes=NULL, updated_at=now() WHERE id=p_creative_id;
  ELSE
    UPDATE ad_creatives SET status='changes_requested', change_notes=p_notes, updated_at=now()
      WHERE id=p_creative_id;
  END IF;
  PERFORM _ad_audit('creative', p_creative_id, CASE WHEN p_approve THEN 'approved' ELSE 'changes_requested' END, p_notes);
END $$;

-- ── Admin: reserve a booking (uses the overbooking exclusion guard) ─────────
CREATE OR REPLACE FUNCTION public.ad_reserve_booking(p_campaign_id uuid, p_slot int,
  p_starts timestamptz, p_ends timestamptz)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_max int;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT max_concurrent INTO v_max FROM ad_settings WHERE id=1;
  IF p_slot < 1 OR p_slot > v_max THEN RAISE EXCEPTION 'slot out of range (1..%)', v_max; END IF;
  BEGIN
    INSERT INTO ad_bookings(campaign_id, slot_index, during, status)
      VALUES (p_campaign_id, p_slot, tstzrange(p_starts, p_ends, '[)'), 'confirmed')
      RETURNING id INTO v_id;
  EXCEPTION WHEN exclusion_violation THEN
    RAISE EXCEPTION 'slot % already booked for that period (overbooking prevented)', p_slot;
  END;
  UPDATE ad_campaigns SET slot_index=p_slot, starts_at=p_starts, ends_at=p_ends, updated_at=now()
    WHERE id=p_campaign_id;
  PERFORM _ad_audit('booking', v_id, 'reserved', NULL, jsonb_build_object('campaign',p_campaign_id,'slot',p_slot));
  RETURN v_id;
END $$;

-- ── Admin: verify a payment idempotently; flips campaign.payment_satisfied ───
CREATE OR REPLACE FUNCTION public.ad_verify_payment(p_campaign_id uuid, p_amount_cents bigint,
  p_kind text, p_method text, p_idempotency_key text, p_provider_ref text DEFAULT NULL, p_evidence jsonb DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_id uuid; v_rest uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  -- idempotent: if this key already recorded, return existing (no double-charge/record)
  SELECT id INTO v_id FROM ad_payment_records WHERE idempotency_key=p_idempotency_key;
  IF v_id IS NOT NULL THEN RETURN v_id; END IF;
  SELECT restaurant_id INTO v_rest FROM ad_campaigns WHERE id=p_campaign_id;
  IF v_rest IS NULL THEN RAISE EXCEPTION 'campaign not found'; END IF;
  INSERT INTO ad_payment_records(campaign_id, restaurant_id, amount_cents, kind, method,
      provider_ref, status, idempotency_key, evidence, verified_by, verified_at)
    VALUES (p_campaign_id, v_rest, p_amount_cents, p_kind, p_method, p_provider_ref,
      'verified', p_idempotency_key, p_evidence, auth.uid(), now())
    RETURNING id INTO v_id;
  -- payment satisfied when verified placement payments cover the accepted quote's placement total
  UPDATE ad_campaigns c SET payment_satisfied = (
      COALESCE((SELECT SUM(amount_cents) FROM ad_payment_records
                WHERE campaign_id=c.id AND status='verified'),0)
      >= COALESCE((SELECT SUM(qi.amount_cents) FROM ad_quote_items qi
                   JOIN ad_quotes q ON q.id=qi.quote_id
                   WHERE q.id=c.quote_id AND q.status='accepted'),0)
    ), updated_at=now() WHERE c.id=p_campaign_id;
  PERFORM _ad_audit('payment', v_id, 'verified', NULL, jsonb_build_object('amount_cents',p_amount_cents,'kind',p_kind));
  RETURN v_id;
END $$;

-- ── Admin: activate / pause / resume / cancel with full gate checks ──────────
CREATE OR REPLACE FUNCTION public.ad_activate_campaign(p_campaign_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE c record; v_placement bigint;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT * INTO c FROM ad_campaigns WHERE id=p_campaign_id;
  IF c.id IS NULL THEN RAISE EXCEPTION 'campaign not found'; END IF;
  IF c.creative_id IS NULL OR NOT EXISTS (SELECT 1 FROM ad_creatives WHERE id=c.creative_id AND status='approved')
    THEN RAISE EXCEPTION 'approved creative required'; END IF;
  IF c.starts_at IS NULL OR c.ends_at IS NULL THEN RAISE EXCEPTION 'schedule required'; END IF;
  IF NOT EXISTS (SELECT 1 FROM ad_bookings WHERE campaign_id=c.id AND status='confirmed') THEN
    RAISE EXCEPTION 'confirmed booking required'; END IF;
  -- if the campaign has placement charges, require accepted quote + payment satisfied
  SELECT COALESCE(SUM(qi.amount_cents),0) INTO v_placement FROM ad_quote_items qi
    JOIN ad_quotes q ON q.id=qi.quote_id WHERE q.id=c.quote_id AND qi.kind='placement';
  IF v_placement > 0 THEN
    IF NOT EXISTS (SELECT 1 FROM ad_quotes WHERE id=c.quote_id AND status='accepted') THEN
      RAISE EXCEPTION 'accepted quote required'; END IF;
    IF NOT c.payment_satisfied THEN RAISE EXCEPTION 'payment not satisfied'; END IF;
  END IF;
  UPDATE ad_campaigns SET status='active', pause_reason=NULL, updated_at=now() WHERE id=p_campaign_id;
  PERFORM _ad_audit('campaign', p_campaign_id, 'activated');
END $$;

CREATE OR REPLACE FUNCTION public.ad_set_campaign_state(p_campaign_id uuid, p_action text, p_reason text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  IF p_action='pause' THEN
    UPDATE ad_campaigns SET status='paused', pause_reason=p_reason, updated_at=now()
      WHERE id=p_campaign_id AND status='active';
  ELSIF p_action='resume' THEN
    UPDATE ad_campaigns SET status='active', pause_reason=NULL, updated_at=now()
      WHERE id=p_campaign_id AND status='paused';
  ELSIF p_action='cancel' THEN
    UPDATE ad_campaigns SET status='cancelled', cancel_reason=p_reason, updated_at=now()
      WHERE id=p_campaign_id AND status<>'cancelled';
    UPDATE ad_bookings SET status='released' WHERE campaign_id=p_campaign_id AND status IN ('reserved','confirmed');
  ELSE RAISE EXCEPTION 'bad action'; END IF;
  IF NOT FOUND THEN RAISE EXCEPTION 'no matching campaign state for %', p_action; END IF;
  PERFORM _ad_audit('campaign', p_campaign_id, p_action, p_reason);
END $$;

-- ── Customer-facing: selection RPC (safe fields only) ───────────────────────
-- Returns eligible sponsored ads for the placement + delivery point. Enforces
-- schedule at fetch time (so expired ads stop serving even if a scheduler fails).
CREATE OR REPLACE FUNCTION public.get_sponsored_ads(p_lat double precision DEFAULT NULL,
  p_lng double precision DEFAULT NULL, p_limit int DEFAULT 3)
RETURNS TABLE(campaign_id uuid, creative_id uuid, restaurant_id uuid, restaurant_name text,
  logo_url text, media_type text, playback_url text, thumbnail_url text, captions_url text,
  headline text, destination_type text, destination_dish_id uuid)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path=public AS $$
  WITH s AS (SELECT enabled, session_exposure_limit, serve_radius_km FROM ad_settings WHERE id=1)
  SELECT c.id, cr.id, c.restaurant_id,
         COALESCE(r.chain_name, r.name), r.image_url, cr.media_type, cr.playback_url,
         cr.thumbnail_url, cr.captions_url, COALESCE(cr.headline, c.destination_type),
         c.destination_type, c.destination_dish_id
  FROM ad_campaigns c
  JOIN ad_creatives cr ON cr.id=c.creative_id AND cr.status='approved'
  JOIN ad_requests  rq ON rq.id=c.request_id
  JOIN restaurants  r  ON r.id=c.restaurant_id
  CROSS JOIN s
  WHERE s.enabled = true
    AND c.status='active'
    AND c.payment_satisfied = true
    AND c.starts_at <= now() AND c.ends_at > now()
    AND EXISTS (SELECT 1 FROM ad_bookings b WHERE b.campaign_id=c.id AND b.status='confirmed')
    AND r.is_verified = true
    AND (p_lat IS NULL OR p_lng IS NULL OR r.latitude IS NULL OR r.longitude IS NULL
         OR 6371 * acos(LEAST(1, GREATEST(-1,
              cos(radians(p_lat))*cos(radians(r.latitude))*cos(radians(r.longitude)-radians(p_lng))
              + sin(radians(p_lat))*sin(radians(r.latitude))))) <= s.serve_radius_km)
  ORDER BY random()               -- fair-ish rotation; refined per-session client-side
  LIMIT LEAST(GREATEST(p_limit,0), (SELECT session_exposure_limit FROM s));
$$;
REVOKE ALL ON FUNCTION public.get_sponsored_ads(double precision,double precision,int) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_sponsored_ads(double precision,double precision,int) TO anon, authenticated;

-- ── Customer-facing: event ingest (deduped; user pinned to auth.uid) ────────
CREATE OR REPLACE FUNCTION public.ad_record_event(p_campaign_id uuid, p_event_type text,
  p_session_id text, p_creative_id uuid DEFAULT NULL, p_dedupe_key text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF p_event_type NOT IN ('impression','video_start','video_complete','cta_click') THEN
    RAISE EXCEPTION 'bad event type'; END IF;
  INSERT INTO ad_events(campaign_id, creative_id, event_type, session_id, user_id, dedupe_key)
  VALUES (p_campaign_id, p_creative_id, p_event_type, p_session_id, auth.uid(),
          COALESCE(p_dedupe_key, p_session_id||':'||p_campaign_id||':'||p_event_type))
  ON CONFLICT (dedupe_key) DO NOTHING;  -- widget rebuilds / loops don't inflate
END $$;
REVOKE ALL ON FUNCTION public.ad_record_event(uuid,text,text,uuid,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ad_record_event(uuid,text,text,uuid,text) TO anon, authenticated;

-- ── Attribution: called when an order reaches completed/delivered ───────────
-- Last eligible cta_click within 24h, same restaurant, one campaign, deduped.
CREATE OR REPLACE FUNCTION public.ad_attribute_order(p_order_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE o record; v_campaign uuid;
BEGIN
  SELECT id, user_id, restaurant_id, status, created_at INTO o FROM orders WHERE id=p_order_id;
  IF o.id IS NULL OR o.user_id IS NULL THEN RETURN; END IF;
  IF o.status NOT IN ('delivered','completed') THEN RETURN; END IF;
  IF EXISTS (SELECT 1 FROM ad_order_attributions WHERE order_id=p_order_id) THEN RETURN; END IF;
  SELECT e.campaign_id INTO v_campaign
  FROM ad_events e JOIN ad_campaigns c ON c.id=e.campaign_id
  WHERE e.event_type='cta_click' AND e.user_id=o.user_id
    AND c.restaurant_id=o.restaurant_id
    AND e.created_at >= o.created_at - interval '24 hours'
    AND e.created_at <= o.created_at
  ORDER BY e.created_at DESC LIMIT 1;
  IF v_campaign IS NULL THEN RETURN; END IF;
  INSERT INTO ad_order_attributions(order_id, campaign_id) VALUES (p_order_id, v_campaign)
    ON CONFLICT (order_id) DO NOTHING;
  PERFORM _ad_audit('attribution', v_campaign, 'order_attributed', NULL, jsonb_build_object('order',p_order_id));
END $$;

-- ── Daily metrics rollup (Jamaica day). Admin/cron. ─────────────────────────
CREATE OR REPLACE FUNCTION public.ad_rebuild_daily_metrics(p_campaign_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  DELETE FROM ad_daily_metrics WHERE campaign_id=p_campaign_id;
  INSERT INTO ad_daily_metrics(campaign_id, day, impressions, video_starts, video_completions, cta_clicks)
  SELECT campaign_id,
         (created_at AT TIME ZONE 'America/Jamaica')::date AS day,
         count(*) FILTER (WHERE event_type='impression'),
         count(*) FILTER (WHERE event_type='video_start'),
         count(*) FILTER (WHERE event_type='video_complete'),
         count(*) FILTER (WHERE event_type='cta_click')
  FROM ad_events WHERE campaign_id=p_campaign_id
  GROUP BY 1,2;
  -- attributed orders per Jamaica day
  UPDATE ad_daily_metrics m SET attributed_orders = sub.n
  FROM (SELECT a.campaign_id, (o.created_at AT TIME ZONE 'America/Jamaica')::date d, count(*) n
        FROM ad_order_attributions a JOIN orders o ON o.id=a.order_id
        WHERE a.campaign_id=p_campaign_id GROUP BY 1,2) sub
  WHERE m.campaign_id=sub.campaign_id AND m.day=sub.d;
END $$;

-- grants for internal-use RPCs (gate internally)
GRANT EXECUTE ON FUNCTION public.ad_submit_request(uuid), public.ad_review_request(uuid,text,text),
  public.ad_issue_quote(uuid,jsonb,timestamptz), public.ad_respond_quote(uuid,boolean),
  public.ad_new_creative(uuid,text,text,text,text,text,text,boolean),
  public.ad_mark_creative_ready(uuid,text,text,int,int,int), public.ad_decide_creative(uuid,boolean,text),
  public.ad_reserve_booking(uuid,int,timestamptz,timestamptz),
  public.ad_verify_payment(uuid,bigint,text,text,text,text,jsonb),
  public.ad_activate_campaign(uuid), public.ad_set_campaign_state(uuid,text,text),
  public.ad_attribute_order(uuid), public.ad_rebuild_daily_metrics(uuid)
  TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Admin creates a campaign from an approved request + approved creative (+ quote
-- when there are placement charges). The campaign still needs a booking, payment
-- and activation before it can serve (enforced by ad_activate_campaign).
CREATE OR REPLACE FUNCTION public.ad_create_campaign(
  p_request_id uuid,
  p_creative_id uuid,
  p_quote_id uuid DEFAULT NULL,
  p_destination_type text DEFAULT 'menu',
  p_destination_dish_id uuid DEFAULT NULL
)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v_rest uuid; v_cid uuid;
BEGIN
  IF NOT is_admin() THEN RAISE EXCEPTION 'admin only'; END IF;
  SELECT restaurant_id INTO v_rest FROM ad_requests WHERE id = p_request_id;
  IF v_rest IS NULL THEN RAISE EXCEPTION 'request not found'; END IF;
  IF NOT EXISTS (SELECT 1 FROM ad_creatives WHERE id=p_creative_id AND request_id=p_request_id) THEN
    RAISE EXCEPTION 'creative does not belong to request'; END IF;
  -- destination dish (if any) must belong to the requesting restaurant
  IF p_destination_type='dish' AND p_destination_dish_id IS NOT NULL THEN
    IF NOT EXISTS (SELECT 1 FROM menus WHERE id=p_destination_dish_id AND restaurant_id=v_rest) THEN
      RAISE EXCEPTION 'destination dish not owned by restaurant'; END IF;
  END IF;
  INSERT INTO ad_campaigns(request_id, restaurant_id, creative_id, quote_id,
      destination_type, destination_dish_id, status)
    VALUES (p_request_id, v_rest, p_creative_id, p_quote_id,
      p_destination_type, p_destination_dish_id, 'scheduled')
    RETURNING id INTO v_cid;
  PERFORM _ad_audit('campaign', v_cid, 'created', NULL,
    jsonb_build_object('request',p_request_id,'creative',p_creative_id));
  RETURN v_cid;
END $$;
GRANT EXECUTE ON FUNCTION public.ad_create_campaign(uuid,uuid,uuid,text,uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';

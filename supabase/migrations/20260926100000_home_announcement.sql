-- Admin-configurable home notice banner. Lets an admin put any message on the
-- home screen offer-banner spot (e.g. "We're closing early today") instead of
-- only the apology coupon. Three app_config keys + one admin setter.
INSERT INTO app_config(key, value)
SELECT * FROM (VALUES
  ('home_announcement_text', ''),
  ('home_announcement_active', 'false'),
  ('home_announcement_style', 'notice')     -- notice | warning | info
) AS v(key, value)
WHERE NOT EXISTS (SELECT 1 FROM app_config a WHERE a.key = v.key);

CREATE OR REPLACE FUNCTION public.admin_set_home_announcement(
  p_text text, p_active boolean, p_style text DEFAULT 'notice')
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE v_admin uuid;
BEGIN
  v_admin := public.require_admin();
  INSERT INTO app_config(key,value) VALUES ('home_announcement_text', COALESCE(p_text,''))
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  INSERT INTO app_config(key,value) VALUES ('home_announcement_active', CASE WHEN p_active THEN 'true' ELSE 'false' END)
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  INSERT INTO app_config(key,value) VALUES ('home_announcement_style', COALESCE(p_style,'notice'))
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
  RETURN jsonb_build_object('ok',true,'active',p_active,'style',p_style);
END;
$$;
GRANT EXECUTE ON FUNCTION public.admin_set_home_announcement(text,boolean,text) TO authenticated;

-- Read helper (any authenticated user; customers show the banner).
CREATE OR REPLACE FUNCTION public.home_announcement()
RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$
  SELECT jsonb_build_object(
    'active', COALESCE((SELECT value FROM app_config WHERE key='home_announcement_active'),'false')='true',
    'text',   COALESCE((SELECT value FROM app_config WHERE key='home_announcement_text'),''),
    'style',  COALESCE((SELECT value FROM app_config WHERE key='home_announcement_style'),'notice'));
$$;
GRANT EXECUTE ON FUNCTION public.home_announcement() TO authenticated, anon;

NOTIFY pgrst, 'reload schema';

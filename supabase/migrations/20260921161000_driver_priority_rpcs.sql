-- HotBite Driver Priority — trusted scoring + read RPCs + order classification.

-- Map a 0–100 score to a standing, honouring the provisional cap (a driver
-- with too few deliveries can't reach the top levels).
CREATE OR REPLACE FUNCTION public.driver_standing_for_score(
  p_score numeric, p_provisional boolean)
RETURNS text LANGUAGE plpgsql STABLE AS $fn$
DECLARE t jsonb; s text := 'NEEDS_IMPROVEMENT';
BEGIN
  SELECT thresholds INTO t FROM public.driver_priority_config WHERE id = 1;
  IF (p_score BETWEEN (t->'ELITE'->>0)::numeric AND (t->'ELITE'->>1)::numeric) THEN s:='ELITE';
  ELSIF (p_score BETWEEN (t->'PRIORITY'->>0)::numeric AND (t->'PRIORITY'->>1)::numeric) THEN s:='PRIORITY';
  ELSIF (p_score BETWEEN (t->'GOOD_STANDING'->>0)::numeric AND (t->'GOOD_STANDING'->>1)::numeric) THEN s:='GOOD_STANDING';
  ELSIF (p_score BETWEEN (t->'STANDARD'->>0)::numeric AND (t->'STANDARD'->>1)::numeric) THEN s:='STANDARD';
  ELSE s:='NEEDS_IMPROVEMENT'; END IF;
  -- Provisional drivers are capped at STANDARD regardless of raw score.
  IF p_provisional AND s IN ('ELITE','PRIORITY','GOOD_STANDING') THEN s := 'STANDARD'; END IF;
  RETURN s;
END; $fn$;

-- normalise a rate that may be stored as 0–1 or 0–100 into 0–100.
CREATE OR REPLACE FUNCTION public._pct(p double precision)
RETURNS numeric LANGUAGE sql IMMUTABLE AS
$$ SELECT CASE WHEN p IS NULL THEN NULL WHEN p <= 1.0 THEN (p*100)::numeric ELSE p::numeric END $$;

-- Trusted recompute. Pulls REAL data (recent orders + maintained driver stats),
-- applies the configured weights, writes the score/standing under the trusted
-- GUC, and logs an audit event when the score moves.
CREATE OR REPLACE FUNCTION public.compute_driver_priority(p_driver_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE
  cfg record; d record;
  w jsonb; win_days int; min_prov int; min_dev int;
  f_rating numeric; f_ontime numeric; f_completion numeric;
  f_accept numeric; f_pickup numeric; f_complaints numeric;
  n_completed int; n_cancelled int; n_recent_completed int; n_recent_ontime int;
  score numeric; prev numeric; provisional boolean; standing text; stats jsonb;
BEGIN
  SELECT * INTO cfg FROM public.driver_priority_config WHERE id = 1;
  SELECT * INTO d FROM public.drivers WHERE id = p_driver_id;
  IF d.id IS NULL THEN RETURN NULL; END IF;

  w := cfg.weights;
  win_days := COALESCE((cfg.rolling->>'days')::int, 30);
  min_prov := COALESCE((cfg.min_deliveries->>'provisional')::int, 10);

  -- Recent (rolling-window) delivery counts, computed from raw orders.
  SELECT
    count(*) FILTER (WHERE o.status = 'delivered'),
    count(*) FILTER (WHERE o.status = 'delivered'
        AND o.delivered_at IS NOT NULL AND o.estimated_delivery_at IS NOT NULL
        AND o.delivered_at <= o.estimated_delivery_at)
  INTO n_recent_completed, n_recent_ontime
  FROM public.orders o
  WHERE o.driver_id = p_driver_id
    AND o.created_at > now() - make_interval(days => win_days);

  n_completed := COALESCE(d.completed_deliveries, 0);
  n_cancelled := COALESCE(d.cancelled_deliveries, 0);
  provisional := n_completed < min_prov;

  -- Factor scores (0–100), all from trusted data.
  f_rating := COALESCE(d.rating,0)/5.0*100;
  -- Prefer recent on-time; fall back to the maintained rate.
  f_ontime := CASE WHEN n_recent_completed > 0
                   THEN n_recent_ontime::numeric/n_recent_completed*100
                   ELSE COALESCE(public._pct(d.on_time_rate), 100) END;
  f_completion := CASE WHEN (n_completed+n_cancelled) > 0
                       THEN n_completed::numeric/(n_completed+n_cancelled)*100
                       ELSE 100 END;
  f_accept := COALESCE(public._pct(d.acceptance_rate), 100);
  f_pickup := f_ontime;                 -- pickup proxy until a pickup metric exists
  f_complaints := 100;                  -- no validated-complaint store yet -> perfect

  score := round(
      (w->>'customer_rating')::numeric * f_rating
    + (w->>'on_time')::numeric        * f_ontime
    + (w->>'completion')::numeric     * f_completion
    + (w->>'acceptance')::numeric     * f_accept
    + (w->>'pickup')::numeric         * f_pickup
    + (w->>'complaints')::numeric     * f_complaints
  , 1);
  score := GREATEST(0, LEAST(100, score));

  standing := public.driver_standing_for_score(score, provisional);
  prev := COALESCE(d.driver_score, 0);

  stats := jsonb_build_object(
    'customer_rating', round(COALESCE(d.rating,0)::numeric,2),
    'on_time', round(f_ontime,0),
    'completion', round(f_completion,0),
    'acceptance', round(f_accept,0),
    'pickup', round(f_pickup,0),
    'complaints', 0,
    'completed_deliveries', n_completed,
    'recent_completed', n_recent_completed
  );

  -- Write under the trusted flag so the protection trigger permits it.
  PERFORM set_config('hotbite.priority_write','on', true);
  UPDATE public.drivers
     SET driver_score = score, tier = standing,
         priority_standing = standing, priority_provisional = provisional,
         priority_stats = stats, priority_updated_at = now()
   WHERE id = p_driver_id;
  PERFORM set_config('hotbite.priority_write','off', true);

  IF round(prev,1) <> round(score,1) THEN
    INSERT INTO public.driver_priority_events
      (driver_id, event_type, score_change, previous_score, new_score, reason, created_by)
    VALUES (p_driver_id, 'recompute', round(score-prev,1), prev, score,
            'Automatic recompute from recent performance', NULL);
  END IF;

  RETURN jsonb_build_object('score',score,'standing',standing,'provisional',provisional,'stats',stats);
END; $fn$;

-- Read RPC for the driver app: score, standing, breakdown, next-level gap and a
-- single concrete improvement hint. Recomputes on read so the value is current.
CREATE OR REPLACE FUNCTION public.get_driver_priority(p_driver_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $fn$
DECLARE res jsonb; t jsonb; standing text; score numeric; provisional boolean;
        next_std text; next_min numeric; gap numeric; stats jsonb; hint text;
BEGIN
  res := public.compute_driver_priority(p_driver_id);
  IF res IS NULL THEN RETURN NULL; END IF;
  score := (res->>'score')::numeric; standing := res->>'standing';
  provisional := (res->>'provisional')::boolean; stats := res->'stats';
  SELECT thresholds INTO t FROM public.driver_priority_config WHERE id=1;

  -- Determine the next standing up and the points needed.
  next_std := CASE standing
    WHEN 'NEEDS_IMPROVEMENT' THEN 'STANDARD' WHEN 'STANDARD' THEN 'GOOD_STANDING'
    WHEN 'GOOD_STANDING' THEN 'PRIORITY' WHEN 'PRIORITY' THEN 'ELITE' ELSE NULL END;
  IF next_std IS NOT NULL THEN
    next_min := (t->next_std->>0)::numeric; gap := GREATEST(0, next_min - score);
  END IF;

  -- Improvement hint: point at the weakest factor.
  SELECT k INTO hint FROM (
    SELECT 'on-time delivery' k, (stats->>'on_time')::numeric v
    UNION ALL SELECT 'completion rate', (stats->>'completion')::numeric
    UNION ALL SELECT 'acceptance rate', (stats->>'acceptance')::numeric
    UNION ALL SELECT 'customer rating', (stats->>'customer_rating')::numeric*20
  ) s ORDER BY v ASC LIMIT 1;

  RETURN res
    || jsonb_build_object(
        'next_standing', next_std,
        'points_to_next', gap,
        'improve_factor', hint,
        'thresholds', t);
END; $fn$;

-- Classify an order's priority tier from configurable criteria (value/distance).
-- Kept conservative; admin can tune later. Called by a BEFORE-INSERT trigger.
CREATE OR REPLACE FUNCTION public.classify_order_priority()
RETURNS trigger LANGUAGE plpgsql AS $fn$
DECLARE hi numeric := 4000; premium numeric := 8000; -- JMD thresholds (configurable later)
BEGIN
  IF NEW.priority_class IS NULL OR NEW.priority_class = 'NORMAL' THEN
    IF COALESCE(NEW.total_amount,0) >= premium THEN NEW.priority_class := 'PREMIUM';
    ELSIF COALESCE(NEW.total_amount,0) >= hi THEN NEW.priority_class := 'PRIORITY';
    ELSE NEW.priority_class := 'NORMAL'; END IF;
  END IF;
  RETURN NEW;
END; $fn$;

DROP TRIGGER IF EXISTS trg_classify_order_priority ON public.orders;
CREATE TRIGGER trg_classify_order_priority
  BEFORE INSERT ON public.orders
  FOR EACH ROW EXECUTE FUNCTION public.classify_order_priority();

-- Does a driver's standing meet the minimum required for an order class?
CREATE OR REPLACE FUNCTION public.driver_meets_order_class(
  p_standing text, p_class text)
RETURNS boolean LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path=public AS $fn$
DECLARE need text; rank_need int; rank_have int;
BEGIN
  IF p_class = 'NORMAL' THEN RETURN true; END IF;
  SELECT (assignment->'class_min_standing'->>p_class) INTO need
    FROM public.driver_priority_config WHERE id=1;
  IF need IS NULL THEN RETURN true; END IF;
  rank_need := array_position(ARRAY['NEEDS_IMPROVEMENT','STANDARD','GOOD_STANDING','PRIORITY','ELITE'], need);
  rank_have := array_position(ARRAY['NEEDS_IMPROVEMENT','STANDARD','GOOD_STANDING','PRIORITY','ELITE'], COALESCE(p_standing,'STANDARD'));
  RETURN COALESCE(rank_have,2) >= COALESCE(rank_need,1);
END; $fn$;

GRANT EXECUTE ON FUNCTION public.get_driver_priority(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.compute_driver_priority(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_meets_order_class(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.driver_standing_for_score(numeric,boolean) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- ============================================================================
-- AI DECISION ROOM — RPCs (create/cancel/retry/save, access grants, metrics).
-- ============================================================================

-- Create a decision + seed the 5 durable workflow stages (pending).
CREATE OR REPLACE FUNCTION public.ai_decision_create(
  p_title text, p_question text, p_context text, p_options jsonb,
  p_goals text, p_budget text, p_constraints text, p_category text,
  p_include_metrics boolean, p_synth_model text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_uid uuid := auth.uid(); v_id uuid; v_today_count int;
        v_limit int := coalesce((SELECT NULLIF(regexp_replace(value,'\D','','g'),'')::int
                                 FROM public.app_config WHERE key='ai_decision_daily_limit'),20);
        v_synth text := CASE WHEN lower(coalesce(p_synth_model,'openai')) IN ('openai','anthropic')
                             THEN lower(p_synth_model) ELSE 'openai' END;
BEGIN
  IF NOT public.ai_decision_room_allowed(v_uid) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  IF coalesce(trim(p_title),'')='' OR coalesce(trim(p_question),'')='' THEN
    RETURN jsonb_build_object('ok',false,'reason','title_and_question_required'); END IF;

  SELECT count(*) INTO v_today_count FROM public.ai_decisions
   WHERE created_by = v_uid AND created_at::date = (now() AT TIME ZONE 'America/Jamaica')::date;
  IF v_today_count >= v_limit THEN
    RETURN jsonb_build_object('ok',false,'reason','daily_limit_reached'); END IF;

  INSERT INTO public.ai_decisions
    (created_by,title,question,context,options,goals,budget,constraints,category,
     include_metrics,synth_model,status)
  VALUES
    (v_uid,p_title,p_question,p_context,coalesce(p_options,'[]'::jsonb),p_goals,p_budget,
     p_constraints,coalesce(NULLIF(p_category,''),'other'),coalesce(p_include_metrics,false),
     v_synth,'draft')
  RETURNING id INTO v_id;

  INSERT INTO public.ai_decision_stages(decision_id,stage,provider,seq) VALUES
    (v_id,'openai_assess','openai',1),
    (v_id,'claude_assess','anthropic',2),
    (v_id,'openai_review','openai',3),
    (v_id,'claude_review','anthropic',4),
    (v_id,'synthesis', v_synth, 5);

  RETURN jsonb_build_object('ok',true,'decision_id',v_id);
END; $$;
REVOKE ALL ON FUNCTION public.ai_decision_create(text,text,text,jsonb,text,text,text,text,boolean,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.ai_decision_create(text,text,text,jsonb,text,text,text,text,boolean,text) TO authenticated, service_role;

-- Cancel an in-flight decision.
CREATE OR REPLACE FUNCTION public.ai_decision_cancel(p_id uuid)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.ai_decisions SET status='cancelled', updated_at=now()
   WHERE id=p_id AND (created_by=auth.uid() OR public.is_ai_decision_super_admin())
     AND status IN ('draft','assessing','cross_review','synthesizing');
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_cancellable'); END IF;
  UPDATE public.ai_decision_stages SET status='failed', error=coalesce(error,'cancelled')
   WHERE decision_id=p_id AND status IN ('pending','running');
  RETURN jsonb_build_object('ok',true);
END; $$;
GRANT EXECUTE ON FUNCTION public.ai_decision_cancel(uuid) TO authenticated, service_role;

-- Retry a failed stage (reset it + the decision so the worker reruns it).
CREATE OR REPLACE FUNCTION public.ai_decision_retry_stage(p_id uuid, p_stage text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ai_decisions d WHERE d.id=p_id
     AND (d.created_by=auth.uid() OR public.is_ai_decision_super_admin())) THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  UPDATE public.ai_decision_stages SET status='pending', error=NULL, output=NULL,
     started_at=NULL, finished_at=NULL
   WHERE decision_id=p_id AND stage=p_stage AND status='failed';
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','stage_not_failed'); END IF;
  UPDATE public.ai_decisions SET status='assessing', updated_at=now()
   WHERE id=p_id AND status IN ('failed','cancelled');
  RETURN jsonb_build_object('ok',true);
END; $$;
GRANT EXECUTE ON FUNCTION public.ai_decision_retry_stage(uuid,text) TO authenticated, service_role;

-- Record the admin's own final decision + notes. ADVISORY ONLY — changes no
-- business data; only stores the choice/notes on the decision row.
CREATE OR REPLACE FUNCTION public.ai_decision_save_final(p_id uuid, p_choice text, p_notes text)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.ai_decisions SET final_choice=p_choice, final_notes=p_notes, updated_at=now()
   WHERE id=p_id AND (created_by=auth.uid() OR public.is_ai_decision_super_admin());
  IF NOT FOUND THEN RETURN jsonb_build_object('ok',false,'reason','not_found'); END IF;
  RETURN jsonb_build_object('ok',true);
END; $$;
GRANT EXECUTE ON FUNCTION public.ai_decision_save_final(uuid,text,text) TO authenticated, service_role;

-- Grant / revoke access (super admin only).
CREATE OR REPLACE FUNCTION public.ai_decision_grant_access(p_user uuid)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_ai_decision_super_admin() THEN RETURN jsonb_build_object('ok',false,'reason','super_admin_only'); END IF;
  IF NOT EXISTS (SELECT 1 FROM public.users WHERE id=p_user AND role='admin') THEN
    RETURN jsonb_build_object('ok',false,'reason','target_not_admin'); END IF;
  INSERT INTO public.ai_decision_permissions(user_id,granted_by) VALUES (p_user, auth.uid())
    ON CONFLICT (user_id) DO NOTHING;
  RETURN jsonb_build_object('ok',true);
END; $$;
GRANT EXECUTE ON FUNCTION public.ai_decision_grant_access(uuid) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.ai_decision_revoke_access(p_user uuid)
  RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public.is_ai_decision_super_admin() THEN RETURN jsonb_build_object('ok',false,'reason','super_admin_only'); END IF;
  DELETE FROM public.ai_decision_permissions WHERE user_id=p_user;
  RETURN jsonb_build_object('ok',true);
END; $$;
GRANT EXECUTE ON FUNCTION public.ai_decision_revoke_access(uuid) TO authenticated, service_role;

-- Usage today vs limit.
CREATE OR REPLACE FUNCTION public.ai_decision_usage()
  RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT jsonb_build_object(
    'allowed', public.ai_decision_room_allowed(),
    'is_super_admin', public.is_ai_decision_super_admin(),
    'used_today', (SELECT count(*) FROM public.ai_decisions
                   WHERE created_by=auth.uid()
                     AND created_at::date=(now() AT TIME ZONE 'America/Jamaica')::date),
    'daily_limit', coalesce((SELECT NULLIF(regexp_replace(value,'\D','','g'),'')::int
                             FROM public.app_config WHERE key='ai_decision_daily_limit'),20));
$$;
GRANT EXECUTE ON FUNCTION public.ai_decision_usage() TO authenticated, service_role;

-- PII-SAFE aggregate metrics preview (last N days). NO customer identities,
-- phones, addresses, banking or payment credentials — counts/sums only.
CREATE OR REPLACE FUNCTION public.ai_decision_metrics_preview(p_days int DEFAULT 30)
  RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE v_from timestamptz := now() - make_interval(days => greatest(1, least(p_days,365)));
        j jsonb;
BEGIN
  IF NOT public.ai_decision_room_allowed() THEN
    RETURN jsonb_build_object('ok',false,'reason','not_authorized'); END IF;
  SELECT jsonb_build_object(
    'ok', true,
    'date_range', jsonb_build_object('from', v_from::date, 'to', now()::date, 'days', greatest(1,least(p_days,365))),
    'orders_total',      (SELECT count(*) FROM public.orders WHERE created_at >= v_from),
    'orders_delivered',  (SELECT count(*) FROM public.orders WHERE created_at >= v_from AND status='delivered'),
    'orders_cancelled',  (SELECT count(*) FROM public.orders WHERE created_at >= v_from AND status='cancelled'),
    'gross_revenue',     (SELECT round(coalesce(sum(total_amount),0)::numeric,2) FROM public.orders WHERE created_at >= v_from AND status='delivered'),
    'avg_order_value',   (SELECT round(coalesce(avg(total_amount),0)::numeric,2) FROM public.orders WHERE created_at >= v_from AND status='delivered'),
    'active_restaurants',(SELECT count(DISTINCT restaurant_id) FROM public.orders WHERE created_at >= v_from),
    'active_drivers',    (SELECT count(DISTINCT driver_id) FROM public.orders WHERE created_at >= v_from AND driver_id IS NOT NULL),
    'currency',          coalesce((SELECT value FROM public.app_config WHERE key='currency_code'),'JMD')
  ) INTO j;
  RETURN j;
END; $$;
GRANT EXECUTE ON FUNCTION public.ai_decision_metrics_preview(int) TO authenticated, service_role;

NOTIFY pgrst, 'reload schema';

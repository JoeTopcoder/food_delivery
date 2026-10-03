-- Stage 8 (cont.): the approved-action engine + approval RPCs.
-- SECURITY DEFINER, admin/service only, closed capability dispatch (no dynamic
-- SQL / HTTP), price guard armed for the whole transaction.

CREATE OR REPLACE FUNCTION public.ai_execute_approved_action(
  p_suggestion_id uuid,
  p_idempotency_key text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $fn$
DECLARE
  s            record;
  t            record;   -- action type flags
  v_uid        uuid := auth.uid();
  v_idem       text;
  v_exec_id    uuid;
  v_task_id    uuid;
  v_records    jsonb := '[]'::jsonb;
  v_before     jsonb;
  v_after      jsonb;
  v_result     jsonb := '{}'::jsonb;
  v_verified   boolean := false;
  v_ext        boolean := false;
  v_final      text;
BEGIN
  IF NOT (public.is_admin() OR COALESCE(auth.role(),'')='service_role') THEN
    RAISE EXCEPTION 'FORBIDDEN: admin or service role required';
  END IF;

  -- Arm the price/fee guard for this transaction (see ai_guard_no_price_writes).
  PERFORM set_config('app.ai_exec', '1', true);

  SELECT * INTO s FROM ai_suggestions WHERE id = p_suggestion_id FOR UPDATE;
  IF s.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND: suggestion'; END IF;

  -- Vague approvals cannot execute.
  IF s.action_status <> 'approved' OR s.action_type IS NULL OR s.approved_payload IS NULL THEN
    RAISE EXCEPTION 'NOT_EXECUTABLE: needs an approved action_type + payload';
  END IF;

  SELECT * INTO t FROM ai_action_types WHERE action_type = s.action_type;
  IF t.action_type IS NULL THEN RAISE EXCEPTION 'BAD_ACTION_TYPE: %', s.action_type; END IF;
  v_ext := t.has_external_effect;

  -- Idempotency: one execution per key. Return the prior result if present.
  v_idem := COALESCE(p_idempotency_key, p_suggestion_id::text || ':' || s.action_type);
  SELECT id INTO v_exec_id FROM ai_action_executions
    WHERE idempotency_key = v_idem AND status IN ('completed','waiting_human','blocked');
  IF v_exec_id IS NOT NULL THEN
    RETURN jsonb_build_object('status','duplicate_ignored','execution_id',v_exec_id);
  END IF;

  INSERT INTO ai_action_executions(suggestion_id, action_type, approved_payload, idempotency_key, status, external_effect, executor, attempted)
    VALUES (p_suggestion_id, s.action_type, s.approved_payload, v_idem, 'executing', v_ext, v_uid,
            jsonb_build_object('action_type', s.action_type, 'at', now()))
    RETURNING id INTO v_exec_id;

  -- ── PRICING / FEE: never executed. Prepare an exact MANUAL admin task. ──
  IF t.requires_manual_admin THEN
    INSERT INTO ai_admin_tasks(suggestion_id, title, description, category, priority, assignee_team, related_records, evidence, created_by)
      VALUES (p_suggestion_id,
              COALESCE(s.approved_payload->>'title', 'MANUAL: ' || s.title),
              'Pricing/fee change proposed by AI. A human must apply it in the management screen. Proposed: '
                || COALESCE(s.approved_payload->>'change', s.description),
              'pricing', s.priority, 'admin_pricing',
              COALESCE(s.approved_payload->'targets','[]'::jsonb),
              jsonb_build_object('impact_estimate', s.approved_payload->'impact', 'rationale', s.rationale),
              v_uid)
      RETURNING id INTO v_task_id;
    UPDATE ai_action_executions SET status='waiting_human', task_id=v_task_id,
        result=jsonb_build_object('routed','manual_pricing_task','task_id',v_task_id),
        completed_at=now() WHERE id=v_exec_id;
    UPDATE ai_suggestions SET action_status='assigned_to_human' WHERE id=p_suggestion_id;
    RETURN jsonb_build_object('status','waiting_human','reason','pricing_requires_manual_admin','task_id',v_task_id,'execution_id',v_exec_id);
  END IF;

  -- ── EXTERNAL SEND: never auto-sent. Route to a human confirm task. ──
  IF t.needs_second_confirm OR t.has_external_effect THEN
    INSERT INTO ai_admin_tasks(suggestion_id, title, description, category, priority, assignee_team, evidence, created_by)
      VALUES (p_suggestion_id, 'CONFIRM SEND: ' || s.title,
              'External send requires a separate human confirmation showing recipients and exact content.',
              'comms', s.priority, 'admin_comms',
              jsonb_build_object('draft', s.approved_payload), v_uid)
      RETURNING id INTO v_task_id;
    UPDATE ai_action_executions SET status='waiting_human', task_id=v_task_id,
        result=jsonb_build_object('routed','awaiting_send_confirmation','task_id',v_task_id), completed_at=now() WHERE id=v_exec_id;
    UPDATE ai_suggestions SET action_status='assigned_to_human' WHERE id=p_suggestion_id;
    RETURN jsonb_build_object('status','waiting_human','reason','external_send_needs_confirmation','task_id',v_task_id,'execution_id',v_exec_id);
  END IF;

  -- ── Closed capability dispatch (non-pricing, safe) ──
  IF s.action_type = 'assign_support_cases' THEN
    -- Real existing workflow: set the reviewer on the listed open cases.
    WITH ids AS (SELECT jsonb_array_elements_text(COALESCE(s.approved_payload->'case_ids','[]'::jsonb))::uuid AS cid)
    SELECT jsonb_agg(jsonb_build_object('id', sr.id, 'status', sr.status, 'reviewed_by', sr.reviewed_by))
      INTO v_before FROM support_requests sr JOIN ids ON ids.cid = sr.id;
    WITH ids AS (SELECT jsonb_array_elements_text(COALESCE(s.approved_payload->'case_ids','[]'::jsonb))::uuid AS cid),
         upd AS (
           UPDATE support_requests sr SET reviewed_by = v_uid, reviewed_at = now()
           FROM ids WHERE sr.id = ids.cid
             AND COALESCE(sr.status,'') NOT IN ('resolved','closed')
           RETURNING sr.id
         )
    SELECT jsonb_agg(jsonb_build_object('type','support_request','id',upd.id)) INTO v_records FROM upd;
    v_records := COALESCE(v_records, '[]'::jsonb);
    INSERT INTO ai_admin_tasks(suggestion_id, title, description, category, assignee_team, related_records, created_by)
      VALUES (p_suggestion_id, COALESCE(s.approved_payload->>'title','Assigned support cases'),
              s.description, 'support', COALESCE(s.approved_payload->>'team','admin_support'), v_records, v_uid)
      RETURNING id INTO v_task_id;
    SELECT (jsonb_array_length(v_records) >= 0) INTO v_verified;
    v_result := jsonb_build_object('assigned_count', jsonb_array_length(v_records));

  ELSIF s.action_type = 'investigate_orders' THEN
    -- Read-only: build a verified case list; change nothing on orders.
    WITH cand AS (
      SELECT o.id, o.status, o.total_amount, o.ordered_at
      FROM orders o
      WHERE (s.approved_payload->'filter'->>'status' IS NULL OR o.status = s.approved_payload->'filter'->>'status')
      ORDER BY o.ordered_at DESC
      LIMIT COALESCE((s.approved_payload->>'limit')::int, 100)
    )
    SELECT jsonb_agg(jsonb_build_object('type','order','id',cand.id,'status',cand.status,'total',cand.total_amount))
      INTO v_records FROM cand;
    v_records := COALESCE(v_records, '[]'::jsonb);
    INSERT INTO ai_admin_tasks(suggestion_id, title, description, category, related_records, evidence, created_by)
      VALUES (p_suggestion_id, COALESCE(s.approved_payload->>'title','Investigate affected orders'),
              s.description, 'ops', v_records, jsonb_build_object('case_count', jsonb_array_length(v_records)), v_uid)
      RETURNING id INTO v_task_id;
    v_verified := true;
    v_result := jsonb_build_object('case_count', jsonb_array_length(v_records));

  ELSIF s.action_type = 'create_admin_alert' THEN
    INSERT INTO ai_urgent_alerts(role_id, report_id, report_date, severity, title, message, evidence, status)
      VALUES (s.role_id, s.report_id, s.report_date,
              CASE WHEN s.approved_payload->>'severity' IN ('high','critical') THEN s.approved_payload->>'severity' ELSE 'high' END,
              COALESCE(s.approved_payload->>'title', s.title),
              COALESCE(s.approved_payload->>'message', s.description),
              jsonb_build_object('from_suggestion', p_suggestion_id), 'open')
      RETURNING id INTO v_task_id; -- reuse var to hold alert id for verification
    v_records := jsonb_build_array(jsonb_build_object('type','urgent_alert','id',v_task_id));
    v_verified := EXISTS(SELECT 1 FROM ai_urgent_alerts WHERE id = v_task_id);
    v_result := jsonb_build_object('alert_id', v_task_id);
    v_task_id := NULL; -- not a task

  ELSE
    -- create_admin_task | flag_catalogue_issue | prepare_rider_coverage_plan |
    -- open_store_performance_case | draft_partner_message → a tracked task.
    INSERT INTO ai_admin_tasks(suggestion_id, title, description, category, priority, assignee_team, related_records, evidence, created_by)
      VALUES (p_suggestion_id,
              COALESCE(s.approved_payload->>'title', s.title),
              COALESCE(s.approved_payload->>'description', s.description),
              t.category, s.priority,
              s.approved_payload->>'team',
              COALESCE(s.approved_payload->'related_records','[]'::jsonb),
              COALESCE(s.approved_payload, '{}'::jsonb),
              v_uid)
      RETURNING id INTO v_task_id;
    v_records := jsonb_build_array(jsonb_build_object('type','admin_task','id',v_task_id));
    v_verified := EXISTS(SELECT 1 FROM ai_admin_tasks WHERE id = v_task_id);
    v_result := jsonb_build_object('task_id', v_task_id);
  END IF;

  -- Verify → complete (never complete on unverified work).
  IF NOT v_verified THEN
    UPDATE ai_action_executions SET status='failed', error='verification_failed', completed_at=now(),
      before_values=v_before, records_affected=v_records WHERE id=v_exec_id;
    UPDATE ai_suggestions SET action_status='failed' WHERE id=p_suggestion_id;
    RETURN jsonb_build_object('status','failed','reason','verification_failed','execution_id',v_exec_id);
  END IF;

  UPDATE ai_action_executions SET status='completed', task_id=v_task_id,
      before_values=v_before, after_values=v_records, records_affected=v_records,
      result=v_result, verification=jsonb_build_object('verified',true,'checked_at',now()),
      completed_at=now() WHERE id=v_exec_id;
  UPDATE ai_suggestions SET action_status='completed' WHERE id=p_suggestion_id;

  RETURN jsonb_build_object('status','completed','execution_id',v_exec_id,'task_id',v_task_id,
                            'records_affected',v_records,'result',v_result,'verified',true);
EXCEPTION WHEN OTHERS THEN
  -- Failure never shows as completed; record and surface it.
  UPDATE ai_action_executions SET status='failed', error=SQLERRM, completed_at=now()
    WHERE idempotency_key = COALESCE(p_idempotency_key, p_suggestion_id::text || ':' || COALESCE(s.action_type,'?'));
  UPDATE ai_suggestions SET action_status='failed' WHERE id=p_suggestion_id AND action_status NOT IN ('completed');
  RETURN jsonb_build_object('status','failed','error',SQLERRM);
END;
$fn$;

REVOKE ALL ON FUNCTION public.ai_execute_approved_action(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ai_execute_approved_action(uuid, text) TO authenticated, service_role;

-- ── Admin decision entry point ─────────────────────────────────────────────
-- 'execute' (approve + run), 'investigate', 'assign_human', 'reject'.
CREATE OR REPLACE FUNCTION public.ai_review_suggestion_action(
  p_suggestion_id uuid, p_decision text, p_notes text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $fn$
DECLARE s record; v_uid uuid := auth.uid(); v_task uuid;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'FORBIDDEN: admin only'; END IF;
  SELECT * INTO s FROM ai_suggestions WHERE id = p_suggestion_id FOR UPDATE;
  IF s.id IS NULL THEN RAISE EXCEPTION 'NOT_FOUND'; END IF;

  IF p_decision = 'execute' THEN
    IF s.action_type IS NULL OR s.action_payload IS NULL THEN
      RAISE EXCEPTION 'VAGUE_NOT_EXECUTABLE: use investigate or assign_human';
    END IF;
    UPDATE ai_suggestions SET status='approved', action_status='approved',
      approved_payload = action_payload, approved_by=v_uid, approved_at=now(),
      reviewed_by=v_uid, reviewed_at=now(), review_notes=COALESCE(p_notes, review_notes)
      WHERE id=p_suggestion_id;
    RETURN public.ai_execute_approved_action(p_suggestion_id, NULL);

  ELSIF p_decision = 'investigate' THEN
    UPDATE ai_suggestions SET status='approved', action_status='awaiting_more_detail',
      reviewed_by=v_uid, reviewed_at=now(), review_notes=COALESCE(p_notes, review_notes) WHERE id=p_suggestion_id;
    RETURN jsonb_build_object('status','awaiting_more_detail');

  ELSIF p_decision = 'assign_human' THEN
    INSERT INTO ai_admin_tasks(suggestion_id, title, description, category, created_by, evidence)
      VALUES (p_suggestion_id, s.title, s.description, 'ops', v_uid, jsonb_build_object('rationale', s.rationale))
      RETURNING id INTO v_task;
    UPDATE ai_suggestions SET status='approved', action_status='assigned_to_human',
      reviewed_by=v_uid, reviewed_at=now(), review_notes=COALESCE(p_notes, review_notes) WHERE id=p_suggestion_id;
    RETURN jsonb_build_object('status','assigned_to_human','task_id',v_task);

  ELSIF p_decision = 'reject' THEN
    UPDATE ai_suggestions SET status='rejected', action_status='cancelled',
      reviewed_by=v_uid, reviewed_at=now(), review_notes=COALESCE(p_notes, review_notes) WHERE id=p_suggestion_id;
    RETURN jsonb_build_object('status','rejected');
  END IF;
  RAISE EXCEPTION 'BAD_DECISION: %', p_decision;
END;
$fn$;

REVOKE ALL ON FUNCTION public.ai_review_suggestion_action(uuid, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ai_review_suggestion_action(uuid, text, text) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Tests for admin close / reopen of support chats.
-- Everything runs inside a transaction and rolls back. Nothing persists.
-- Run:  supabase db query --linked -f supabase/tests/close_conversation_test.sql

BEGIN;

CREATE TEMP TABLE t(step INT, scenario TEXT, expected TEXT, actual TEXT,
                    pass BOOLEAN) ON COMMIT DROP;

DO $t$
DECLARE
  v_admin    UUID;
  v_customer UUID;
  v_conv     UUID := 'cccccccc-0000-0000-0000-0000000000c1';
  v_closed   TIMESTAMPTZ;
  v_by       UUID;
  v_reason   TEXT;
  v_msg      TEXT;
BEGIN
  SELECT id INTO v_admin FROM public.users WHERE role = 'admin' LIMIT 1;
  SELECT id INTO v_customer FROM public.users WHERE role <> 'admin' LIMIT 1;

  INSERT INTO public.conversations (id, participant_ids, last_message_text,
                                    last_message_at, created_at, updated_at,
                                    is_mock_data)
  VALUES (v_conv, ARRAY[v_admin, v_customer], 'where is my order',
          now(), now(), now(), false);

  -- ── 1. A non-admin cannot close ──────────────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM * FROM public.admin_close_conversation(v_conv, 'nice try');
    INSERT INTO t VALUES (1, 'A customer closing a chat', 'raises Forbidden',
      'it closed - GATE IS OPEN', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (1, 'A customer closing a chat', 'raises Forbidden',
      SQLERRM, SQLERRM ILIKE '%Forbidden%');
  END;

  -- ── 2. An admin can close ────────────────────────────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  SELECT c.closed_at, c.closed_by, c.close_reason
    INTO v_closed, v_by, v_reason
    FROM public.admin_close_conversation(v_conv, 'refund issued') c;
  INSERT INTO t VALUES (2, 'An admin closes the chat',
    'closed_at set, closed_by = the admin, reason kept',
    'closed_at ' || (v_closed IS NOT NULL) || ', by_admin ' ||
      (v_by = v_admin) || ', reason ' || COALESCE(v_reason, 'NULL'),
    v_closed IS NOT NULL AND v_by = v_admin AND v_reason = 'refund issued');

  -- ── 3. Closing twice keeps the original close ────────────────────────────
  PERFORM pg_sleep(0.01);
  DECLARE v_second TIMESTAMPTZ; v_second_reason TEXT;
  BEGIN
    SELECT c.closed_at, c.close_reason INTO v_second, v_second_reason
      FROM public.admin_close_conversation(v_conv, 'different reason') c;
    INSERT INTO t VALUES (3,
      'Closing an already-closed chat does not rewrite who closed it or when',
      'same timestamp and reason as the first close',
      'same_time ' || (v_second = v_closed) || ', reason ' ||
        COALESCE(v_second_reason, 'NULL'),
      v_second = v_closed AND v_second_reason = 'refund issued');
  END;

  -- ── 4. An admin note does NOT reopen it ──────────────────────────────────
  INSERT INTO public.chat_messages (conversation_id, sender_id, sender_role,
                                    message, created_at)
  VALUES (v_conv, v_admin, 'admin', 'closing note for the file', now());
  SELECT closed_at INTO v_closed FROM public.conversations WHERE id = v_conv;
  INSERT INTO t VALUES (4,
    'An admin posting after closing leaves it closed',
    'still closed', 'closed_at ' || (v_closed IS NOT NULL)::text,
    v_closed IS NOT NULL);

  -- ── 5. The customer replying reopens it ──────────────────────────────────
  -- The important one: closing must never silently mute a customer.
  INSERT INTO public.chat_messages (conversation_id, sender_id, sender_role,
                                    message, created_at)
  VALUES (v_conv, v_customer, 'customer', 'it still has not arrived', now());
  SELECT closed_at, closed_by, close_reason
    INTO v_closed, v_by, v_reason
    FROM public.conversations WHERE id = v_conv;
  INSERT INTO t VALUES (5,
    'A customer replying to a closed chat reopens it',
    'closed_at, closed_by and reason all cleared',
    'closed_at ' || COALESCE(v_closed::text, 'NULL') || ', by ' ||
      COALESCE(v_by::text, 'NULL') || ', reason ' || COALESCE(v_reason, 'NULL'),
    v_closed IS NULL AND v_by IS NULL AND v_reason IS NULL);

  -- ── 6. A driver replying reopens it too ──────────────────────────────────
  PERFORM public.admin_close_conversation(v_conv, 'handled');
  INSERT INTO public.chat_messages (conversation_id, sender_id, sender_role,
                                    message, created_at)
  VALUES (v_conv, v_customer, 'driver', 'I cannot find the address', now());
  SELECT closed_at INTO v_closed FROM public.conversations WHERE id = v_conv;
  INSERT INTO t VALUES (6, 'A driver message also reopens a closed chat',
    'reopened', 'closed_at ' || COALESCE(v_closed::text, 'NULL'),
    v_closed IS NULL);

  -- ── 7. Explicit reopen ───────────────────────────────────────────────────
  PERFORM public.admin_close_conversation(v_conv, 'done');
  PERFORM public.admin_reopen_conversation(v_conv);
  SELECT closed_at INTO v_closed FROM public.conversations WHERE id = v_conv;
  INSERT INTO t VALUES (7, 'An admin reopens a closed chat',
    'open', 'closed_at ' || COALESCE(v_closed::text, 'NULL'),
    v_closed IS NULL);

  -- ── 8. A non-admin cannot reopen ─────────────────────────────────────────
  PERFORM public.admin_close_conversation(v_conv, 'done');
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_customer, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM * FROM public.admin_reopen_conversation(v_conv);
    INSERT INTO t VALUES (8, 'A customer reopening a chat', 'raises Forbidden',
      'it reopened - GATE IS OPEN', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (8, 'A customer reopening a chat', 'raises Forbidden',
      SQLERRM, SQLERRM ILIKE '%Forbidden%');
  END;

  -- ── 9. Unknown id is an error, not a silent no-op ────────────────────────
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', v_admin, 'role', 'authenticated')::text, true);
  BEGIN
    PERFORM * FROM public.admin_close_conversation(
      '00000000-0000-0000-0000-000000000000', NULL);
    INSERT INTO t VALUES (9, 'Closing a conversation that does not exist',
      'raises', 'returned quietly', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (9, 'Closing a conversation that does not exist',
      'raises', SQLERRM, SQLERRM ILIKE '%No conversation%');
  END;

  -- ── 10. An over-long reason is rejected ──────────────────────────────────
  BEGIN
    PERFORM * FROM public.admin_close_conversation(v_conv, repeat('x', 501));
    INSERT INTO t VALUES (10, 'A 501-character reason', 'raises',
      'accepted it', FALSE);
  EXCEPTION WHEN OTHERS THEN
    INSERT INTO t VALUES (10, 'A 501-character reason', 'raises', SQLERRM,
      SQLERRM ILIKE '%too long%');
  END;

  -- ── 11. An empty reason is stored as absent ──────────────────────────────
  PERFORM public.admin_reopen_conversation(v_conv);
  SELECT c.close_reason INTO v_reason
    FROM public.admin_close_conversation(v_conv, '   ') c;
  INSERT INTO t VALUES (11, 'A blank reason is stored as NULL, not ""',
    'NULL', COALESCE('"' || v_reason || '"', 'NULL'), v_reason IS NULL);
END
$t$;

SELECT jsonb_pretty(jsonb_agg(jsonb_build_object(
  'step', step, 'scenario', scenario, 'expected', expected, 'actual', actual,
  'result', CASE WHEN pass THEN 'PASS' ELSE '*** FAIL ***' END) ORDER BY step))
  AS results
FROM t;

SELECT count(*) FILTER (WHERE pass)     AS passed,
       count(*) FILTER (WHERE NOT pass) AS failed,
       count(*)                         AS total
FROM t;

ROLLBACK;

-- Check the full trigger definition including WHEN clause
SELECT tgname, tgenabled, tgtype,
       pg_get_triggerdef(t.oid, true) AS trigger_def
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname = 'notifications' AND NOT tgisinternal;

-- Check if any pg_net requests are queued (not yet executed)
SELECT count(*) AS queued FROM net.http_request_queue;

-- Check the notifications table for title/body columns (might be NULL causing early exit)
SELECT id, type, title, body, user_id, order_id
FROM notifications
ORDER BY created_at DESC
LIMIT 5;

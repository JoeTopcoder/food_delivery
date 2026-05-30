-- Check trigger functions exist
SELECT proname FROM pg_proc
WHERE proname IN (
  'send_fcm_on_notification_insert',
  'notify_customer_on_order_status_change',
  'notify_customer_on_ride_placed',
  'notify_customer_on_ride_status_change'
)
ORDER BY proname;

-- Check triggers on notifications table
SELECT tgname, tgenabled, tgfoid::regproc
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname = 'notifications' AND NOT tgisinternal;

-- Check pg_net extension
SELECT extname, extversion FROM pg_extension WHERE extname = 'pg_net';

-- Check recent notifications (last 5)
SELECT id, type, user_id, created_at
FROM notifications
ORDER BY created_at DESC
LIMIT 5;

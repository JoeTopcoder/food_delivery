-- Insert a test notification to verify FCM push fires
INSERT INTO notifications (user_id, type, title, body)
VALUES (
  '41965f15-56f2-40b5-bc18-705915beafb3',
  'test',
  '🔔 Test Push',
  'If you see this, FCM is working again!'
);

-- Check latest pg_net response (wait a moment for the async call)
SELECT id, status_code, error_msg, timed_out, created
FROM net._http_response
ORDER BY created DESC
LIMIT 3;

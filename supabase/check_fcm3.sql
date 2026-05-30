-- Get the full source of the FCM trigger function
SELECT prosrc FROM pg_proc WHERE proname = 'send_fcm_on_notification_insert';

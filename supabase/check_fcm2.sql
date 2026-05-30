-- Check if the FCM trigger exists on notifications table
SELECT tgname, tgenabled, tgfoid::regproc AS function_name
FROM pg_trigger t
JOIN pg_class c ON c.oid = t.tgrelid
WHERE c.relname = 'notifications' AND NOT tgisinternal;

SELECT id, status_code, error_msg, timed_out, created
FROM net._http_response
ORDER BY created DESC
LIMIT 10;

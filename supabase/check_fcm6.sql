SELECT id, fcm_token IS NOT NULL AS has_fcm_token, length(fcm_token) AS token_length
FROM public.users
WHERE id = '41965f15-56f2-40b5-bc18-705915beafb3';

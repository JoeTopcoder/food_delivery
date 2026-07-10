export const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

export function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

export function errorResponse(e: unknown, fallbackStatus = 500) {
  const msg = e instanceof Error ? e.message : String(e)
  const status =
    msg === 'UNAUTHORIZED' ? 401 :
    msg === 'FORBIDDEN' ? 403 :
    msg.startsWith('BAD_REQUEST') ? 400 : fallbackStatus
  return json({ error: msg }, status)
}

export function handleOptions() {
  return new Response('ok', { headers: corsHeaders })
}

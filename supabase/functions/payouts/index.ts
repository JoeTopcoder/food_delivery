// Consolidated `payouts` Edge Function.
//
// One deployed function in place of request-payout, payout-driver,
// approve-payout-request, reject-payout-request, retry-payout-request and
// process-restaurant-payout. Same verbatim-copy + lazy-router pattern as the
// other consolidations. These are back-office / money-out operations; each
// route authenticates in its own handler, so verify_jwt is off at the platform
// and each route gates itself.
//
// (release-available-earnings is NOT here: its work is done directly in SQL by
// a pg_cron job, so that edge function was dead and was deleted, not merged.)

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

type Handler = (req: Request) => Promise<Response>
type Loader = () => Promise<{ handle: Handler }>

const ROUTES: Record<string, Loader> = {
  '/request': () => import('./routes/request.ts'),
  '/driver': () => import('./routes/driver.ts'),
  '/approve': () => import('./routes/approve.ts'),
  '/reject': () => import('./routes/reject.ts'),
  '/retry': () => import('./routes/retry.ts'),
  '/restaurant': () => import('./routes/restaurant.ts'),
}

function routeOf(pathname: string): string {
  const segs = pathname.split('/').filter(Boolean)
  const i = segs.lastIndexOf('payouts')
  const rest = i >= 0 ? segs.slice(i + 1) : segs
  return '/' + rest.join('/')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const route = routeOf(new URL(req.url).pathname)
  const loader = ROUTES[route]

  if (!loader) {
    return new Response(
      JSON.stringify({ error: 'Unknown payouts route: ' + route }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    const mod = await loader()
    return await mod.handle(req)
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[payouts] unhandled error on ' + route + ': ' + msg)
    return new Response(
      JSON.stringify({ error: 'Internal error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})

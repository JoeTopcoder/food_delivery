// Consolidated `packages` Edge Function.
//
// One deployed function in place of the ten package-delivery functions. Same
// verbatim-copy + lazy-router pattern as stripe/grocery/admin/payouts. None are
// webhooks; each route authenticates in its own handler, so verify_jwt is off.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

type Handler = (req: Request) => Promise<Response>
type Loader = () => Promise<{ handle: Handler }>

const ROUTES: Record<string, Loader> = {
  '/accept': () => import('./routes/accept.ts'),
  '/assign': () => import('./routes/assign.ts'),
  '/fee': () => import('./routes/fee.ts'),
  '/complete': () => import('./routes/complete.ts'),
  '/confirm-pickup': () => import('./routes/confirm-pickup.ts'),
  '/create': () => import('./routes/create.ts'),
  '/tracking': () => import('./routes/tracking.ts'),
  '/update-stop': () => import('./routes/update-stop.ts'),
  '/update-status': () => import('./routes/update-status.ts'),
  '/verify': () => import('./routes/verify.ts'),
}

function routeOf(pathname: string): string {
  const segs = pathname.split('/').filter(Boolean)
  const i = segs.lastIndexOf('packages')
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
      JSON.stringify({ error: 'Unknown packages route: ' + route }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    const mod = await loader()
    return await mod.handle(req)
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[packages] unhandled error on ' + route + ': ' + msg)
    return new Response(
      JSON.stringify({ error: 'Internal error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})

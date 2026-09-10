// Consolidated `grocery` Edge Function.
//
// One deployed function in place of grocery-order, grocery-products and
// grocery-stores. Same design as the `stripe` function: a thin path router
// that hands the request, untouched, to a route module under ./routes/. Each
// module is a verbatim copy of the function it replaces, so behaviour is
// byte-for-byte what production ran.
//
// grocery-order is JWT-authenticated; it verifies the token in-handler exactly
// as before. grocery-products / grocery-stores are read endpoints. None are
// webhooks, so verify_jwt can stay at its default — but the order route does
// its own auth regardless, so it does not depend on the platform gate.
//
// Routes load lazily (dynamic import on first hit) so one module cannot crash
// the whole function's cold start.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

type Handler = (req: Request) => Promise<Response>
type Loader = () => Promise<{ handle: Handler }>

// Keys are the path AFTER the `grocery` function segment. Flutter reaches these
// with functions.invoke('grocery/order', ...).
const ROUTES: Record<string, Loader> = {
  '/order': () => import('./routes/order.ts'),
  '/products': () => import('./routes/products.ts'),
  '/stores': () => import('./routes/stores.ts'),
}

function routeOf(pathname: string): string {
  const segs = pathname.split('/').filter(Boolean)
  const i = segs.lastIndexOf('grocery')
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
      JSON.stringify({ error: 'Unknown grocery route: ' + route }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    const mod = await loader()
    return await mod.handle(req)
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[grocery] unhandled error on ' + route + ': ' + msg)
    return new Response(
      JSON.stringify({ error: 'Internal error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})

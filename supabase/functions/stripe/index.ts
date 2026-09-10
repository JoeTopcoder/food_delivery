// Consolidated `stripe` Edge Function.
//
// One deployed function replacing 12 separate ones. It does NOT re-implement
// any Stripe logic: it is a thin path router that hands the request, untouched,
// to one of the route modules under ./routes/. Each module is a verbatim copy
// of the function it replaces (see routes/*.ts headers), so payment, Connect,
// subscription, payout and webhook behaviour is byte-for-byte what production
// runs today.
//
// Why a router and not a monolith: the deployed-function count is the thing we
// are reducing (100/100 ceiling). The source stays modular — one file per old
// function — so nothing became harder to read or reason about.
//
// verify_jwt MUST be false for this function (see supabase/config.toml): the
// webhook routes are called by Stripe, which cannot present a Supabase JWT.
// Every NON-webhook route authenticates the caller itself, exactly as its
// original function did (requireAuth / manual JWT decode + users-table check).
// So turning off the platform JWT gate does not weaken the authenticated
// routes — their auth was always in the handler, never in the platform.
//
// The router never reads the request body. Webhook signature verification
// needs the raw, unparsed body, so the body is passed through to the handler
// untouched.

// Routes are loaded LAZILY (dynamic import on first hit), not eagerly at the
// top. Eager imports would run every module's top-level code at cold start, so
// one module's import-time work (a Stripe client built from an esm.sh build, a
// read of an unset webhook secret) could crash the entire function's boot. With
// lazy loading the boot only parses this router; a faulty module fails only its
// own route, caught below as a 500, and each cold start loads just what it needs.
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, stripe-signature',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

type Handler = (req: Request) => Promise<Response>
type Loader = () => Promise<{ handle: Handler }>

// Exact-path routing. Keys are the path AFTER the `stripe` function segment.
// Flutter reaches these with functions.invoke('stripe/payment', ...): the dart
// client appends the sub-path to the slug and Supabase routes /functions/v1/
// stripe/* to this function. Values are lazy loaders (see note above).
const ROUTES: Record<string, Loader> = {
  '/payment': () => import('./routes/payment.ts'),
  '/connect': () => import('./routes/connect.ts'),
  '/connect/account': () => import('./routes/connect-account.ts'),
  '/connect/onboarding': () => import('./routes/connect-onboarding.ts'),
  '/connect/status': () => import('./routes/connect-status.ts'),
  '/subscription': () => import('./routes/subscription.ts'),
  '/pause-fee': () => import('./routes/pause-fee.ts'),
  '/payout': () => import('./routes/payout.ts'),
  '/webhook': () => import('./routes/webhook-main.ts'),
  '/webhook/connect': () => import('./routes/webhook-connect.ts'),
  '/webhook/payout': () => import('./routes/webhook-payout.ts'),
  '/webhook/subscription': () => import('./routes/webhook-subscription.ts'),
}

function routeOf(pathname: string): string {
  // pathname is /stripe/payment (or /functions/v1/stripe/payment when served
  // through the gateway). Take everything after the `stripe` segment.
  const segs = pathname.split('/').filter(Boolean)
  const i = segs.lastIndexOf('stripe')
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
      JSON.stringify({ error: 'Unknown stripe route: ' + route }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    // Load the route module on demand, then pass the request through untouched
    // — the body is not read here so webhook handlers can verify the raw
    // payload signature.
    const mod = await loader()
    return await mod.handle(req)
  } catch (e) {
    // A handler that throws instead of returning a Response. Each route already
    // has its own try/catch; this is the last-resort net so the function never
    // returns an unhandled 500 with a stack trace.
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[stripe] unhandled error on ' + route + ': ' + msg)
    return new Response(
      JSON.stringify({ error: 'Internal error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})

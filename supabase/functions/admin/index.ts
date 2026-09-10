// Consolidated `admin` Edge Function.
//
// One deployed function in place of admin-broadcast, admin-create-user,
// admin-lookup, admin-review-driver and admin-verify-restaurant. Same design as
// `stripe`/`grocery`: a thin lazy-import path router handing the request,
// untouched, to a verbatim-copied route module. Every route already verifies
// the caller is an admin in its own handler (getUser + role='admin', or a
// service-role token check), so verify_jwt is off at the platform and each
// route still gates itself — identical security to before.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

type Handler = (req: Request) => Promise<Response>
type Loader = () => Promise<{ handle: Handler }>

// Keys are the path AFTER the `admin` function segment. Callers reach these
// with functions.invoke('admin/broadcast', ...) or a POST to
// /functions/v1/admin/lookup.
const ROUTES: Record<string, Loader> = {
  '/broadcast': () => import('./routes/broadcast.ts'),
  '/create-user': () => import('./routes/create-user.ts'),
  '/lookup': () => import('./routes/lookup.ts'),
  '/review-driver': () => import('./routes/review-driver.ts'),
  '/verify-restaurant': () => import('./routes/verify-restaurant.ts'),
}

function routeOf(pathname: string): string {
  const segs = pathname.split('/').filter(Boolean)
  const i = segs.lastIndexOf('admin')
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
      JSON.stringify({ error: 'Unknown admin route: ' + route }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    const mod = await loader()
    return await mod.handle(req)
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('[admin] unhandled error on ' + route + ': ' + msg)
    return new Response(
      JSON.stringify({ error: 'Internal error' }),
      { status: 500, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }
})

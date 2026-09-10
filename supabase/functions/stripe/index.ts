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

import { handle as payment } from './routes/payment.ts'
import { handle as connect } from './routes/connect.ts'
import { handle as connectAccount } from './routes/connect-account.ts'
import { handle as connectOnboarding } from './routes/connect-onboarding.ts'
import { handle as connectStatus } from './routes/connect-status.ts'
import { handle as subscription } from './routes/subscription.ts'
import { handle as pauseFee } from './routes/pause-fee.ts'
import { handle as payout } from './routes/payout.ts'
import { handle as webhookMain } from './routes/webhook-main.ts'
import { handle as webhookConnect } from './routes/webhook-connect.ts'
import { handle as webhookPayout } from './routes/webhook-payout.ts'
import { handle as webhookSubscription } from './routes/webhook-subscription.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type, stripe-signature',
  'Access-Control-Allow-Methods': 'POST, GET, OPTIONS',
}

type Handler = (req: Request) => Promise<Response>

// Exact-path routing. Keys are the path AFTER the `stripe` function segment.
// Flutter reaches these with functions.invoke('stripe/payment', ...): the dart
// client appends the sub-path to the slug and Supabase routes /functions/v1/
// stripe/* to this function.
const ROUTES: Record<string, Handler> = {
  '/payment': payment,
  '/connect': connect,
  '/connect/account': connectAccount,
  '/connect/onboarding': connectOnboarding,
  '/connect/status': connectStatus,
  '/subscription': subscription,
  '/pause-fee': pauseFee,
  '/payout': payout,
  '/webhook': webhookMain,
  '/webhook/connect': webhookConnect,
  '/webhook/payout': webhookPayout,
  '/webhook/subscription': webhookSubscription,
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
  const handler = ROUTES[route]

  if (!handler) {
    return new Response(
      JSON.stringify({ error: 'Unknown stripe route: ' + route }),
      { status: 404, headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    )
  }

  try {
    // Pass the request through untouched — the body is not read here so that
    // webhook handlers can verify the raw payload signature.
    return await handler(req)
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

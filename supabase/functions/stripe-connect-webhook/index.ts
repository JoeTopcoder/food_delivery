import Stripe from 'npm:stripe@14'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { json } from '../stripe-shared/errors.ts'

const STRIPE_SECRET_KEY = Deno.env.get('STRIPE_SECRET_KEY') ?? ''
const STRIPE_WEBHOOK_SECRET = Deno.env.get('STRIPE_CONNECT_WEBHOOK_SECRET') ?? ''

if (!STRIPE_SECRET_KEY) throw new Error('STRIPE_SECRET_KEY not set')
if (!STRIPE_WEBHOOK_SECRET) throw new Error('STRIPE_CONNECT_WEBHOOK_SECRET not set')

const stripe = new Stripe(STRIPE_SECRET_KEY, { apiVersion: '2024-06-20', typescript: true })

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, stripe-signature',
}

function deriveOnboardingStatus(acct: Stripe.Account): string {
  if (!acct.details_submitted) return 'pending'
  if (acct.requirements?.disabled_reason) return 'restricted'
  if ((acct.requirements?.currently_due ?? []).length > 0) return 'restricted'
  if (acct.payouts_enabled) return 'complete'
  return 'pending'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  // Read raw body for signature verification
  const sig = req.headers.get('stripe-signature') ?? ''
  const body = await req.text()

  let event: Stripe.Event
  try {
    event = await stripe.webhooks.constructEventAsync(body, sig, STRIPE_WEBHOOK_SECRET)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    console.error('Webhook signature verification failed:', msg)
    return new Response(JSON.stringify({ error: 'Invalid signature' }), {
      status: 400,
      headers: corsHeaders,
    })
  }

  // Idempotency check — skip already-processed events
  const { data: existing } = await serviceClient
    .from('stripe_webhook_events')
    .select('id, processed')
    .eq('stripe_event_id', event.id)
    .maybeSingle()

  if (existing) {
    return new Response(JSON.stringify({ received: true, duplicate: true }), {
      status: 200,
      headers: corsHeaders,
    })
  }

  // Persist event record before processing
  await serviceClient.from('stripe_webhook_events').insert({
    stripe_event_id: event.id,
    type: event.type,
    livemode: event.livemode,
    payload: event as unknown as Record<string, unknown>,
    processed: false,
  })

  try {
    switch (event.type) {
      // ----------------------------------------------------------------
      // account.updated — sync connected account status
      // ----------------------------------------------------------------
      case 'account.updated': {
        const acct = event.data.object as Stripe.Account
        const caps = acct.capabilities as Record<string, string> | undefined
        const onboardingStatus = deriveOnboardingStatus(acct)

        await serviceClient
          .from('stripe_connected_accounts')
          .update({
            charges_enabled: acct.charges_enabled,
            payouts_enabled: acct.payouts_enabled,
            details_submitted: acct.details_submitted,
            onboarding_status: onboardingStatus,
            transfers_capability_status: caps?.transfers ?? 'inactive',
            requirements_currently_due: acct.requirements?.currently_due ?? [],
            requirements_eventually_due: acct.requirements?.eventually_due ?? [],
            requirements_past_due: acct.requirements?.past_due ?? [],
            disabled_reason: acct.requirements?.disabled_reason ?? null,
            last_synced_at: new Date().toISOString(),
            updated_at: new Date().toISOString(),
          })
          .eq('stripe_account_id', acct.id)
        break
      }

      // ----------------------------------------------------------------
      // payout.paid — mark payout as paid and ledger entries withdrawn
      // ----------------------------------------------------------------
      case 'payout.paid': {
        const payout = event.data.object as Stripe.Payout
        const { data: pr } = await serviceClient
          .from('stripe_payout_requests')
          .select('id')
          .eq('stripe_payout_id', payout.id)
          .maybeSingle()

        if (pr) {
          await serviceClient.rpc('mark_payout_paid', { p_payout_request_id: pr.id })
        } else {
          console.warn('payout.paid: no matching payout_request for payout', payout.id)
        }
        break
      }

      // ----------------------------------------------------------------
      // payout.failed — mark failed and restore ledger entries
      // ----------------------------------------------------------------
      case 'payout.failed': {
        const payout = event.data.object as Stripe.Payout
        const { data: pr } = await serviceClient
          .from('stripe_payout_requests')
          .select('id')
          .eq('stripe_payout_id', payout.id)
          .maybeSingle()

        if (pr) {
          await serviceClient.rpc('mark_payout_failed', {
            p_payout_request_id: pr.id,
            p_failure_code: payout.failure_code ?? 'unknown',
            p_failure_message: payout.failure_message ?? 'Payout failed',
          })
        } else {
          console.warn('payout.failed: no matching payout_request for payout', payout.id)
        }
        break
      }

      // ----------------------------------------------------------------
      // payout.canceled — cancel request and restore ledger entries
      // ----------------------------------------------------------------
      case 'payout.canceled': {
        const payout = event.data.object as Stripe.Payout
        const { data: pr } = await serviceClient
          .from('stripe_payout_requests')
          .select('id, status')
          .eq('stripe_payout_id', payout.id)
          .maybeSingle()

        if (pr && !['paid', 'withdrawn'].includes(pr.status)) {
          await serviceClient
            .from('stripe_payout_requests')
            .update({ status: 'canceled', updated_at: new Date().toISOString() })
            .eq('id', pr.id)
          await serviceClient.rpc('unlock_ledger_entries_for_payout', {
            p_payout_request_id: pr.id,
          })
        }
        break
      }

      // ----------------------------------------------------------------
      // transfer.reversed — mark failed and restore ledger entries
      // ----------------------------------------------------------------
      case 'transfer.reversed': {
        const transfer = event.data.object as Stripe.Transfer
        const { data: pr } = await serviceClient
          .from('stripe_payout_requests')
          .select('id')
          .eq('stripe_transfer_id', transfer.id)
          .maybeSingle()

        if (pr) {
          await serviceClient
            .from('stripe_payout_requests')
            .update({
              status: 'failed',
              failure_code: 'transfer_reversed',
              failure_message: 'Stripe transfer was reversed by Stripe',
              updated_at: new Date().toISOString(),
            })
            .eq('id', pr.id)
          await serviceClient.rpc('unlock_ledger_entries_for_payout', {
            p_payout_request_id: pr.id,
          })
        }
        break
      }

      // ----------------------------------------------------------------
      // transfer.created — optional logging only
      // ----------------------------------------------------------------
      case 'transfer.created': {
        const transfer = event.data.object as Stripe.Transfer
        console.log('transfer.created:', transfer.id, 'destination:', transfer.destination)
        break
      }

      default:
        console.log('Unhandled webhook event type:', event.type)
    }

    // Mark event as successfully processed
    await serviceClient
      .from('stripe_webhook_events')
      .update({ processed: true, processed_at: new Date().toISOString() })
      .eq('stripe_event_id', event.id)
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e)
    await serviceClient
      .from('stripe_webhook_events')
      .update({ processed: false, error: msg })
      .eq('stripe_event_id', event.id)
    console.error('Webhook processing error for event', event.type, ':', msg)
  }

  return new Response(JSON.stringify({ received: true }), {
    status: 200,
    headers: corsHeaders,
  })
})

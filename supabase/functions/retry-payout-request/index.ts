import { stripe } from '../stripe-shared/stripe.ts'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    await requireAdmin(req)
    const { payout_request_id } = await req.json()

    if (!payout_request_id) {
      return json({ error: 'BAD_REQUEST: payout_request_id required' }, 400)
    }

    const { data: pr } = await serviceClient
      .from('stripe_payout_requests')
      .select('*')
      .eq('id', payout_request_id)
      .single()

    if (!pr) return json({ error: 'Payout request not found' }, 404)
    if (!['failed', 'transferred', 'approved'].includes(pr.status)) {
      return json({ error: `Cannot retry payout in status: ${pr.status}` }, 400)
    }

    // If no transfer exists yet, create it first
    if (!pr.stripe_transfer_id) {
      const transfer = await stripe.transfers.create(
        {
          amount: pr.amount_cents,
          currency: pr.currency,
          destination: pr.stripe_account_id,
          metadata: {
            payout_request_id: pr.id,
            user_id: pr.user_id,
            role: pr.role,
            app: '7Dash',
          },
        },
        { idempotencyKey: `transfer_${pr.id}` },
      )
      await serviceClient
        .from('stripe_payout_requests')
        .update({
          stripe_transfer_id: transfer.id,
          status: 'transferred',
          failure_code: null,
          failure_message: null,
          updated_at: new Date().toISOString(),
        })
        .eq('id', pr.id)
    }

    // Retry the payout from the connected account
    // Use a unique idempotency key per retry attempt so Stripe doesn't deduplicate.
    const retryKey = `payout_${pr.id}_retry_${Date.now()}`
    const payoutParams: Record<string, unknown> = {
      amount: pr.amount_cents,
      currency: pr.currency,
      metadata: {
        payout_request_id: pr.id,
        transfer_id: pr.stripe_transfer_id,
        user_id: pr.user_id,
        role: pr.role,
        payout_method: pr.payout_method ?? 'standard',
        app: '7Dash',
        retry: 'true',
      },
    }
    if (pr.payout_method === 'instant') payoutParams.method = 'instant'

    const payout = await stripe.payouts.create(
      payoutParams as Parameters<typeof stripe.payouts.create>[0],
      {
        stripeAccount: pr.stripe_account_id,
        idempotencyKey: retryKey,
      },
    )

    await serviceClient
      .from('stripe_payout_requests')
      .update({
        stripe_payout_id: payout.id,
        status: 'processing',
        failure_code: null,
        failure_message: null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', payout_request_id)

    const { data: updated } = await serviceClient
      .from('stripe_payout_requests')
      .select('*')
      .eq('id', payout_request_id)
      .single()

    return json({ payout_request: updated })
  } catch (e) {
    return errorResponse(e)
  }
})

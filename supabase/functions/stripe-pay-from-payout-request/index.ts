import { stripe } from '../stripe-shared/stripe.ts'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

// Bridges the OLD payout_requests system to Stripe Connect.
// Admin triggers this for drivers who have completed Stripe Express onboarding.
// Flow: Transfer (platform → connected account) → Payout (connected → bank)
// Then marks payout_requests.status = 'completed'.

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    await requireAdmin(req)
    const { payout_request_id } = await req.json()

    if (!payout_request_id) {
      return json({ error: 'BAD_REQUEST: payout_request_id required' }, 400)
    }

    // Load the old payout request
    const { data: pr } = await serviceClient
      .from('payout_requests')
      .select('*')
      .eq('id', payout_request_id)
      .single()

    if (!pr) return json({ error: 'Payout request not found' }, 404)
    if (pr.status !== 'approved') {
      return json({ error: `Cannot process payout in status: ${pr.status}` }, 400)
    }

    // Load the driver's Stripe connected account
    const { data: acct } = await serviceClient
      .from('stripe_connected_accounts')
      .select('*')
      .eq('user_id', pr.requester_id)
      .eq('role', 'driver')
      .single()

    if (!acct) {
      return json({ error: 'Driver has no Stripe connected account. They must complete onboarding first.' }, 400)
    }
    if (acct.onboarding_status !== 'complete') {
      return json({ error: `Driver Stripe onboarding not complete (status: ${acct.onboarding_status})` }, 400)
    }
    if (!acct.payouts_enabled) {
      return json({ error: 'Payouts not enabled on this driver\'s Stripe account.' }, 400)
    }

    const amountCents = Math.round(pr.amount * 100)
    const currency = (pr.currency ?? 'usd').toLowerCase()

    // Mark as processing
    await serviceClient
      .from('payout_requests')
      .update({ status: 'processing', updated_at: new Date().toISOString() })
      .eq('id', pr.id)

    // Step 1: Transfer from platform to connected account
    const transfer = await stripe.transfers.create(
      {
        amount: amountCents,
        currency,
        destination: acct.stripe_account_id,
        metadata: {
          payout_request_id: pr.id,
          requester_id: pr.requester_id,
          driver_id: pr.driver_id ?? '',
          app: '7Dash',
        },
      },
      { idempotencyKey: `old_transfer_${pr.id}` },
    )

    // Step 2: Payout from connected account to their bank
    const payout = await stripe.payouts.create(
      {
        amount: amountCents,
        currency,
        metadata: {
          payout_request_id: pr.id,
          transfer_id: transfer.id,
          app: '7Dash',
        },
      },
      {
        stripeAccount: acct.stripe_account_id,
        idempotencyKey: `old_payout_${pr.id}`,
      },
    )

    // Mark as completed
    await serviceClient
      .from('payout_requests')
      .update({
        status: 'completed',
        wipay_transaction_id: payout.id,
        processed_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
        admin_notes: `Stripe transfer: ${transfer.id} | payout: ${payout.id}`,
      })
      .eq('id', pr.id)

    return json({
      success: true,
      stripe_transfer_id: transfer.id,
      stripe_payout_id: payout.id,
      amount: pr.amount,
    })
  } catch (e) {
    // On Stripe error, revert to approved so admin can retry or use Mark as Paid
    return errorResponse(e)
  }
})

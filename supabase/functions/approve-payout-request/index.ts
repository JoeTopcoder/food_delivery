import { stripe } from '../stripe-shared/stripe.ts'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

async function processPayout(payoutRequestId: string): Promise<void> {
  const { data: pr } = await serviceClient
    .from('stripe_payout_requests')
    .select('*')
    .eq('id', payoutRequestId)
    .single()

  if (!pr || !['requested', 'approved'].includes(pr.status)) {
    throw new Error('Payout request not in payable state')
  }

  const isInstant = pr.payout_method === 'instant'

  try {
    // Step 1: Transfer funds from platform to connected account
    const transfer = await stripe.transfers.create(
      {
        amount: pr.amount_cents,
        currency: pr.currency,
        destination: pr.stripe_account_id,
        metadata: {
          payout_request_id: pr.id,
          user_id: pr.user_id,
          role: pr.role,
          payout_method: pr.payout_method ?? 'standard',
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
        updated_at: new Date().toISOString(),
      })
      .eq('id', pr.id)

    // Step 2: Initiate payout from connected account to bank/card
    try {
      const payoutParams: Record<string, unknown> = {
        amount: pr.amount_cents,
        currency: pr.currency,
        metadata: {
          payout_request_id: pr.id,
          transfer_id: transfer.id,
          user_id: pr.user_id,
          role: pr.role,
          payout_method: pr.payout_method ?? 'standard',
          app: '7Dash',
        },
      }
      if (isInstant) payoutParams.method = 'instant'

      const payout = await stripe.payouts.create(
        payoutParams as Parameters<typeof stripe.payouts.create>[0],
        {
          stripeAccount: pr.stripe_account_id,
          idempotencyKey: `payout_${pr.id}`,
        },
      )
      await serviceClient
        .from('stripe_payout_requests')
        .update({
          stripe_payout_id: payout.id,
          status: 'processing',
          updated_at: new Date().toISOString(),
        })
        .eq('id', pr.id)
    } catch (payoutErr: unknown) {
      // Transfer succeeded but payout failed — keep 'transferred' so admin can retry.
      const msg = payoutErr instanceof Error ? payoutErr.message : String(payoutErr)
      await serviceClient
        .from('stripe_payout_requests')
        .update({
          failure_message: msg,
          updated_at: new Date().toISOString(),
        })
        .eq('id', pr.id)
      console.error('Payout creation failed after transfer (approve-payout-request):', msg)
    }
  } catch (transferErr: unknown) {
    // Transfer failed — mark as failed and unlock ledger entries.
    const code = (transferErr as { code?: string }).code ?? 'transfer_failed'
    const msg = transferErr instanceof Error ? transferErr.message : String(transferErr)
    await serviceClient
      .from('stripe_payout_requests')
      .update({
        status: 'failed',
        failure_code: code,
        failure_message: msg,
        updated_at: new Date().toISOString(),
      })
      .eq('id', pr.id)
    await serviceClient.rpc('unlock_ledger_entries_for_payout', {
      p_payout_request_id: pr.id,
    })
    throw transferErr
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { payout_request_id, admin_note } = await req.json()

    if (!payout_request_id) {
      return json({ error: 'BAD_REQUEST: payout_request_id required' }, 400)
    }

    const { data: pr } = await serviceClient
      .from('stripe_payout_requests')
      .select('*')
      .eq('id', payout_request_id)
      .single()

    if (!pr) return json({ error: 'Payout request not found' }, 404)
    if (pr.status !== 'requested') {
      return json({ error: `Cannot approve payout in status: ${pr.status}` }, 400)
    }

    // Mark as approved
    await serviceClient
      .from('stripe_payout_requests')
      .update({
        status: 'approved',
        approved_by: admin.id,
        approved_at: new Date().toISOString(),
        admin_note: admin_note ?? null,
        updated_at: new Date().toISOString(),
      })
      .eq('id', payout_request_id)

    // Execute Stripe transfer + payout
    await processPayout(payout_request_id)

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

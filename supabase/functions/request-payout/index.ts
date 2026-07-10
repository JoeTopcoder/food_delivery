import { stripe } from '../stripe-shared/stripe.ts'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAuth } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

// ----------------------------------------------------------------
// processPayout: creates Stripe Transfer then Payout on connected
// account. Called inline when require_admin_approval = false.
// ----------------------------------------------------------------
async function processPayout(payoutRequestId: string): Promise<void> {
  const { data: pr } = await serviceClient
    .from('stripe_payout_requests')
    .select('*')
    .eq('id', payoutRequestId)
    .single()

  if (!pr) throw new Error('Payout request not found')
  if (!['requested', 'approved'].includes(pr.status)) {
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
          payout_method: pr.payout_method,
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
          payout_method: pr.payout_method,
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
      // Transfer succeeded but payout failed — keep status as 'transferred', allow retry.
      const msg = payoutErr instanceof Error ? payoutErr.message : String(payoutErr)
      await serviceClient
        .from('stripe_payout_requests')
        .update({
          failure_message: msg,
          updated_at: new Date().toISOString(),
        })
        .eq('id', pr.id)
      console.error('Payout creation failed after transfer:', msg)
    }
  } catch (transferErr: unknown) {
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

// ----------------------------------------------------------------
// Main handler
// ----------------------------------------------------------------
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const user = await requireAuth(req)
    const { role, amount_cents, currency = 'usd', payout_method = 'standard' } = await req.json()

    if (!['standard', 'instant'].includes(payout_method)) {
      return json({ error: 'BAD_REQUEST: payout_method must be standard or instant' }, 400)
    }

    // Validate inputs
    if (!['driver', 'restaurant'].includes(role)) {
      return json({ error: 'BAD_REQUEST: invalid role' }, 400)
    }
    if (!Number.isInteger(amount_cents) || amount_cents <= 0) {
      return json({ error: 'BAD_REQUEST: invalid amount_cents — must be a positive integer' }, 400)
    }

    // Load payout settings
    const { data: settings } = await serviceClient
      .from('app_payout_settings')
      .select('*')
      .limit(1)
      .single()

    if (!settings) return json({ error: 'Payout settings not configured' }, 500)

    if (amount_cents < settings.min_payout_cents) {
      return json({ error: `Minimum payout is ${settings.min_payout_cents} cents` }, 400)
    }
    if (amount_cents > settings.max_payout_cents) {
      return json({ error: `Maximum payout is ${settings.max_payout_cents} cents` }, 400)
    }

    // Check connected account
    const { data: account } = await serviceClient
      .from('stripe_connected_accounts')
      .select('*')
      .eq('user_id', user.id)
      .eq('role', role)
      .single()

    if (!account) {
      return json({ error: 'No connected Stripe account. Complete onboarding first.' }, 400)
    }
    if (!account.payouts_enabled) {
      return json({ error: 'Payouts not enabled on your Stripe account. Complete onboarding.' }, 400)
    }
    if (account.transfers_capability_status !== 'active') {
      return json({ error: 'Transfers capability not active on your Stripe account.' }, 400)
    }
    if (account.onboarding_status !== 'complete') {
      return json({ error: 'Stripe onboarding not complete.' }, 400)
    }

    // Check available balance
    const { data: summary } = await serviceClient.rpc('get_user_earnings_summary', {
      p_user_id: user.id,
      p_role: role,
    })
    const available = (summary as { available_balance_cents?: number })?.available_balance_cents ?? 0
    if (amount_cents > available) {
      return json({ error: `Insufficient balance. Available: ${available} cents.` }, 400)
    }

    // Calculate instant payout fee (1.5%, min 50¢)
    const instantFeeCents = payout_method === 'instant'
      ? Math.max(Math.ceil(amount_cents * 0.015), 50)
      : 0

    // Generate idempotency key
    const idempotencyKey = `payout_req_${user.id}_${role}_${Date.now()}_${crypto.randomUUID().slice(0, 8)}`

    // Create payout request record
    const { data: pr, error: prErr } = await serviceClient
      .from('stripe_payout_requests')
      .insert({
        user_id: user.id,
        role,
        stripe_account_id: account.stripe_account_id,
        amount_cents,
        currency,
        status: 'requested',
        payout_method,
        instant_fee_cents: instantFeeCents,
        requested_by: user.id,
        idempotency_key: idempotencyKey,
        metadata: { source: 'user_request', payout_method, app: '7Dash' },
      })
      .select('*')
      .single()

    if (prErr) throw new Error(prErr.message)

    // Lock ledger entries for this payout
    await serviceClient.rpc('lock_ledger_entries_for_payout', {
      p_user_id: user.id,
      p_role: role,
      p_amount_cents: amount_cents,
      p_payout_request_id: pr.id,
    })

    // If admin approval is not required, process immediately
    if (!settings.require_admin_approval) {
      await serviceClient
        .from('stripe_payout_requests')
        .update({
          status: 'approved',
          approved_at: new Date().toISOString(),
        })
        .eq('id', pr.id)

      await processPayout(pr.id)

      const { data: updated } = await serviceClient
        .from('stripe_payout_requests')
        .select('*')
        .eq('id', pr.id)
        .single()

      return json({ payout_request: updated })
    }

    return json({ payout_request: pr })
  } catch (e) {
    return errorResponse(e)
  }
})

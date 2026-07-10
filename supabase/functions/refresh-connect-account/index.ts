import { stripe } from '../stripe-shared/stripe.ts'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAuth } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

function deriveOnboardingStatus(acct: {
  details_submitted: boolean
  payouts_enabled: boolean
  requirements?: {
    disabled_reason?: string | null
    currently_due?: string[]
  }
}): string {
  if (!acct.details_submitted) return 'pending'
  if (acct.requirements?.disabled_reason) return 'restricted'
  if ((acct.requirements?.currently_due ?? []).length > 0) return 'restricted'
  if (acct.payouts_enabled) return 'complete'
  return 'pending'
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const user = await requireAuth(req)
    const { role = 'driver' } = await req.json()

    if (!['driver', 'restaurant'].includes(role)) {
      return json({ error: 'BAD_REQUEST: invalid role' }, 400)
    }

    const { data: row } = await serviceClient
      .from('stripe_connected_accounts')
      .select('*')
      .eq('user_id', user.id)
      .eq('role', role)
      .single()

    if (!row) return json({ error: 'No connected account' }, 404)

    const acct = await stripe.accounts.retrieve(row.stripe_account_id)
    const caps = acct.capabilities as Record<string, string> | undefined
    const onboardingStatus = deriveOnboardingStatus(acct)

    await serviceClient.from('stripe_connected_accounts').update({
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
    }).eq('id', row.id)

    return json({
      connected: true,
      onboarding_complete: onboardingStatus === 'complete',
      payouts_enabled: acct.payouts_enabled,
      can_receive_transfers: caps?.transfers === 'active',
      needs_more_info: (acct.requirements?.currently_due ?? []).length > 0,
      requirements: acct.requirements?.currently_due ?? [],
      onboarding_status: onboardingStatus,
    })
  } catch (e) {
    return errorResponse(e)
  }
})

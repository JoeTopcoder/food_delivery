import { stripe } from '../stripe-shared/stripe.ts'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAuth } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const user = await requireAuth(req)
    const { role = 'driver', country = 'US', currency = 'usd' } = await req.json()

    if (!['driver', 'restaurant'].includes(role)) {
      return json({ error: 'BAD_REQUEST: invalid role' }, 400)
    }

    // Check for existing connected account
    const { data: existing } = await serviceClient
      .from('stripe_connected_accounts')
      .select('*')
      .eq('user_id', user.id)
      .eq('role', role)
      .maybeSingle()

    if (existing) return json({ account: existing })

    // Create Stripe Express account.
    // service_agreement: 'recipient' — these accounts only ever receive
    // transfers (payouts) from the platform's own Stripe balance; they never
    // process card charges themselves. This is required for cross-border
    // countries (e.g. Jamaica) where Stripe has no local charge processing,
    // and is also valid/correct for natively-supported countries.
    const account = await stripe.accounts.create({
      type: 'express',
      country,
      capabilities: { transfers: { requested: true } },
      business_type: role === 'restaurant' ? 'company' : 'individual',
      tos_acceptance: { service_agreement: 'recipient' },
      metadata: { user_id: user.id, role, app: '7Dash' },
    })

    const { data: inserted, error } = await serviceClient
      .from('stripe_connected_accounts')
      .insert({
        user_id: user.id,
        role,
        stripe_account_id: account.id,
        country,
        currency,
        account_type: 'express',
        onboarding_status: 'pending',
        charges_enabled: account.charges_enabled,
        payouts_enabled: account.payouts_enabled,
        details_submitted: account.details_submitted,
        transfers_capability_status: (account.capabilities as Record<string, string> | undefined)?.transfers ?? 'inactive',
        requirements_currently_due: account.requirements?.currently_due ?? [],
        requirements_eventually_due: account.requirements?.eventually_due ?? [],
        requirements_past_due: account.requirements?.past_due ?? [],
      })
      .select('*')
      .single()

    if (error) throw new Error(error.message)
    return json({ account: inserted })
  } catch (e) {
    return errorResponse(e)
  }
})

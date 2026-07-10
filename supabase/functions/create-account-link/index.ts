import { stripe } from '../stripe-shared/stripe.ts'
import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAuth } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const APP_URL = Deno.env.get('APP_URL') ?? 'https://7dash.app'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const user = await requireAuth(req)
    const { role = 'driver' } = await req.json()

    if (!['driver', 'restaurant'].includes(role)) {
      return json({ error: 'BAD_REQUEST: invalid role' }, 400)
    }

    const { data: account } = await serviceClient
      .from('stripe_connected_accounts')
      .select('stripe_account_id')
      .eq('user_id', user.id)
      .eq('role', role)
      .single()

    if (!account) {
      return json({ error: 'No connected account found. Call create-connect-account first.' }, 404)
    }

    const link = await stripe.accountLinks.create({
      account: account.stripe_account_id,
      refresh_url: `${APP_URL}/stripe/onboarding/refresh`,
      return_url: `${APP_URL}/stripe/onboarding/return`,
      type: 'account_onboarding',
    })

    return json({ url: link.url })
  } catch (e) {
    return errorResponse(e)
  }
})

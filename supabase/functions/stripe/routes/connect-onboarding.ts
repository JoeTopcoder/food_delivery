// AUTO-GENERATED for the consolidated `stripe` function.
// Verbatim copy of supabase/functions/create-account-link/index.ts with only the
// serve() wrapper turned into an exported handle() and import depth fixed.
// Business/webhook logic is unchanged. Regenerate via scratchpad/build_stripe.py.

import { stripe } from '../../stripe-shared/stripe.ts'
import { serviceClient } from '../../stripe-shared/supabase.ts'
import { requireAuth } from '../../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../../stripe-shared/errors.ts'

const APP_URL = Deno.env.get('APP_URL') ?? 'https://quickdash.app'

export async function handle(req: Request): Promise<Response> {
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
}

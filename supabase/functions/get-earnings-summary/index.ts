import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAuth } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const user = await requireAuth(req)
    const { role = 'driver' } = await req.json()

    if (!['driver', 'restaurant'].includes(role)) {
      return json({ error: 'BAD_REQUEST: invalid role' }, 400)
    }

    const { data: summary } = await serviceClient
      .rpc('get_user_earnings_summary', { p_user_id: user.id, p_role: role })

    const { data: settings } = await serviceClient
      .from('app_payout_settings')
      .select('*')
      .limit(1)
      .single()

    const { data: account } = await serviceClient
      .from('stripe_connected_accounts')
      .select('onboarding_status, payouts_enabled, transfers_capability_status, requirements_currently_due')
      .eq('user_id', user.id)
      .eq('role', role)
      .maybeSingle()

    const { data: recentPayouts } = await serviceClient
      .from('stripe_payout_requests')
      .select('id, amount_cents, currency, status, created_at, stripe_transfer_id, stripe_payout_id, failure_message')
      .eq('user_id', user.id)
      .eq('role', role)
      .order('created_at', { ascending: false })
      .limit(10)

    return json({
      summary,
      settings,
      connected_account: account,
      recent_payouts: recentPayouts ?? [],
    })
  } catch (e) {
    return errorResponse(e)
  }
})

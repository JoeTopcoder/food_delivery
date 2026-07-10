import { serviceClient } from '../stripe-shared/supabase.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

// This function is intended to be called by a cron job or Supabase pg_cron.
// Protect with RELEASE_EARNINGS_SECRET env var — set it as a Supabase secret
// and pass as Authorization: Bearer <secret> in the cron request.

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const authHeader = req.headers.get('Authorization') ?? ''
    const secret = Deno.env.get('RELEASE_EARNINGS_SECRET') ?? ''

    if (secret && authHeader !== `Bearer ${secret}`) {
      return json({ error: 'UNAUTHORIZED' }, 401)
    }

    // Move all pending earnings whose hold period has elapsed to 'available'
    const { error, count } = await serviceClient
      .from('earnings_ledger')
      .update({ status: 'available', updated_at: new Date().toISOString() })
      .eq('status', 'pending')
      .lte('available_at', new Date().toISOString())

    if (error) throw new Error(error.message)

    console.log(`[release-available-earnings] Released ${count ?? 0} entries at ${new Date().toISOString()}`)
    return json({ released: count ?? 0, timestamp: new Date().toISOString() })
  } catch (e) {
    return errorResponse(e)
  }
})

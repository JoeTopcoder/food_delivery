import { serviceClient } from '../stripe-shared/supabase.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

// Service-to-service endpoint: only callable with the Supabase service role key.
// Call this from other Edge Functions (e.g. complete-delivery, complete-ride)
// after a successful order/ride to credit the driver/restaurant earnings.

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const releaseSecret = Deno.env.get('RELEASE_EARNINGS_SECRET') ?? ''
    const authHeader = req.headers.get('Authorization') ?? ''

    if (!releaseSecret || authHeader !== `Bearer ${releaseSecret}`) {
      return json({ error: 'UNAUTHORIZED' }, 401)
    }

    const {
      user_id,
      role,
      order_id,
      ride_id,
      restaurant_id,
      driver_id,
      type,
      direction = 'credit',
      amount_cents,
      currency = 'usd',
      description,
      metadata = {},
    } = await req.json()

    // Validate required fields
    if (!user_id || !role || !type || amount_cents === undefined) {
      return json({ error: 'BAD_REQUEST: missing required fields (user_id, role, type, amount_cents)' }, 400)
    }
    if (!['driver', 'restaurant'].includes(role)) {
      return json({ error: 'BAD_REQUEST: invalid role' }, 400)
    }
    if (!Number.isInteger(amount_cents) || amount_cents <= 0) {
      return json({ error: 'BAD_REQUEST: amount_cents must be a positive integer' }, 400)
    }

    const validTypes = ['order_earning', 'ride_earning', 'tip', 'bonus', 'adjustment', 'refund', 'chargeback', 'platform_reversal']
    if (!validTypes.includes(type)) {
      return json({ error: `BAD_REQUEST: invalid type. Must be one of: ${validTypes.join(', ')}` }, 400)
    }

    // Idempotency: prevent duplicate earnings for the same order
    if (order_id && type === 'order_earning') {
      const { data: existing } = await serviceClient
        .from('earnings_ledger')
        .select('id')
        .eq('user_id', user_id)
        .eq('role', role)
        .eq('order_id', order_id)
        .eq('type', type)
        .maybeSingle()

      if (existing) {
        return json({ error: 'Duplicate earning entry for this order', existing_id: existing.id }, 409)
      }
    }

    // Idempotency: prevent duplicate earnings for the same ride
    if (ride_id && type === 'ride_earning') {
      const { data: existing } = await serviceClient
        .from('earnings_ledger')
        .select('id')
        .eq('user_id', user_id)
        .eq('role', role)
        .eq('ride_id', ride_id)
        .eq('type', type)
        .maybeSingle()

      if (existing) {
        return json({ error: 'Duplicate earning entry for this ride', existing_id: existing.id }, 409)
      }
    }

    // Calculate hold period from payout settings
    const { data: settings } = await serviceClient
      .from('app_payout_settings')
      .select('driver_hold_days, restaurant_hold_days')
      .limit(1)
      .single()

    const holdDays = role === 'driver'
      ? (settings?.driver_hold_days ?? 2)
      : (settings?.restaurant_hold_days ?? 2)

    const availableAt = new Date()
    availableAt.setDate(availableAt.getDate() + holdDays)

    const { data: entry, error } = await serviceClient
      .from('earnings_ledger')
      .insert({
        user_id,
        role,
        order_id: order_id ?? null,
        ride_id: ride_id ?? null,
        restaurant_id: restaurant_id ?? null,
        driver_id: driver_id ?? null,
        type,
        direction,
        amount_cents,
        currency,
        status: 'pending',
        available_at: availableAt.toISOString(),
        description: description ?? null,
        metadata,
      })
      .select('*')
      .single()

    if (error) throw new Error(error.message)
    return json({ entry })
  } catch (e) {
    return errorResponse(e)
  }
})

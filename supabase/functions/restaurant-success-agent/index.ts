// restaurant-success-agent — Restaurant Success Agent (7Dash AI Operations)
// Read-only. Ranks active restaurants by a deterministic at-risk score
// (cancellation rate, prep time, rating, refund rate) computed in SQL/JS —
// the model only narrates which partners need attention and why.
// Deploy: supabase functions deploy restaurant-success-agent --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

interface RestaurantMetrics {
  id: string
  name: string
  rating: number | null
  order_count: number
  cancelled_count: number
  cancellation_rate_pct: number
  refunded_count: number
  refund_rate_pct: number
  avg_prep_minutes: number | null
  revenue: number
  at_risk_score: number
}

async function computeRestaurantMetrics(): Promise<RestaurantMetrics[]> {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString()

  const [{ data: restaurants }, { data: orders }] = await Promise.all([
    serviceClient.from('restaurants').select('id, name, rating').eq('status', 'approved'),
    serviceClient
      .from('orders')
      .select('restaurant_id, status, payment_status, total_amount, ordered_at, ready_at')
      .gte('ordered_at', thirtyDaysAgo),
  ])

  const restaurantRows = restaurants ?? []
  const orderRows = orders ?? []

  return restaurantRows.map((r) => {
    const myOrders = orderRows.filter((o) => o.restaurant_id === r.id)
    const count = myOrders.length
    const cancelled = myOrders.filter((o) => o.status === 'cancelled').length
    const refunded = myOrders.filter((o) => o.payment_status === 'refunded').length
    const revenue = round2(myOrders.filter((o) => o.status !== 'cancelled').reduce((s, o) => s + (Number(o.total_amount) || 0), 0))

    const prepTimes = myOrders
      .filter((o) => o.ready_at && o.ordered_at)
      .map((o) => (new Date(o.ready_at as string).getTime() - new Date(o.ordered_at as string).getTime()) / 60000)
      .filter((m) => m >= 0 && m < 180) // discard bad/outlier data
    const avgPrep = prepTimes.length > 0 ? round2(prepTimes.reduce((s, m) => s + m, 0) / prepTimes.length) : null

    const cancellationRate = count > 0 ? round2((cancelled / count) * 100) : 0
    const refundRate = count > 0 ? round2((refunded / count) * 100) : 0

    // Deterministic at-risk score (0-100, higher = more at risk). Restaurants
    // with too little volume (<3 orders) aren't scored — not enough signal.
    let riskScore = 0
    if (count >= 3) {
      riskScore += cancellationRate * 0.4
      riskScore += refundRate * 0.3
      if (r.rating != null && r.rating < 4.0) riskScore += (4.0 - r.rating) * 15
      if (avgPrep != null && avgPrep > 30) riskScore += Math.min((avgPrep - 30) * 0.5, 20)
    }

    return {
      id: r.id,
      name: r.name,
      rating: r.rating,
      order_count: count,
      cancelled_count: cancelled,
      cancellation_rate_pct: cancellationRate,
      refunded_count: refunded,
      refund_rate_pct: refundRate,
      avg_prep_minutes: avgPrep,
      revenue,
      at_risk_score: round2(riskScore),
    }
  }).sort((a, b) => b.at_risk_score - a.at_risk_score)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)

    const { data: agentRow } = await serviceClient
      .from('ai_agents')
      .select('status')
      .eq('slug', 'restaurant_success')
      .maybeSingle()
    if (agentRow?.status === 'paused') return json({ error: 'Restaurant Success Agent is paused.' }, 403)

    const metrics = await computeRestaurantMetrics()

    let narrative = ''
    if (OPENAI_API_KEY && metrics.length > 0) {
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `You are the 7Dash Restaurant Success Agent. You're given 30-day performance metrics for every active restaurant, already ranked by a deterministic at_risk_score (higher = more concerning). Write a short briefing (100-160 words): name the 1-3 restaurants most at risk and the specific reason (cancellation rate, rating, slow prep time, or refunds — cite the actual numbers), and note any standout top performer. Restaurants with order_count under 3 have insufficient data — don't flag them as at-risk. Never invent a number not present in the data. Plain text, no markdown.`,
            },
            { role: 'user', content: JSON.stringify(metrics) },
          ],
          temperature: 0.3,
        }),
      })
      if (res.ok) {
        const completion = await res.json()
        narrative = completion.choices?.[0]?.message?.content ?? ''
      }
    }

    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'restaurant_success',
      entity_type: 'restaurant_report',
      entity_id: crypto.randomUUID(),
      related_entities: metrics.map((m) => ({ type: 'restaurant', id: m.id })),
      input: {},
      output: { metrics, narrative },
      model: 'gpt-4o-mini',
      status: 'completed',
      created_by: admin.id,
    })

    return json({ success: true, metrics, narrative })
  } catch (e) {
    return errorResponse(e)
  }
})

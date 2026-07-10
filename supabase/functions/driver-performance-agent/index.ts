// driver-performance-agent — Driver Performance Agent (7Dash AI Operations)
// Read-only. Ranks approved drivers by a deterministic score computed from
// this-window order data (cancellation rate, delivery time) — NOT from the
// drivers.rating/acceptance_rate/on_time_rate columns, which are unpopulated
// placeholders in this dataset (verified before building this). The model
// only narrates who needs attention and why; it never recommends
// deactivation — that requires a human review per policy.
// Deploy: supabase functions deploy driver-performance-agent --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

interface DriverMetrics {
  id: string
  name: string
  order_count: number
  cancelled_count: number
  cancellation_rate_pct: number
  avg_delivery_minutes: number | null
  lifetime_completed_deliveries: number
  at_risk_score: number
}

async function computeDriverMetrics(): Promise<DriverMetrics[]> {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString()

  const [{ data: drivers }, { data: orders }] = await Promise.all([
    serviceClient.from('drivers').select('id, full_name, completed_deliveries').eq('status', 'approved'),
    serviceClient
      .from('orders')
      .select('driver_id, status, picked_up_at, delivered_at, ordered_at')
      .gte('ordered_at', thirtyDaysAgo)
      .not('driver_id', 'is', null),
  ])

  const driverRows = drivers ?? []
  const orderRows = orders ?? []

  return driverRows.map((d) => {
    const myOrders = orderRows.filter((o) => o.driver_id === d.id)
    const count = myOrders.length
    const cancelled = myOrders.filter((o) => o.status === 'cancelled').length
    const cancellationRate = count > 0 ? round2((cancelled / count) * 100) : 0

    const deliveryTimes = myOrders
      .filter((o) => o.picked_up_at && o.delivered_at)
      .map((o) => (new Date(o.delivered_at as string).getTime() - new Date(o.picked_up_at as string).getTime()) / 60000)
      .filter((m) => m >= 0 && m < 180)
    const avgDelivery = deliveryTimes.length > 0 ? round2(deliveryTimes.reduce((s, m) => s + m, 0) / deliveryTimes.length) : null

    // Deterministic at-risk score. Drivers with too little recent volume
    // (<3 orders this window) aren't scored — not enough signal.
    let riskScore = 0
    if (count >= 3) {
      riskScore += cancellationRate * 0.6
      if (avgDelivery != null && avgDelivery > 40) riskScore += Math.min((avgDelivery - 40) * 0.5, 30)
    }

    return {
      id: d.id,
      name: d.full_name ?? 'Unknown',
      order_count: count,
      cancelled_count: cancelled,
      cancellation_rate_pct: cancellationRate,
      avg_delivery_minutes: avgDelivery,
      lifetime_completed_deliveries: d.completed_deliveries ?? 0,
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
      .eq('slug', 'driver_performance')
      .maybeSingle()
    if (agentRow?.status === 'paused') return json({ error: 'Driver Performance Agent is paused.' }, 403)

    const metrics = await computeDriverMetrics()

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
              content: `You are the 7Dash Driver Performance Agent. You're given 30-day metrics for every approved driver, ranked by a deterministic at_risk_score (higher = more concerning). Write a short briefing (100-150 words): name the 1-3 drivers most worth checking in on and the specific reason (cancellation rate or slow delivery time — cite the actual numbers), and note any standout performer. Drivers with order_count under 3 have insufficient data — don't flag them. You may ONLY ever recommend a check-in or coaching conversation — never recommend deactivation or suspension, that decision requires a formal human review. Never invent a number not present in the data. Plain text, no markdown.`,
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
      agent_name: 'driver_performance',
      entity_type: 'driver_report',
      entity_id: crypto.randomUUID(),
      related_entities: metrics.map((m) => ({ type: 'driver', id: m.id })),
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

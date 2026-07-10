// executive-agent-brief — Executive Intelligence Agent (7Dash AI Operations)
// Read-only. Computes all figures deterministically in SQL first, then asks
// the model only to narrate those given numbers — it never calculates
// anything itself and cannot take any action (no writes outside the audit log).
// Deploy: supabase functions deploy executive-agent-brief --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

function startOfDay(d: Date): string {
  return new Date(d.getFullYear(), d.getMonth(), d.getDate()).toISOString()
}

async function computeMetrics() {
  const now = new Date()
  const todayStart = startOfDay(now)
  const yesterday = new Date(now)
  yesterday.setDate(yesterday.getDate() - 1)
  const yesterdayStart = startOfDay(yesterday)
  const sevenDaysAgo = new Date(now)
  sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7)
  const sevenDaysStart = sevenDaysAgo.toISOString()

  const [
    todayOrders,
    yesterdayOrders,
    last7dOrders,
    activeRestaurants,
    activeDrivers,
    supportEscalations,
    supportCreditsIssued,
  ] = await Promise.all([
    serviceClient.from('orders').select('total_amount, status, payment_status').gte('ordered_at', todayStart),
    serviceClient.from('orders').select('total_amount, status').gte('ordered_at', yesterdayStart).lt('ordered_at', todayStart),
    serviceClient.from('orders').select('total_amount, status, payment_status').gte('ordered_at', sevenDaysStart),
    serviceClient.from('restaurants').select('id', { count: 'exact', head: true }).eq('status', 'approved'),
    serviceClient.from('drivers').select('id', { count: 'exact', head: true }).eq('status', 'approved'),
    // ── Cross-agent signal: what has the Support Agent been seeing? ──
    serviceClient
      .from('ai_agent_runs')
      .select('id', { count: 'exact', head: true })
      .eq('agent_name', 'support_agent_draft')
      .eq('output->>suggested_action', 'escalate')
      .gte('created_at', sevenDaysStart),
    serviceClient
      .from('ai_agent_runs')
      .select('output')
      .eq('agent_name', 'support_agent_approve')
      .eq('output->>credit_issued', 'true')
      .gte('created_at', sevenDaysStart),
  ])

  const today = todayOrders.data ?? []
  const yesterdayRows = yesterdayOrders.data ?? []
  const last7d = last7dOrders.data ?? []

  const sum = (rows: { total_amount: number }[]) => rows.reduce((s, r) => s + (Number(r.total_amount) || 0), 0)
  const countWhere = (rows: { status?: string; payment_status?: string }[], pred: (r: { status?: string; payment_status?: string }) => boolean) =>
    rows.filter(pred).length

  const todayRevenue = round2(sum(today.filter((r) => r.status !== 'cancelled')))
  const yesterdayRevenue = round2(sum(yesterdayRows.filter((r) => r.status !== 'cancelled')))
  const todayOrderCount = today.length
  const todayCancelled = countWhere(today, (r) => r.status === 'cancelled')
  const todayCancelRate = todayOrderCount > 0 ? round2((todayCancelled / todayOrderCount) * 100) : 0
  const avgOrderValueToday = todayOrderCount > 0 ? round2(todayRevenue / (todayOrderCount - todayCancelled || 1)) : 0

  const last7dCount = last7d.length
  const last7dRefunded = countWhere(last7d, (r) => r.payment_status === 'refunded')
  const last7dRefundRate = last7dCount > 0 ? round2((last7dRefunded / last7dCount) * 100) : 0
  const last7dCancelled = countWhere(last7d, (r) => r.status === 'cancelled')
  const last7dCancelRate = last7dCount > 0 ? round2((last7dCancelled / last7dCount) * 100) : 0

  const revenueDeltaPct = yesterdayRevenue > 0
    ? round2(((todayRevenue - yesterdayRevenue) / yesterdayRevenue) * 100)
    : null

  const creditRows = (supportCreditsIssued.data ?? []) as { output: { credit_amount?: number } }[]
  const totalCreditsIssued = round2(creditRows.reduce((s, r) => s + (Number(r.output?.credit_amount) || 0), 0))

  return {
    generated_at: now.toISOString(),
    today: {
      revenue: todayRevenue,
      order_count: todayOrderCount,
      cancelled: todayCancelled,
      cancel_rate_pct: todayCancelRate,
      avg_order_value: avgOrderValueToday,
    },
    yesterday: {
      revenue: yesterdayRevenue,
      order_count: yesterdayRows.length,
    },
    revenue_change_vs_yesterday_pct: revenueDeltaPct,
    last_7_days: {
      order_count: last7dCount,
      refund_rate_pct: last7dRefundRate,
      cancel_rate_pct: last7dCancelRate,
    },
    active_restaurants: activeRestaurants.count ?? 0,
    active_drivers: activeDrivers.count ?? 0,
    support_agent_signal: {
      escalations_last_7_days: supportEscalations.count ?? 0,
      credits_issued_last_7_days: creditRows.length,
      credit_amount_last_7_days: totalCreditsIssued,
    },
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)

    const { data: agentRow } = await serviceClient
      .from('ai_agents')
      .select('status')
      .eq('slug', 'executive_intelligence')
      .maybeSingle()
    if (agentRow?.status === 'paused') {
      return json({ error: 'Executive Intelligence Agent is paused.' }, 403)
    }

    const metrics = await computeMetrics()

    let narrative = ''
    if (OPENAI_API_KEY) {
      const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'gpt-4o',
          messages: [
            {
              role: 'system',
              content: `You are the 7Dash Executive Intelligence Agent. You write a short, direct executive briefing (120-180 words) narrating ONLY the numbers given to you below — never invent, estimate, or extrapolate a figure that isn't present. The support_agent_signal block comes from the Customer Support Agent's own activity log (a different AI agent) — treat escalations and credits issued as real operational signal, not just a metric to restate. Call out the single most important risk or win, and if support_agent_signal shows a notable pattern (e.g. several escalations), name it explicitly. Plain text, no markdown headers.`,
            },
            { role: 'user', content: `Today's metrics:\n${JSON.stringify(metrics, null, 2)}` },
          ],
          temperature: 0.3,
        }),
      })
      if (openaiRes.ok) {
        const completion = await openaiRes.json()
        narrative = completion.choices?.[0]?.message?.content ?? ''
      }
    }

    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'executive_intelligence',
      entity_type: 'daily_briefing',
      entity_id: crypto.randomUUID(),
      input: {},
      output: { metrics, narrative },
      model: 'gpt-4o',
      status: 'completed',
      created_by: admin.id,
    })

    return json({ success: true, metrics, narrative })
  } catch (e) {
    return errorResponse(e)
  }
})

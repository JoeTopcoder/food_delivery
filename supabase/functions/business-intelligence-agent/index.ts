// business-intelligence-agent — Business Intelligence Agent (7Dash AI Operations)
// Ask-a-question interface over real business data. The model NEVER writes or
// runs its own SQL — it can only call the fixed, parameterized query
// functions below (OpenAI tool-calling), each of which is a plain, bounded
// Supabase query. This is the deliberate safety boundary: no free-form DB
// access is ever handed to the model.
// Deploy: supabase functions deploy business-intelligence-agent --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

function clampDate(d: string, fallback: Date): string {
  const parsed = new Date(d)
  if (isNaN(parsed.getTime())) return fallback.toISOString()
  return parsed.toISOString()
}

// ── Deterministic, bounded query tools ──────────────────────────────────────

async function revenueSummary(args: { start_date: string; end_date: string }) {
  const start = clampDate(args.start_date, new Date(Date.now() - 7 * 86400000))
  const end = clampDate(args.end_date, new Date())
  const { data } = await serviceClient
    .from('orders')
    .select('total_amount, status')
    .gte('ordered_at', start)
    .lte('ordered_at', end)
  const rows = data ?? []
  const nonCancelled = rows.filter((r) => r.status !== 'cancelled')
  const revenue = round2(nonCancelled.reduce((s, r) => s + (Number(r.total_amount) || 0), 0))
  return {
    start_date: start.slice(0, 10),
    end_date: end.slice(0, 10),
    total_revenue: revenue,
    order_count: rows.length,
    completed_order_count: nonCancelled.length,
    avg_order_value: nonCancelled.length > 0 ? round2(revenue / nonCancelled.length) : 0,
  }
}

async function topRestaurants(args: { start_date: string; end_date: string; limit?: number }) {
  const start = clampDate(args.start_date, new Date(Date.now() - 30 * 86400000))
  const end = clampDate(args.end_date, new Date())
  const limit = Math.max(1, Math.min(Number(args.limit) || 5, 20))
  const { data } = await serviceClient
    .from('orders')
    .select('restaurant_id, total_amount, status, restaurants(name)')
    .gte('ordered_at', start)
    .lte('ordered_at', end)
    .neq('status', 'cancelled')
  const rows = (data ?? []) as { restaurant_id: string; total_amount: number; restaurants: { name: string } | null }[]
  const byRestaurant = new Map<string, { name: string; revenue: number; orders: number }>()
  for (const r of rows) {
    const key = r.restaurant_id
    const existing = byRestaurant.get(key) ?? { name: r.restaurants?.name ?? 'Unknown', revenue: 0, orders: 0 }
    existing.revenue += Number(r.total_amount) || 0
    existing.orders += 1
    byRestaurant.set(key, existing)
  }
  const ranked = Array.from(byRestaurant.values())
    .map((r) => ({ ...r, revenue: round2(r.revenue) }))
    .sort((a, b) => b.revenue - a.revenue)
    .slice(0, limit)
  return { start_date: start.slice(0, 10), end_date: end.slice(0, 10), top_restaurants: ranked }
}

async function cancellationAndRefundRates(args: { start_date: string; end_date: string }) {
  const start = clampDate(args.start_date, new Date(Date.now() - 7 * 86400000))
  const end = clampDate(args.end_date, new Date())
  const { data } = await serviceClient
    .from('orders')
    .select('status, payment_status')
    .gte('ordered_at', start)
    .lte('ordered_at', end)
  const rows = data ?? []
  const total = rows.length
  const cancelled = rows.filter((r) => r.status === 'cancelled').length
  const refunded = rows.filter((r) => r.payment_status === 'refunded').length
  return {
    start_date: start.slice(0, 10),
    end_date: end.slice(0, 10),
    order_count: total,
    cancellation_rate_pct: total > 0 ? round2((cancelled / total) * 100) : 0,
    refund_rate_pct: total > 0 ? round2((refunded / total) * 100) : 0,
  }
}

async function agentActivitySummary(args: { start_date: string; end_date: string }) {
  const start = clampDate(args.start_date, new Date(Date.now() - 7 * 86400000))
  const end = clampDate(args.end_date, new Date())
  const { data } = await serviceClient
    .from('ai_agent_runs')
    .select('agent_name, status, output')
    .gte('created_at', start)
    .lte('created_at', end)
  const rows = data ?? []
  const byAgent = new Map<string, number>()
  let escalations = 0
  let creditsIssued = 0
  let creditAmount = 0
  for (const r of rows) {
    byAgent.set(r.agent_name, (byAgent.get(r.agent_name) ?? 0) + 1)
    const out = r.output as Record<string, unknown> | null
    if (out?.suggested_action === 'escalate') escalations++
    if (out?.credit_issued === true) {
      creditsIssued++
      creditAmount += Number(out.credit_amount) || 0
    }
  }
  return {
    start_date: start.slice(0, 10),
    end_date: end.slice(0, 10),
    total_agent_runs: rows.length,
    runs_by_agent: Object.fromEntries(byAgent),
    escalations,
    credits_issued: creditsIssued,
    credit_amount: round2(creditAmount),
  }
}

async function networkCounts() {
  const [restaurants, drivers] = await Promise.all([
    serviceClient.from('restaurants').select('id', { count: 'exact', head: true }).eq('status', 'approved'),
    serviceClient.from('drivers').select('id', { count: 'exact', head: true }).eq('status', 'approved'),
  ])
  return { active_restaurants: restaurants.count ?? 0, active_drivers: drivers.count ?? 0 }
}

const KNOWN_AGENT_SLUGS = [
  'support_agent_draft', 'restaurant_support', 'driver_support', 'executive_intelligence',
  'business_intelligence', 'restaurant_success', 'driver_performance', 'menu_intelligence',
  'reputation_management', 'live_order_ops', 'driver_compliance', 'fraud_risk',
  'finance_reconciliation', 'payout_agent', 'refund_resolution', 'customer_retention',
  'restaurant_onboarding', 'driver_recruitment', 'marketing_strategy', 'marketing_content',
  'market_expansion', 'technical_operations', 'restaurant_lead_gen', 'restaurant_sales',
  'dispatch_optimization',
]

/** Bounded, parameterized lookup into the shared agent audit trail — this is
 *  what makes BI genuinely able to answer "what has agent X found lately"
 *  without ever handing the model free-form SQL access. */
async function recentAgentFindings(args: { agent_name?: string; days?: number; limit?: number }) {
  const days = Math.max(1, Math.min(Number(args.days) || 7, 90))
  const limit = Math.max(1, Math.min(Number(args.limit) || 5, 20))
  const since = new Date(Date.now() - days * 86400000).toISOString()

  let query = serviceClient
    .from('ai_agent_runs')
    .select('agent_name, entity_type, output, created_at')
    .eq('status', 'completed')
    .gte('created_at', since)
    .order('created_at', { ascending: false })
    .limit(limit)

  if (args.agent_name) {
    if (!KNOWN_AGENT_SLUGS.includes(args.agent_name)) {
      return { error: `Unknown agent_name. Valid values: ${KNOWN_AGENT_SLUGS.join(', ')}` }
    }
    query = query.eq('agent_name', args.agent_name)
  }

  const { data } = await query
  return {
    since_days: days,
    runs: (data ?? []).map((r) => ({ agent_name: r.agent_name, entity_type: r.entity_type, output: r.output, created_at: r.created_at })),
  }
}

const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'revenue_summary',
      description: 'Total revenue, order count, and average order value for a date range.',
      parameters: {
        type: 'object',
        properties: {
          start_date: { type: 'string', description: 'YYYY-MM-DD' },
          end_date: { type: 'string', description: 'YYYY-MM-DD' },
        },
        required: ['start_date', 'end_date'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'top_restaurants',
      description: 'Top restaurants by revenue for a date range.',
      parameters: {
        type: 'object',
        properties: {
          start_date: { type: 'string', description: 'YYYY-MM-DD' },
          end_date: { type: 'string', description: 'YYYY-MM-DD' },
          limit: { type: 'number', description: 'Max 20, default 5' },
        },
        required: ['start_date', 'end_date'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'cancellation_and_refund_rates',
      description: 'Cancellation rate and refund rate for a date range.',
      parameters: {
        type: 'object',
        properties: {
          start_date: { type: 'string', description: 'YYYY-MM-DD' },
          end_date: { type: 'string', description: 'YYYY-MM-DD' },
        },
        required: ['start_date', 'end_date'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'agent_activity_summary',
      description: 'Counts of AI agent runs, escalations, and wallet credits issued by the Support Agent for a date range.',
      parameters: {
        type: 'object',
        properties: {
          start_date: { type: 'string', description: 'YYYY-MM-DD' },
          end_date: { type: 'string', description: 'YYYY-MM-DD' },
        },
        required: ['start_date', 'end_date'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'network_counts',
      description: 'Current count of active (approved) restaurants and drivers.',
      parameters: { type: 'object', properties: {} },
    },
  },
  {
    type: 'function',
    function: {
      name: 'recent_agent_findings',
      description: `Look up what a specific 7Dash AI agent has found/reported recently, from the shared agent audit trail. Use this when the question is about what another agent (e.g. Fraud & Risk, Restaurant Success, Driver Compliance) has flagged, not about raw business data. Valid agent_name values: ${KNOWN_AGENT_SLUGS.join(', ')}.`,
      parameters: {
        type: 'object',
        properties: {
          agent_name: { type: 'string', description: 'One of the known agent slugs. Omit to search across all agents.' },
          days: { type: 'number', description: 'How many days back to look, max 90, default 7' },
          limit: { type: 'number', description: 'Max runs to return, max 20, default 5' },
        },
      },
    },
  },
]

async function executeTool(name: string, args: Record<string, unknown>): Promise<unknown> {
  switch (name) {
    case 'revenue_summary': return revenueSummary(args as { start_date: string; end_date: string })
    case 'top_restaurants': return topRestaurants(args as { start_date: string; end_date: string; limit?: number })
    case 'cancellation_and_refund_rates': return cancellationAndRefundRates(args as { start_date: string; end_date: string })
    case 'agent_activity_summary': return agentActivitySummary(args as { start_date: string; end_date: string })
    case 'network_counts': return networkCounts()
    case 'recent_agent_findings': return recentAgentFindings(args as { agent_name?: string; days?: number; limit?: number })
    default: return { error: `Unknown tool: ${name}` }
  }
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { question } = await req.json()
    if (!question || typeof question !== 'string') return json({ error: 'BAD_REQUEST: question required' }, 400)

    if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)

    const { data: agentRow } = await serviceClient
      .from('ai_agents')
      .select('status')
      .eq('slug', 'business_intelligence')
      .maybeSingle()
    if (agentRow?.status === 'paused') return json({ error: 'Business Intelligence Agent is paused.' }, 403)

    const today = new Date().toISOString().slice(0, 10)
    // deno-lint-ignore no-explicit-any
    const messages: any[] = [
      {
        role: 'system',
        content: `You are the 7Dash Business Intelligence Agent. Today's date is ${today}. Answer the admin's question using ONLY the tools available — never guess, estimate, or state a figure you did not get from a tool call. For questions about raw business numbers (revenue, orders, cancellations), use the direct query tools. For questions about what another 7Dash agent has flagged or found (e.g. "why is X restaurant flagged", "what has Fraud & Risk seen lately"), use recent_agent_findings to pull real findings from that agent's own audit trail — never guess at what another agent "probably" thinks. If a question needs data outside what the tools provide, say so plainly instead of guessing. Cite the actual numbers in your answer (e.g. "$1,234.56 across 42 orders"). Keep answers concise and direct.`,
      },
      { role: 'user', content: question },
    ]

    const toolCallLog: { name: string; args: unknown; result: unknown }[] = []
    let finalAnswer = ''

    for (let round = 0; round < 3; round++) {
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'gpt-4o',
          messages,
          tools: TOOLS,
          tool_choice: 'auto',
          temperature: 0.2,
        }),
      })
      if (!res.ok) {
        const errText = await res.text()
        return json({ error: 'AI request failed', details: errText }, 502)
      }
      const completion = await res.json()
      const msg = completion.choices?.[0]?.message
      if (!msg) return json({ error: 'AI returned no response' }, 502)

      if (msg.tool_calls && msg.tool_calls.length > 0) {
        messages.push(msg)
        for (const call of msg.tool_calls) {
          const args = JSON.parse(call.function.arguments || '{}')
          const result = await executeTool(call.function.name, args)
          toolCallLog.push({ name: call.function.name, args, result })
          messages.push({ role: 'tool', tool_call_id: call.id, content: JSON.stringify(result) })
        }
        continue
      }

      finalAnswer = msg.content ?? ''
      break
    }

    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'business_intelligence',
      entity_type: 'question',
      entity_id: crypto.randomUUID(),
      input: { question },
      output: { answer: finalAnswer, tool_calls: toolCallLog },
      model: 'gpt-4o',
      status: 'completed',
      created_by: admin.id,
    })

    return json({ success: true, answer: finalAnswer, tool_calls: toolCallLog })
  } catch (e) {
    return errorResponse(e)
  }
})

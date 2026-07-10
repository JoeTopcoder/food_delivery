// support-agent-draft — Customer / Restaurant / Driver Support Agents
// (7Dash AI Operations, consolidated)
//
// One function serves all three support agents (support_agent,
// restaurant_support, driver_support in ai_agents) — consolidated to stay
// under the project's edge-function count cap. It auto-detects the ticket
// submitter's role and branches context, prompt, and allowed actions
// accordingly, but each role still checks its OWN ai_agents.status (so
// pausing Driver Support doesn't pause Customer Support) and logs its own
// agent_name for cross-agent audit/context purposes.
//
// Never sends anything and never moves money — that only happens after an
// admin reviews the draft via support-agent-approve.
// Deploy: supabase functions deploy support-agent-draft --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'
import { getCrossAgentContext, summarizeCrossAgentContext, type EntityRef } from '../stripe-shared/agent_context.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

const CUSTOMER_ACTIONS = ['none', 'reply_only', 'credit', 'refund_manual', 'escalate']
const PARTNER_ACTIONS = ['none', 'reply_only', 'escalate'] // restaurant/driver — no wallet credit path

const SAFETY_KEYWORDS = [
  'accident', 'crash', 'collision', 'injur', 'hurt', 'bleeding', 'hospital',
  'assault', 'attacked', 'robbed', 'robbery', 'weapon', 'gun', 'knife',
  'threat', 'threatened', 'unsafe', 'emergency', 'police', 'ambulance',
  'hit by', 'hit-and-run', 'kidnap', 'harass',
]

function detectSafetyIncident(message: string): boolean {
  const lower = message.toLowerCase()
  return SAFETY_KEYWORDS.some((kw) => lower.includes(kw))
}

interface DraftResult {
  draft_reply: string
  suggested_action: string
  suggested_amount: number | null
  confidence: number
  reasoning: string
}

async function saveDraftAndRespond(params: {
  supportRequestId: string
  agentName: string
  input: Record<string, unknown>
  draftReply: string
  suggestedAction: string
  suggestedAmount: number | null
  confidence: number
  reasoning: string
  model: string
  relatedEntities: EntityRef[]
  adminId: string
  status?: string
}) {
  const { data: run, error: runErr } = await serviceClient
    .from('ai_agent_runs')
    .insert({
      agent_name: params.agentName,
      entity_type: 'support_request',
      entity_id: params.supportRequestId,
      related_entities: params.relatedEntities,
      input: params.input,
      output: {
        draft_reply: params.draftReply,
        suggested_action: params.suggestedAction,
        suggested_amount: params.suggestedAmount,
        confidence: params.confidence,
        reasoning: params.reasoning,
      },
      model: params.model,
      status: 'completed',
      created_by: params.adminId,
    })
    .select('id')
    .single()
  if (runErr) return json({ error: 'Failed to log agent run', details: runErr.message }, 500)

  const { error: updateErr } = await serviceClient
    .from('support_requests')
    .update({
      ai_draft_reply: params.draftReply,
      ai_suggested_action: params.suggestedAction,
      ai_suggested_amount: params.suggestedAmount,
      ai_confidence: params.confidence,
      ai_reasoning: params.reasoning,
      ai_run_id: run.id,
      ai_status: 'drafted',
      ...(params.status ? { status: params.status } : {}),
    })
    .eq('id', params.supportRequestId)
  if (updateErr) return json({ error: 'Failed to save draft', details: updateErr.message }, 500)

  return json({
    success: true,
    draft_reply: params.draftReply,
    suggested_action: params.suggestedAction,
    suggested_amount: params.suggestedAmount,
    confidence: params.confidence,
    reasoning: params.reasoning,
    run_id: run.id,
  })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { support_request_id } = await req.json()
    if (!support_request_id) return json({ error: 'BAD_REQUEST: support_request_id required' }, 400)

    const { data: ticket, error: ticketErr } = await serviceClient
      .from('support_requests')
      .select('id, user_id, name, email, category, message, order_id, status')
      .eq('id', support_request_id)
      .single()
    if (ticketErr || !ticket) return json({ error: 'Support request not found' }, 404)

    // ── Role detection: driver, restaurant owner, or plain customer ──
    let driverContext: Record<string, unknown> | null = null
    let restaurantContext: Record<string, unknown> | null = null
    if (ticket.user_id) {
      const [{ data: driver }, { data: restaurant }] = await Promise.all([
        serviceClient
          .from('drivers')
          .select('id, full_name, status, completed_deliveries, cancelled_deliveries, total_earnings, total_paid_out, payouts_enabled, stripe_account_status')
          .eq('user_id', ticket.user_id)
          .maybeSingle(),
        serviceClient.from('restaurants').select('id, name, status, commission_rate').eq('owner_id', ticket.user_id).maybeSingle(),
      ])
      if (driver) driverContext = driver
      if (restaurant) restaurantContext = restaurant
    }
    const role: 'driver' | 'restaurant' | 'customer' = driverContext ? 'driver' : restaurantContext ? 'restaurant' : 'customer'
    const agentName = role === 'driver' ? 'driver_support' : role === 'restaurant' ? 'restaurant_support' : 'support_agent_draft'
    const agentSlug = role === 'driver' ? 'driver_support' : role === 'restaurant' ? 'restaurant_support' : 'support_agent'

    const { data: agentRow } = await serviceClient.from('ai_agents').select('status').eq('slug', agentSlug).maybeSingle()
    if (agentRow?.status === 'paused') {
      return json({ error: `${agentSlug.replace('_', ' ')} agent is paused. An admin must resume it in AI Operations before drafting.` }, 403)
    }

    // ── Driver safety short-circuit — no AI involved, deterministic only ──
    if (role === 'driver' && detectSafetyIncident(ticket.message ?? '')) {
      const safetyReply = `Hi ${ticket.name}, thank you for letting us know. This has been flagged as urgent and a member of our team will reach out to you directly as soon as possible. If you are in immediate danger or need medical attention, please contact local emergency services right away.`
      return await saveDraftAndRespond({
        supportRequestId: support_request_id,
        agentName: 'driver_support',
        input: { ticket, driverContext, safety_keyword_match: true },
        draftReply: safetyReply,
        suggestedAction: 'escalate',
        suggestedAmount: null,
        confidence: 1,
        reasoning: 'SAFETY INCIDENT — flagged by deterministic keyword match. Review immediately.',
        model: 'none (deterministic safety rule)',
        relatedEntities: [{ type: 'user', id: ticket.user_id }, { type: 'driver', id: driverContext!.id as string }],
        adminId: admin.id,
        status: 'reviewing',
      })
    }

    if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)

    // ── Customer role: existing order + policy context ──
    let orderContext: Record<string, unknown> | null = null
    if (role === 'customer' && ticket.order_id) {
      const { data: order } = await serviceClient
        .from('orders')
        .select('id, status, payment_status, payment_method, total_amount, subtotal, delivery_fee, ordered_at, receipt_number, user_id, driver_id, restaurant_id')
        .eq('id', ticket.order_id)
        .maybeSingle()
      if (order) orderContext = order
    }

    // ── Restaurant role: commission + recent volume ──
    if (role === 'restaurant' && restaurantContext) {
      const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString()
      const { data: recentOrders } = await serviceClient
        .from('orders')
        .select('total_amount, status')
        .eq('restaurant_id', restaurantContext.id as string)
        .gte('ordered_at', thirtyDaysAgo)
      const orders = recentOrders ?? []
      restaurantContext = {
        ...restaurantContext,
        orders_last_30_days: orders.length,
        revenue_last_30_days: Math.round(orders.filter((o) => o.status !== 'cancelled').reduce((s, o) => s + (Number(o.total_amount) || 0), 0) * 100) / 100,
      }
    }

    const entityRefs: EntityRef[] = [{ type: 'support_request', id: ticket.id }]
    if (ticket.user_id) entityRefs.push({ type: 'user', id: ticket.user_id })
    if (role === 'customer' && orderContext) {
      entityRefs.push({ type: 'order', id: orderContext.id as string })
      if (orderContext.driver_id) entityRefs.push({ type: 'driver', id: orderContext.driver_id as string })
      if (orderContext.restaurant_id) entityRefs.push({ type: 'restaurant', id: orderContext.restaurant_id as string })
    }
    if (role === 'restaurant' && restaurantContext) entityRefs.push({ type: 'restaurant', id: restaurantContext.id as string })
    if (role === 'driver' && driverContext) entityRefs.push({ type: 'driver', id: driverContext.id as string })

    const relatedRuns = await getCrossAgentContext(entityRefs)
    const crossAgentSummary = summarizeCrossAgentContext(relatedRuns)

    let policySummary: string | null = null
    if (role === 'customer') {
      const { data: policyRow } = await serviceClient.from('app_config').select('value').eq('key', `support_policy_${ticket.category}`).maybeSingle()
      policySummary = policyRow?.value ? String(policyRow.value).replace(/^"|"$/g, '') : null
    }

    let systemPrompt: string
    let userPrompt: string
    if (role === 'customer') {
      systemPrompt = `You are the 7Dash customer support drafting assistant. You write a draft reply and a recommended action for a human admin to review — you never contact the customer directly and you never move money yourself.

Rules:
- Base your reply ONLY on the ticket details and order facts provided below. Never invent order details, dates, amounts, or policy terms that are not given to you.
- If compensation (credit/refund) is requested but no written policy is provided below, recommend "escalate" — do not guess at what's fair.
- suggested_action must be exactly one of: "none", "reply_only", "credit" (wallet credit — only for amounts clearly justified by the order total), "refund_manual" (real refund, must be processed manually via Stripe by an admin), "escalate".
- suggested_amount must never exceed the order's total_amount if an order is attached, and must be null unless suggested_action is "credit" or "refund_manual".
- confidence is 0.0-1.0.
- Keep the reply concise, warm, and specific. Sign off as "The 7Dash Support Team".
- The "Related activity from other AI agents" section is prior findings about this same order/customer/driver/restaurant. Use it to inform judgment but never as a substitute for the ticket's own facts.

Policy on file for this category:
${policySummary ?? 'No written policy on file for this category. If the customer is asking for compensation, you must recommend "escalate".'}

Related activity from other AI agents:
${crossAgentSummary}

Respond ONLY with JSON: { "draft_reply": string, "suggested_action": string, "suggested_amount": number|null, "confidence": number, "reasoning": string }`
      userPrompt = `Ticket:\nName: ${ticket.name}\nCategory: ${ticket.category}\nMessage: ${ticket.message}\n\nOrder on file: ${orderContext ? JSON.stringify(orderContext) : 'No order attached to this ticket.'}`
    } else if (role === 'restaurant') {
      systemPrompt = `You are the 7Dash Restaurant Support drafting assistant. You write a draft reply for a human admin to review — you never contact the restaurant directly.

Rules:
- Base your reply ONLY on the ticket and restaurant account data given. Never invent commission rates, payout amounts, or contract terms.
- You may NEVER promise a commission rate change, contract modification, or financial adjustment — suggested_action must be "escalate" for those requests.
- suggested_action must be exactly one of: "none", "reply_only", "escalate".
- confidence is 0.0-1.0. Sign off as "The 7Dash Partner Support Team".

Related activity from other AI agents:
${crossAgentSummary}

Respond ONLY with JSON: { "draft_reply": string, "suggested_action": string, "confidence": number, "reasoning": string }`
      userPrompt = `Ticket from restaurant partner:\nName: ${ticket.name}\nCategory: ${ticket.category}\nMessage: ${ticket.message}\n\nRestaurant account on file: ${restaurantContext ? JSON.stringify(restaurantContext) : 'No restaurant account matched — treat as a general/prospective partner question.'}`
    } else {
      systemPrompt = `You are the 7Dash Driver Support drafting assistant. You write a draft reply for a human admin to review — you never contact the driver directly.

Rules:
- Base your reply ONLY on the ticket and driver account data given. Never invent earnings figures, payout dates, or delivery counts.
- You may NEVER promise a specific payout amount or timeline — suggested_action must be "escalate" for earnings/payout disputes.
- suggested_action must be exactly one of: "none", "reply_only", "escalate".
- confidence is 0.0-1.0. Sign off as "The 7Dash Driver Support Team".

Related activity from other AI agents:
${crossAgentSummary}

Respond ONLY with JSON: { "draft_reply": string, "suggested_action": string, "confidence": number, "reasoning": string }`
      userPrompt = `Ticket from driver:\nName: ${ticket.name}\nCategory: ${ticket.category}\nMessage: ${ticket.message}\n\nDriver account on file: ${driverContext ? JSON.stringify(driverContext) : 'No driver account matched to this user.'}`
    }

    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [{ role: 'system', content: systemPrompt }, { role: 'user', content: userPrompt }],
        response_format: { type: 'json_object' },
        temperature: 0.3,
      }),
    })

    if (!openaiRes.ok) {
      const errText = await openaiRes.text()
      await serviceClient.from('ai_agent_runs').insert({
        agent_name: agentName,
        entity_type: 'support_request',
        entity_id: support_request_id,
        related_entities: entityRefs.filter((r) => r.type !== 'support_request'),
        input: { ticket, orderContext, restaurantContext, driverContext },
        status: 'failed',
        error: errText,
        created_by: admin.id,
      })
      return json({ error: 'AI drafting failed', details: errText }, 502)
    }

    const completion = await openaiRes.json()
    let parsed: DraftResult
    try {
      parsed = JSON.parse(completion.choices?.[0]?.message?.content ?? '{}')
    } catch {
      return json({ error: 'AI returned invalid JSON' }, 502)
    }

    const allowedActions = role === 'customer' ? CUSTOMER_ACTIONS : PARTNER_ACTIONS
    const suggestedAction = allowedActions.includes(parsed.suggested_action) ? parsed.suggested_action : 'escalate'
    const orderTotal = orderContext ? Number(orderContext.total_amount) || 0 : 0
    let suggestedAmount: number | null = null
    if (role === 'customer' && (suggestedAction === 'credit' || suggestedAction === 'refund_manual') && parsed.suggested_amount != null) {
      const raw = Number(parsed.suggested_amount) || 0
      suggestedAmount = orderContext ? Math.max(0, Math.min(raw, orderTotal)) : Math.max(0, raw)
    }
    const confidence = Math.max(0, Math.min(1, Number(parsed.confidence) || 0))
    const draftReply = String(parsed.draft_reply ?? '').slice(0, 4000)
    const reasoning = String(parsed.reasoning ?? '').slice(0, 2000)

    return await saveDraftAndRespond({
      supportRequestId: support_request_id,
      agentName,
      input: { ticket, orderContext, restaurantContext, driverContext, policySummary, cross_agent_context_used: relatedRuns.length },
      draftReply,
      suggestedAction,
      suggestedAmount,
      confidence,
      reasoning,
      model: 'gpt-4o-mini',
      relatedEntities: entityRefs.filter((r) => r.type !== 'support_request'),
      adminId: admin.id,
    })
  } catch (e) {
    return errorResponse(e)
  }
})

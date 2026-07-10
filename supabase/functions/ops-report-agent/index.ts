// ops-report-agent — consolidated read-only report agents (7Dash AI Operations)
//
// One function hosts every read-only "compute metrics deterministically,
// narrate with AI, take no action" agent, dispatched by agent_slug. This is
// deliberate: the project has a hard cap on total edge functions, so
// building one function per report-style agent isn't sustainable. Each
// branch still independently checks its own ai_agents.status and logs its
// own agent_name, so pausing one agent doesn't affect another and the audit
// trail is identical to what a dedicated function would produce.
//
// To add a new report agent: add a case to REPORT_GENERATORS below. Do NOT
// create a new edge function for a read-only report agent — add it here.
// Deploy: supabase functions deploy ops-report-agent --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''
const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const SALES_FROM_EMAIL = Deno.env.get('SALES_FROM_EMAIL') ?? '7Dash Partnerships <onboarding@resend.dev>'

interface ReportResult {
  metrics: unknown
  relatedEntities: { type: string; id: string }[]
  systemPrompt: string
}

function round2(n: number): number {
  return Math.round(n * 100) / 100
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371
  const dLat = (lat2 - lat1) * Math.PI / 180
  const dLon = (lon2 - lon1) * Math.PI / 180
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a))
}

// ── live_order_ops ───────────────────────────────────────────────────────
async function liveOrderOps(): Promise<ReportResult> {
  const now = new Date()
  const { data: orders } = await serviceClient
    .from('orders')
    .select('id, status, ordered_at, ready_at, picked_up_at, driver_id, restaurant_id, is_pickup, scheduled_for, receipt_number')
    .not('status', 'in', '("delivered","cancelled")')

  const rows = orders ?? []
  const restaurantIds = [...new Set(rows.map((o) => o.restaurant_id).filter(Boolean))]
  const { data: restaurants } = restaurantIds.length > 0
    ? await serviceClient.from('restaurants').select('id, name').in('id', restaurantIds)
    : { data: [] }
  const restaurantNames = new Map((restaurants ?? []).map((r) => [r.id, r.name]))

  const flagged: Record<string, unknown>[] = []
  for (const o of rows) {
    if (o.scheduled_for && new Date(o.scheduled_for) > now) continue // not due yet
    const elapsedSinceOrderMin = round2((now.getTime() - new Date(o.ordered_at).getTime()) / 60000)

    let reason: string | null = null
    let elapsed = elapsedSinceOrderMin
    if (o.status === 'preparing' && !o.ready_at && elapsedSinceOrderMin > 45) {
      reason = 'prep_delay'
    } else if (o.ready_at && !o.driver_id && !o.is_pickup) {
      reason = 'unassigned_after_ready'
      elapsed = round2((now.getTime() - new Date(o.ready_at).getTime()) / 60000)
    } else if (o.picked_up_at && o.status !== 'delivered') {
      const sincePickup = round2((now.getTime() - new Date(o.picked_up_at).getTime()) / 60000)
      if (sincePickup > 60) { reason = 'delivery_delay'; elapsed = sincePickup }
    }

    if (reason) {
      flagged.push({
        order_id: o.id,
        receipt_number: o.receipt_number,
        restaurant: restaurantNames.get(o.restaurant_id) ?? 'Unknown',
        status: o.status,
        reason,
        elapsed_minutes: elapsed,
      })
    }
  }

  return {
    metrics: { active_order_count: rows.length, flagged_count: flagged.length, flagged_orders: flagged },
    relatedEntities: rows.map((o) => ({ type: 'order', id: o.id })),
    systemPrompt: `You are the 7Dash Live Order Operations Agent. You're given currently active orders and which ones are flagged as delayed (prep_delay = kitchen hasn't marked ready in 45+ min, unassigned_after_ready = ready but no driver assigned, delivery_delay = picked up 60+ min ago and not delivered). Write a short briefing (80-140 words) on what needs attention right now. If flagged_count is 0, say operations look healthy — don't invent a problem. Never invent an order or number not in the data. Plain text, no markdown.`,
  }
}

// ── driver_compliance ────────────────────────────────────────────────────
async function driverCompliance(): Promise<ReportResult> {
  const now = new Date()
  const thirtyDaysOut = new Date(now.getTime() + 30 * 86400000)

  const { data: drivers } = await serviceClient
    .from('drivers')
    .select('id, full_name, license_expiry_date, documents_status, is_verified')
    .eq('status', 'approved')

  const rows = drivers ?? []
  const flagged: Record<string, unknown>[] = []
  let missingExpiryDate = 0
  for (const d of rows) {
    if (!d.license_expiry_date) { missingExpiryDate++; continue }
    const expiry = new Date(d.license_expiry_date)
    if (expiry <= thirtyDaysOut) {
      flagged.push({
        driver: d.full_name ?? 'Unknown',
        license_expiry_date: d.license_expiry_date,
        status: expiry < now ? 'expired' : 'expiring_soon',
        days_remaining: Math.round((expiry.getTime() - now.getTime()) / 86400000),
      })
    }
  }
  flagged.sort((a, b) => (a.days_remaining as number) - (b.days_remaining as number))

  return {
    metrics: {
      approved_driver_count: rows.length,
      missing_expiry_date_on_file: missingExpiryDate,
      flagged_count: flagged.length,
      flagged_drivers: flagged,
    },
    relatedEntities: rows.map((d) => ({ type: 'driver', id: d.id })),
    systemPrompt: `You are the 7Dash Driver Compliance Agent. You're given approved drivers' license expiry status. "expired" means their license has already expired and they should not be actively delivering; "expiring_soon" means within 30 days. Write a short briefing (80-140 words) on which drivers need renewal reminders or immediate suspension review, most urgent first. If missing_expiry_date_on_file is high, note that as a data-quality gap worth fixing during onboarding — don't treat missing data as a compliance violation itself. You may only ever recommend sending a reminder or flagging for review — never state that you've suspended or deactivated anyone, that requires a human decision. Never invent a driver or date not in the data. Plain text, no markdown.`,
  }
}

// ── fraud_risk ────────────────────────────────────────────────────────────
async function fraudRisk(): Promise<ReportResult> {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString()

  const [{ data: disputes }, { data: approveRuns }, { data: users }] = await Promise.all([
    serviceClient.from('disputes').select('id, order_id, user_id, type, status, created_at').gte('created_at', thirtyDaysAgo),
    serviceClient
      .from('ai_agent_runs')
      .select('entity_id, output, created_at')
      .eq('agent_name', 'support_agent_approve')
      .eq('output->>credit_issued', 'true')
      .gte('created_at', thirtyDaysAgo),
    serviceClient.from('users').select('id, name, email'),
  ])

  const userNames = new Map((users ?? []).map((u) => [u.id, u.name || u.email || 'Unknown']))
  const disputeRows = disputes ?? []

  // Signal 1: users with 2+ disputes in 30 days
  const disputesByUser = new Map<string, number>()
  for (const d of disputeRows) {
    if (!d.user_id) continue
    disputesByUser.set(d.user_id, (disputesByUser.get(d.user_id) ?? 0) + 1)
  }

  // Signal 2: users with 2+ credits issued via Support Agent in 30 days
  // (cross-agent signal — reuses Support Agent's own audit trail as fraud input).
  // ai_agent_runs.entity_id for these rows is the support_request_id, so we
  // join back to support_requests to find who actually got credited.
  const creditsByUser = new Map<string, number>()
  const creditedTicketIds = (approveRuns ?? []).map((r) => r.entity_id).filter(Boolean)
  if (creditedTicketIds.length > 0) {
    const { data: creditedTickets } = await serviceClient
      .from('support_requests')
      .select('id, user_id')
      .in('id', creditedTicketIds)
    for (const t of creditedTickets ?? []) {
      if (!t.user_id) continue
      creditsByUser.set(t.user_id, (creditsByUser.get(t.user_id) ?? 0) + 1)
    }
  }

  const flagged: Record<string, unknown>[] = []
  const allUserIds = new Set([...disputesByUser.keys(), ...creditsByUser.keys()])
  for (const userId of allUserIds) {
    const disputeCount = disputesByUser.get(userId) ?? 0
    const creditCount = creditsByUser.get(userId) ?? 0
    if (disputeCount >= 2 || creditCount >= 2 || (disputeCount >= 1 && creditCount >= 1)) {
      flagged.push({
        user: userNames.get(userId) ?? userId,
        disputes_last_30_days: disputeCount,
        support_credits_last_30_days: creditCount,
      })
    }
  }
  flagged.sort((a, b) => ((b.disputes_last_30_days as number) + (b.support_credits_last_30_days as number)) - ((a.disputes_last_30_days as number) + (a.support_credits_last_30_days as number)))

  return {
    metrics: { total_disputes_30d: disputeRows.length, flagged_count: flagged.length, flagged_users: flagged },
    relatedEntities: Array.from(allUserIds).map((id) => ({ type: 'user', id })),
    systemPrompt: `You are the 7Dash Fraud and Risk Agent. You're given customers flagged for repeated disputes and/or repeated Support Agent wallet credits within 30 days — a pattern worth reviewing for possible abuse. Write a short briefing (80-140 words) naming who's most worth reviewing and why (cite the actual counts). This is a REVIEW recommendation only — you may never state that an account was banned, restricted, or penalized; only that it should be reviewed by a human. If flagged_count is 0, say no notable patterns were found. Never invent a user or number not in the data. Plain text, no markdown.`,
  }
}

// ── finance_reconciliation ───────────────────────────────────────────────
async function financeReconciliation(): Promise<ReportResult> {
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400000).toISOString()

  const { data: orders } = await serviceClient
    .from('orders')
    .select('id, payment_status, payment_method, total_amount, commission_amount, ordered_at, receipt_number')
    .gte('ordered_at', thirtyDaysAgo)

  const rows = orders ?? []
  const byStatus = new Map<string, { count: number; total: number }>()
  for (const o of rows) {
    const key = o.payment_status ?? 'unknown'
    const entry = byStatus.get(key) ?? { count: 0, total: 0 }
    entry.count += 1
    entry.total = round2(entry.total + (Number(o.total_amount) || 0))
    byStatus.set(key, entry)
  }

  // Stuck payments: pending for over 1 hour is anomalous — place-order gates
  // payment before insert, so a lingering 'pending' row is worth a look.
  const oneHourAgo = new Date(Date.now() - 3600000)
  const stuckPending = rows.filter((o) => o.payment_status === 'pending' && new Date(o.ordered_at) < oneHourAgo)

  const totalCommission = round2(rows.reduce((s, o) => s + (Number(o.commission_amount) || 0), 0))
  const totalRevenue = round2(rows.filter((o) => o.payment_status === 'completed').reduce((s, o) => s + (Number(o.total_amount) || 0), 0))

  return {
    metrics: {
      period_days: 30,
      total_orders: rows.length,
      by_payment_status: Object.fromEntries(Array.from(byStatus.entries()).map(([k, v]) => [k, v])),
      total_revenue_completed: totalRevenue,
      total_commission: totalCommission,
      stuck_pending_count: stuckPending.length,
      stuck_pending_orders: stuckPending.map((o) => ({ receipt_number: o.receipt_number, ordered_at: o.ordered_at, total_amount: o.total_amount })),
    },
    relatedEntities: stuckPending.map((o) => ({ type: 'order', id: o.id })),
    systemPrompt: `You are the 7Dash Finance and Reconciliation Agent. You're given 30-day payment status breakdown and orders stuck in 'pending' payment status for over an hour (which is anomalous — payment is normally confirmed before an order is even created, so a lingering pending order usually means a payment webhook or edge function failure). Write a short briefing (80-140 words) summarizing revenue/commission and flagging any stuck payments needing investigation, citing actual numbers. You explain the numbers — you are NOT the authoritative ledger; if something looks off, recommend a human check Stripe directly. Never invent a figure not in the data. Plain text, no markdown.`,
  }
}

// ── payout_agent ──────────────────────────────────────────────────────────
// Read-only triage only. Actual payout submission is handled by the
// deterministic request-payout / approve-payout-request / stripe-pay-from-
// payout-request functions built earlier — this agent never moves money,
// it just helps an admin prioritize the pending queue.
async function payoutTriage(): Promise<ReportResult> {
  const { data: pending } = await serviceClient
    .from('stripe_payout_requests')
    .select('id, user_id, role, stripe_account_id, amount_cents, currency, status, created_at')
    .eq('status', 'pending')
    .order('created_at', { ascending: true })

  const rows = pending ?? []
  const accountIds = [...new Set(rows.map((r) => r.stripe_account_id).filter(Boolean))]
  const { data: accounts } = accountIds.length > 0
    ? await serviceClient.from('stripe_connected_accounts').select('stripe_account_id, payouts_enabled, onboarding_status').in('stripe_account_id', accountIds)
    : { data: [] }
  const accountByStripeId = new Map((accounts ?? []).map((a) => [a.stripe_account_id, a]))

  const userIds = [...new Set(rows.map((r) => r.user_id).filter(Boolean))]
  const { data: users } = userIds.length > 0 ? await serviceClient.from('users').select('id, name, email').in('id', userIds) : { data: [] }
  const userNames = new Map((users ?? []).map((u) => [u.id, u.name || u.email || 'Unknown']))

  const { data: settings } = await serviceClient.from('app_payout_settings').select('min_payout_cents, max_payout_cents').limit(1).maybeSingle()
  const minCents = settings?.min_payout_cents ?? 0
  const maxCents = settings?.max_payout_cents ?? Number.MAX_SAFE_INTEGER

  const triaged = rows.map((r) => {
    const account = accountByStripeId.get(r.stripe_account_id)
    const issues: string[] = []
    if (!account?.payouts_enabled) issues.push('connected_account_not_payout_ready')
    if (r.amount_cents < minCents) issues.push('below_minimum')
    if (r.amount_cents > maxCents) issues.push('above_maximum_needs_extra_review')
    return {
      requester: userNames.get(r.user_id) ?? r.user_id,
      role: r.role,
      amount: round2(r.amount_cents / 100),
      currency: r.currency,
      waiting_since: r.created_at,
      ready_to_pay: issues.length === 0,
      issues,
    }
  })

  const readyCount = triaged.filter((t) => t.ready_to_pay).length
  const blockedCount = triaged.length - readyCount

  return {
    metrics: {
      pending_count: rows.length,
      ready_to_pay_count: readyCount,
      blocked_count: blockedCount,
      total_pending_amount: round2(rows.reduce((s, r) => s + r.amount_cents, 0) / 100),
      payouts: triaged,
    },
    relatedEntities: rows.map((r) => ({ type: 'user', id: r.user_id })),
    systemPrompt: `You are the 7Dash Payout Agent. You're given pending driver/restaurant payout requests, each triaged as ready_to_pay or blocked (with specific issues: connected_account_not_payout_ready means their Stripe Connect onboarding isn't finished, below_minimum/above_maximum are against configured thresholds). Write a short briefing (80-140 words): how many are ready to pay now, and call out any blocked ones and why. You do NOT submit payouts yourself — an admin does that through the existing payout approval screen. Never invent a payout or amount not in the data. Plain text, no markdown.`,
  }
}

// ── refund_resolution ─────────────────────────────────────────────────────
// Read-only recommendation only. Actual dispute resolution still happens
// through the existing dispute-management screen — this agent doesn't
// change any dispute's status or issue anything itself.
async function refundResolution(): Promise<ReportResult> {
  const { data: disputes } = await serviceClient
    .from('disputes')
    .select('id, order_id, user_id, type, description, status, created_at')
    .neq('status', 'resolved')
    .order('created_at', { ascending: true })

  const rows = disputes ?? []
  const orderIds = [...new Set(rows.map((d) => d.order_id).filter(Boolean))]
  const { data: orders } = orderIds.length > 0
    ? await serviceClient.from('orders').select('id, status, total_amount, payment_status, ordered_at').in('id', orderIds)
    : { data: [] }
  const orderById = new Map((orders ?? []).map((o) => [o.id, o]))

  const userIds = [...new Set(rows.map((d) => d.user_id).filter(Boolean))]
  const { data: users } = userIds.length > 0 ? await serviceClient.from('users').select('id, name').in('id', userIds) : { data: [] }
  const userNames = new Map((users ?? []).map((u) => [u.id, u.name ?? 'Unknown']))

  const cases = rows.map((d) => {
    const order = orderById.get(d.order_id)
    const daysOpen = Math.round((Date.now() - new Date(d.created_at).getTime()) / 86400000)
    return {
      dispute_id: d.id,
      customer: userNames.get(d.user_id) ?? 'Unknown',
      type: d.type,
      description: d.description,
      order_total: order?.total_amount ?? null,
      order_status: order?.status ?? null,
      days_open: daysOpen,
    }
  })

  return {
    metrics: { open_dispute_count: rows.length, cases },
    relatedEntities: [
      ...rows.map((d) => ({ type: 'order', id: d.order_id })).filter((r) => r.id),
      ...rows.map((d) => ({ type: 'user', id: d.user_id })).filter((r) => r.id),
    ],
    systemPrompt: `You are the 7Dash Refund and Resolution Agent. You're given open customer disputes with their order context. For each, suggest a likely-fair outcome (no compensation / partial refund / full refund / redelivery / needs human investigation) with brief reasoning, based only on the type/description/order data given — never invent facts about what happened. Prioritize disputes open longest. Write a short briefing (100-160 words) — you are a recommendation only, an admin still resolves each case through the dispute screen. If open_dispute_count is 0, say there's nothing pending. Plain text, no markdown.`,
  }
}

// ── customer_retention ───────────────────────────────────────────────────
async function customerRetention(): Promise<ReportResult> {
  const { data: customers } = await serviceClient.from('users').select('id, name, email, created_at').eq('role', 'customer')
  const { data: orders } = await serviceClient.from('orders').select('user_id, ordered_at, total_amount')

  const rows = customers ?? []
  const orderRows = orders ?? []
  const lastOrderByUser = new Map<string, string>()
  const orderCountByUser = new Map<string, number>()
  const totalSpentByUser = new Map<string, number>()
  for (const o of orderRows) {
    if (!o.user_id) continue
    orderCountByUser.set(o.user_id, (orderCountByUser.get(o.user_id) ?? 0) + 1)
    totalSpentByUser.set(o.user_id, (totalSpentByUser.get(o.user_id) ?? 0) + (Number(o.total_amount) || 0))
    const existing = lastOrderByUser.get(o.user_id)
    if (!existing || new Date(o.ordered_at) > new Date(existing)) lastOrderByUser.set(o.user_id, o.ordered_at)
  }

  const now = Date.now()
  const atRisk: Record<string, unknown>[] = []
  for (const c of rows) {
    const lastOrder = lastOrderByUser.get(c.id)
    const orderCount = orderCountByUser.get(c.id) ?? 0
    if (orderCount === 0) continue // never ordered — not a retention case, that's acquisition
    const daysSinceLastOrder = lastOrder ? Math.round((now - new Date(lastOrder).getTime()) / 86400000) : null
    if (daysSinceLastOrder != null && daysSinceLastOrder >= 21) {
      atRisk.push({
        customer: c.name ?? c.email,
        days_since_last_order: daysSinceLastOrder,
        lifetime_orders: orderCount,
        lifetime_spend: round2(totalSpentByUser.get(c.id) ?? 0),
      })
    }
  }
  atRisk.sort((a, b) => (b.days_since_last_order as number) - (a.days_since_last_order as number))

  return {
    metrics: { total_customers_with_orders: [...orderCountByUser.keys()].length, at_risk_count: atRisk.length, at_risk_customers: atRisk.slice(0, 20) },
    relatedEntities: [],
    systemPrompt: `You are the 7Dash Customer Retention Agent. You're given customers who've ordered before but not in 21+ days, ranked by longest absence. Write a short briefing (80-140 words) on who's most worth a reactivation nudge and why (cite lifetime orders/spend to show they're worth retaining, not just any lapsed user). You may only ever RECOMMEND outreach — no message-sending channel is wired to this agent, so don't claim anything was sent. If at_risk_count is 0, say retention looks healthy. Never invent a customer or number not in the data. Plain text, no markdown.`,
  }
}

// ── restaurant_onboarding ─────────────────────────────────────────────────
async function restaurantOnboarding(): Promise<ReportResult> {
  const { data: draftRestaurants } = await serviceClient
    .from('restaurants')
    .select('id, name, created_at')
    .eq('status', 'draft')

  const rows = draftRestaurants ?? []
  const restaurantIds = rows.map((r) => r.id)
  const { data: menuItems } = restaurantIds.length > 0
    ? await serviceClient.from('menus').select('restaurant_id').in('restaurant_id', restaurantIds)
    : { data: [] }
  const menuCountByRestaurant = new Map<string, number>()
  for (const m of menuItems ?? []) {
    menuCountByRestaurant.set(m.restaurant_id, (menuCountByRestaurant.get(m.restaurant_id) ?? 0) + 1)
  }

  const checklist = rows.map((r) => {
    const menuCount = menuCountByRestaurant.get(r.id) ?? 0
    const daysSinceCreated = Math.round((Date.now() - new Date(r.created_at).getTime()) / 86400000)
    const missing: string[] = []
    if (menuCount === 0) missing.push('no_menu_items')
    return {
      restaurant: r.name,
      days_since_application: daysSinceCreated,
      menu_item_count: menuCount,
      missing,
      launch_ready: missing.length === 0,
    }
  })

  return {
    metrics: { draft_restaurant_count: rows.length, ready_count: checklist.filter((c) => c.launch_ready).length, checklist },
    relatedEntities: rows.map((r) => ({ type: 'restaurant', id: r.id })),
    systemPrompt: `You are the 7Dash Restaurant Onboarding Agent. You're given restaurants still in "draft" status with their launch checklist (currently checking: has at least one menu item). Write a short briefing (80-140 words) on which are close to launch-ready and which need follow-up, citing days since application and what's missing. You recommend only — an admin still approves each restaurant. Never invent a restaurant or fact not in the data. Plain text, no markdown.`,
  }
}

// ── driver_recruitment ────────────────────────────────────────────────────
async function driverRecruitment(): Promise<ReportResult> {
  const { data: pendingDrivers } = await serviceClient
    .from('drivers')
    .select('id, full_name, created_at, documents_uploaded, is_verified, onboarding_step, license_number, driver_license_url, vehicle_registration_url, insurance_document_url')
    .eq('status', 'pending')

  const rows = pendingDrivers ?? []
  const checklist = rows.map((d) => {
    const daysSinceApplied = Math.round((Date.now() - new Date(d.created_at).getTime()) / 86400000)
    const missing: string[] = []
    if (!d.license_number) missing.push('license_number')
    if (!d.driver_license_url) missing.push('license_document')
    if (!d.vehicle_registration_url) missing.push('vehicle_registration')
    if (!d.insurance_document_url) missing.push('insurance_document')
    if (!d.is_verified) missing.push('identity_verification')
    return {
      applicant: d.full_name ?? 'Unnamed applicant',
      days_since_applied: daysSinceApplied,
      missing_requirements: missing,
      ready_for_approval: missing.length === 0,
    }
  })

  return {
    metrics: { pending_applicant_count: rows.length, ready_for_approval_count: checklist.filter((c) => c.ready_for_approval).length, checklist },
    relatedEntities: rows.map((d) => ({ type: 'driver', id: d.id })),
    systemPrompt: `You are the 7Dash Driver Recruitment Agent. You're given pending driver applications and what's missing from each (license number/document, vehicle registration, insurance, identity verification). Write a short briefing (80-140 words) on which applicants are ready for approval and which need to be chased for missing documents, prioritizing by days waiting. You recommend only — an admin still approves each driver per policy. Never invent an applicant or fact not in the data. Plain text, no markdown.`,
  }
}

// ── marketing_strategy ────────────────────────────────────────────────────
async function marketingStrategy(): Promise<ReportResult> {
  const { data: promos } = await serviceClient
    .from('promo_codes')
    .select('id, code, description, discount_type, discount_value, usage_limit, usage_count, is_active, valid_until, expires_at')
    .eq('is_active', true)

  const rows = promos ?? []
  const now = new Date()
  const analysis = rows.map((p) => {
    const limit = p.usage_limit ?? null
    const utilizationPct = limit ? round2((p.usage_count / limit) * 100) : null
    const expiry = p.valid_until ?? p.expires_at
    const daysUntilExpiry = expiry ? Math.round((new Date(expiry).getTime() - now.getTime()) / 86400000) : null
    return {
      code: p.code,
      discount: `${p.discount_value}${p.discount_type === 'percentage' ? '%' : ' flat'}`,
      redemptions: p.usage_count ?? 0,
      usage_limit: limit,
      utilization_pct: utilizationPct,
      days_until_expiry: daysUntilExpiry,
    }
  })

  return {
    metrics: { active_promo_count: rows.length, promos: analysis },
    relatedEntities: [],
    systemPrompt: `You are the 7Dash Marketing Strategy Agent. You're given currently active promo codes with redemption counts and utilization. Write a short briefing (80-140 words): call out promos that are underperforming (low utilization, especially if expiring soon — may need better placement or a bigger incentive) and any that are close to hitting their usage limit (may be worth extending). You recommend only — no budget or promo is created/changed by you. If active_promo_count is 0, say there are no active promotions right now. Never invent a promo or number not in the data. Plain text, no markdown.`,
  }
}

// ── restaurant_lead_gen ───────────────────────────────────────────────────
// Scores and dedupes MANUALLY-ENTERED leads (restaurant_leads table) — this
// app has no external business-data API, so it can't discover new prospects
// on its own. An admin identifies and enters leads themselves; this agent
// helps prioritize and catch duplicates against restaurants already on the
// platform, using a real cuisine-gap signal from actual restaurant data.
async function restaurantLeadGen(): Promise<ReportResult> {
  const [{ data: leads }, { data: existingRestaurants }] = await Promise.all([
    serviceClient.from('restaurant_leads').select('id, name, phone, email, address, cuisine_type, source, status, created_at').eq('status', 'new'),
    serviceClient.from('restaurants').select('name, cuisine_type'),
  ])

  const leadRows = leads ?? []
  const restaurantRows = existingRestaurants ?? []
  const existingNames = new Set(restaurantRows.map((r) => (r.name ?? '').trim().toLowerCase()))

  const cuisineCounts = new Map<string, number>()
  for (const r of restaurantRows) {
    if (!r.cuisine_type) continue
    cuisineCounts.set(r.cuisine_type, (cuisineCounts.get(r.cuisine_type) ?? 0) + 1)
  }
  const maxCuisineCount = Math.max(1, ...Array.from(cuisineCounts.values()))

  const scored = leadRows.map((l) => {
    const nameKey = (l.name ?? '').trim().toLowerCase()
    const possibleDuplicate = existingNames.has(nameKey)

    let completeness = 0
    if (l.phone) completeness += 25
    if (l.email) completeness += 25
    if (l.address) completeness += 25
    if (l.cuisine_type) completeness += 25

    // Cuisine-gap bonus: fewer existing restaurants of this cuisine = more
    // valuable addition to the portfolio (real signal from real data).
    let cuisineGapScore = 0
    if (l.cuisine_type) {
      const existingCount = cuisineCounts.get(l.cuisine_type) ?? 0
      cuisineGapScore = round2((1 - existingCount / maxCuisineCount) * 100)
    }

    const score = possibleDuplicate ? 0 : round2(completeness * 0.6 + cuisineGapScore * 0.4)

    return {
      lead_id: l.id,
      name: l.name,
      cuisine_type: l.cuisine_type,
      contact_completeness_pct: completeness,
      cuisine_gap_score: cuisineGapScore,
      possible_duplicate_of_existing_restaurant: possibleDuplicate,
      score,
      days_since_added: Math.round((Date.now() - new Date(l.created_at).getTime()) / 86400000),
    }
  }).sort((a, b) => b.score - a.score)

  return {
    metrics: { new_lead_count: leadRows.length, duplicate_count: scored.filter((s) => s.possible_duplicate_of_existing_restaurant).length, leads: scored },
    relatedEntities: leadRows.map((l) => ({ type: 'restaurant_lead', id: l.id })),
    systemPrompt: `You are the 7Dash Restaurant Lead Generation Agent. Leads are entered manually by an admin — you never invent a restaurant. You're given each new lead's score (contact completeness + how underrepresented their cuisine is on the platform — a real gap signal) and whether they look like a duplicate of an existing partner (score forced to 0 if so). Write a short briefing (80-140 words) on which leads are worth prioritizing for outreach and why, and flag any duplicates for cleanup. If new_lead_count is 0, say there are no new leads to review. Plain text, no markdown.`,
  }
}

const REPORT_GENERATORS: Record<string, () => Promise<ReportResult>> = {
  live_order_ops: liveOrderOps,
  driver_compliance: driverCompliance,
  fraud_risk: fraudRisk,
  finance_reconciliation: financeReconciliation,
  payout_agent: payoutTriage,
  refund_resolution: refundResolution,
  customer_retention: customerRetention,
  restaurant_onboarding: restaurantOnboarding,
  driver_recruitment: driverRecruitment,
  marketing_strategy: marketingStrategy,
  market_expansion: marketExpansion,
  technical_operations: technicalOperationsAiHealth,
  restaurant_lead_gen: restaurantLeadGen,
}

// ── dispatch_optimization ────────────────────────────────────────────────
// Not a standalone report — needs a specific order. Ranking itself is
// deterministic (distance via haversine); the AI only explains the pick in
// plain language. This never assigns a driver — that stays with the
// existing assign-driver/select-driver functions; an admin still confirms.
async function dispatchOrders(): Promise<{ id: string; receipt_number: string; restaurant: string }[]> {
  const { data: orders } = await serviceClient
    .from('orders')
    .select('id, receipt_number, restaurant_id, restaurants(name)')
    .in('status', ['preparing', 'ready'])
    .is('driver_id', null)
    .eq('is_pickup', false)
  return (orders ?? []).map((o) => ({
    id: o.id,
    receipt_number: o.receipt_number,
    restaurant: (o.restaurants as { name?: string } | null)?.name ?? 'Unknown',
  }))
}

async function dispatchRankDrivers(orderId: string, admin: { id: string }): Promise<Response> {
  const { data: order, error: orderErr } = await serviceClient
    .from('orders')
    .select('id, receipt_number, restaurant_id, restaurants(name, latitude, longitude)')
    .eq('id', orderId)
    .single()
  if (orderErr || !order) return json({ error: 'Order not found' }, 404)

  const restaurant = order.restaurants as { name?: string; latitude?: number; longitude?: number } | null
  if (!restaurant?.latitude || !restaurant?.longitude) return json({ error: 'Restaurant has no location on file' }, 400)

  const { data: drivers } = await serviceClient
    .from('drivers')
    .select('id, full_name, current_lat, current_lng, vehicle_type')
    .eq('status', 'approved')
    .eq('is_online', true)
    .eq('is_available', true)
    .eq('is_available_for_food', true)
    .not('current_lat', 'is', null)
    .not('current_lng', 'is', null)

  const ranked = (drivers ?? [])
    .map((d) => ({
      driver: d.full_name ?? 'Unnamed',
      distance_km: round2(haversineKm(restaurant.latitude!, restaurant.longitude!, Number(d.current_lat), Number(d.current_lng))),
      vehicle_type: d.vehicle_type ?? 'unspecified',
    }))
    .sort((a, b) => a.distance_km - b.distance_km)

  let narrative = ''
  if (OPENAI_API_KEY && ranked.length > 0) {
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: `You are the 7Dash Dispatch Optimization Agent. You're given available drivers ranked by distance (already sorted, nearest first — this ranking is deterministic, not your judgment). Explain in 2-3 sentences why the top driver is the recommended pick, and note any other driver worth considering if the gap is close. An admin still confirms the assignment manually. Never invent a driver or distance not in the data. Plain text.` },
          { role: 'user', content: JSON.stringify({ order: order.receipt_number, restaurant: restaurant.name, ranked_drivers: ranked }) },
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
    agent_name: 'dispatch_optimization',
    entity_type: 'order',
    entity_id: orderId,
    related_entities: (drivers ?? []).map((d) => ({ type: 'driver', id: d.id })),
    input: { order_id: orderId },
    output: { ranked_drivers: ranked, narrative },
    model: 'gpt-4o-mini',
    status: 'completed',
    created_by: admin.id,
  })

  return json({ success: true, ranked_drivers: ranked, narrative })
}

// ── market_expansion (scoped to existing coverage, not new external markets) ──
// The original spec's version needs population/competitor/regulatory data
// this app has no access to. This honest, narrower version instead looks at
// whether EXISTING delivery zones are seeing demand pile up near their edge
// — a real signal for "widen this zone" — using only real order data.
async function marketExpansion(): Promise<ReportResult> {
  const { data: regions } = await serviceClient.from('delivery_regions').select('id, name, latitude, longitude, radius_km, is_active').eq('is_active', true)
  const ninetyDaysAgo = new Date(Date.now() - 90 * 86400000).toISOString()
  const { data: orders } = await serviceClient.from('orders').select('delivery_latitude, delivery_longitude, ordered_at').gte('ordered_at', ninetyDaysAgo)

  const rows = orders ?? []
  const analysis = (regions ?? []).map((r) => {
    let inZone = 0
    let nearEdge = 0 // within the outer 20% of the radius
    for (const o of rows) {
      if (!o.delivery_latitude || !o.delivery_longitude) continue
      const dist = haversineKm(r.latitude, r.longitude, o.delivery_latitude, o.delivery_longitude)
      if (dist <= r.radius_km) {
        inZone++
        if (dist >= r.radius_km * 0.8) nearEdge++
      }
    }
    return {
      zone: r.name,
      radius_km: r.radius_km,
      orders_last_90_days: inZone,
      pct_near_edge: inZone > 0 ? round2((nearEdge / inZone) * 100) : 0,
    }
  })

  return {
    metrics: { active_zone_count: (regions ?? []).length, zones: analysis },
    relatedEntities: [],
    systemPrompt: `You are the 7Dash Market Expansion Agent. Scope note: this app has no external population/competitor/regulatory data, so this analysis is limited to your EXISTING delivery zones only — not new external markets. You're given each zone's order volume and what percentage of orders land near the outer edge of its radius (a signal that widening the zone could capture nearby unmet demand). Write a short briefing (80-140 words) recommending which zone(s), if any, are worth widening, citing the actual percentages. Do not recommend launching in any city/market not already in the data — you have no basis for that. If no zone shows a notable edge pattern, say so. Plain text, no markdown.`,
  }
}

// ── technical_operations (scoped to AI agent health, not full app monitoring) ──
// The original spec's version needs an application error/incident tracking
// system (e.g. Sentry) this app doesn't have wired up. This honest, narrower
// version instead monitors the one thing this platform DOES track reliably:
// its own AI agent run failures, from the audit trail every agent already writes to.
async function technicalOperationsAiHealth(): Promise<ReportResult> {
  const sevenDaysAgo = new Date(Date.now() - 7 * 86400000).toISOString()
  const { data: runs } = await serviceClient
    .from('ai_agent_runs')
    .select('agent_name, status, error, created_at')
    .gte('created_at', sevenDaysAgo)

  const rows = runs ?? []
  const failuresByAgent = new Map<string, number>()
  const totalByAgent = new Map<string, number>()
  const recentFailures: Record<string, unknown>[] = []
  for (const r of rows) {
    totalByAgent.set(r.agent_name, (totalByAgent.get(r.agent_name) ?? 0) + 1)
    if (r.status === 'failed') {
      failuresByAgent.set(r.agent_name, (failuresByAgent.get(r.agent_name) ?? 0) + 1)
      recentFailures.push({ agent: r.agent_name, error: (r.error ?? '').slice(0, 200), when: r.created_at })
    }
  }

  const byAgent = Array.from(totalByAgent.entries()).map(([agent, total]) => ({
    agent,
    total_runs: total,
    failures: failuresByAgent.get(agent) ?? 0,
    failure_rate_pct: round2(((failuresByAgent.get(agent) ?? 0) / total) * 100),
  })).sort((a, b) => b.failure_rate_pct - a.failure_rate_pct)

  return {
    metrics: { total_runs_7d: rows.length, total_failures_7d: recentFailures.length, by_agent: byAgent, recent_failures: recentFailures.slice(0, 10) },
    relatedEntities: [],
    systemPrompt: `You are the 7Dash Technical Operations Agent. Scope note: this app has no application-wide error/incident tracking (no Sentry-equivalent), so this monitors the one thing reliably tracked — the AI agent platform's own run failures over the last 7 days. Write a short briefing (80-140 words) on which agent(s) are failing most and what the errors suggest, if a pattern is visible. If total_failures_7d is 0, say the AI agent platform is running cleanly. Never invent a failure or number not in the data. Plain text, no markdown.`,
  }
}

// ── marketing_content ──────────────────────────────────────────────────
// Not a report agent — generative. Given a brief, drafts content for the
// admin to review and use manually. No publish channel is wired up (no
// social/CMS integration exists), so this never posts anything itself.
async function generateMarketingContent(brief: string, admin: { id: string }): Promise<Response> {
  if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)
  if (!brief || !brief.trim()) return json({ error: 'BAD_REQUEST: brief required' }, 400)

  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are the 7Dash Marketing Content Agent. Given a brief, draft the requested marketing content (social post, promo copy, recruitment ad, etc.) for 7Dash — a food/grocery/ride delivery marketplace. Rules:
- Never invent a specific discount amount, promo code, or claim ("#1 rated", "fastest in town") unless the brief explicitly gives you that detail — leave a placeholder like [DISCOUNT]% instead.
- Keep tone upbeat and on-brand for a delivery app. Match length to the platform implied by the brief (short for social, longer for email).
- Output plain text ready to copy — no markdown formatting, no commentary about what you wrote.`,
        },
        { role: 'user', content: brief },
      ],
      temperature: 0.7,
    }),
  })
  if (!res.ok) {
    const errText = await res.text()
    return json({ error: 'AI content generation failed', details: errText }, 502)
  }
  const completion = await res.json()
  const content = completion.choices?.[0]?.message?.content ?? ''

  await serviceClient.from('ai_agent_runs').insert({
    agent_name: 'marketing_content',
    entity_type: 'content_draft',
    entity_id: crypto.randomUUID(),
    related_entities: [],
    input: { brief },
    output: { content },
    model: 'gpt-4o-mini',
    status: 'completed',
    created_by: admin.id,
  })

  return json({ success: true, content })
}

// ── restaurant_sales ──────────────────────────────────────────────────────
// Draft/approve pattern, same discipline as Support Agent: drafting never
// sends anything; only the approve step (after admin review/edit) emails
// the lead via Resend. Grounded in real 7Dash stats — never invents
// commission rates or numbers.
function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

async function salesDraftOutreach(leadId: string, admin: { id: string }): Promise<Response> {
  if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)

  const { data: lead, error: leadErr } = await serviceClient
    .from('restaurant_leads')
    .select('id, name, contact_name, email, cuisine_type, address, status')
    .eq('id', leadId)
    .single()
  if (leadErr || !lead) return json({ error: 'Lead not found' }, 404)
  if (!lead.email) return json({ error: 'Lead has no email on file — add one before drafting outreach.' }, 400)

  const [{ count: restaurantCount }, { data: settingsRow }] = await Promise.all([
    serviceClient.from('restaurants').select('id', { count: 'exact', head: true }).eq('status', 'approved'),
    serviceClient.from('app_config').select('value').eq('key', 'default_commission_rate').maybeSingle(),
  ])
  const commissionRate = settingsRow?.value ? Number(String(settingsRow.value).replace(/"/g, '')) : null

  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      messages: [
        {
          role: 'system',
          content: `You are the 7Dash Restaurant Sales drafting assistant. Draft a short, warm outreach email inviting this restaurant to join 7Dash as a delivery partner. Rules:
- Use ONLY the real platform stats given (restaurant count, commission rate) — if commission rate is null, don't state a specific number, say "competitive commission rates" instead.
- Never guarantee revenue, order volume, or specific results — those are promises we can't make.
- Reference their cuisine type / name naturally if given. 3-5 short paragraphs, end with a clear call to action (reply or call).
- Sign off as "The 7Dash Partnerships Team".
Respond ONLY with JSON: { "subject": string, "body": string }`,
        },
        { role: 'user', content: JSON.stringify({ lead, platform_restaurant_count: restaurantCount ?? 0, commission_rate: commissionRate }) },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.5,
    }),
  })
  if (!res.ok) {
    const errText = await res.text()
    return json({ error: 'AI drafting failed', details: errText }, 502)
  }
  const completion = await res.json()
  const parsed = JSON.parse(completion.choices?.[0]?.message?.content ?? '{}')
  const subject = String(parsed.subject ?? `Partner with 7Dash`).slice(0, 200)
  const body = String(parsed.body ?? '').slice(0, 4000)

  const { data: run, error: runErr } = await serviceClient
    .from('ai_agent_runs')
    .insert({
      agent_name: 'restaurant_sales',
      entity_type: 'restaurant_lead',
      entity_id: leadId,
      related_entities: [],
      input: { lead, platform_restaurant_count: restaurantCount ?? 0, commission_rate: commissionRate },
      output: { subject, body },
      model: 'gpt-4o-mini',
      status: 'completed',
      created_by: admin.id,
    })
    .select('id')
    .single()
  if (runErr) return json({ error: 'Failed to log agent run', details: runErr.message }, 500)

  const draftText = `Subject: ${subject}\n\n${body}`
  await serviceClient
    .from('restaurant_leads')
    .update({ ai_draft_outreach: draftText, ai_run_id: run.id, ai_status: 'drafted' })
    .eq('id', leadId)

  return json({ success: true, subject, body, run_id: run.id })
}

async function salesApproveOutreach(leadId: string, decision: string, finalSubject: string, finalBody: string, admin: { id: string }): Promise<Response> {
  if (!['approve', 'reject'].includes(decision)) return json({ error: 'BAD_REQUEST: decision must be approve or reject' }, 400)

  const { data: lead, error: leadErr } = await serviceClient.from('restaurant_leads').select('id, email, name, ai_status').eq('id', leadId).single()
  if (leadErr || !lead) return json({ error: 'Lead not found' }, 404)
  if (lead.ai_status === 'sent' || lead.ai_status === 'rejected') return json({ error: `Already ${lead.ai_status}` }, 409)

  if (decision === 'reject') {
    await serviceClient.from('restaurant_leads').update({ ai_status: 'rejected', reviewed_by: admin.id, reviewed_at: new Date().toISOString() }).eq('id', leadId)
    return json({ success: true, status: 'rejected' })
  }

  const subject = (finalSubject ?? '').trim() || 'Partner with 7Dash'
  const body = (finalBody ?? '').trim()
  if (!body) return json({ error: 'BAD_REQUEST: no message body to send' }, 400)

  let emailSent = false
  if (RESEND_API_KEY) {
    const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:24px;">
      <p style="white-space:pre-wrap;line-height:1.6;">${escapeHtml(body)}</p>
    </body></html>`
    const emailResp = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({ from: SALES_FROM_EMAIL, to: [lead.email], subject, html }),
    })
    emailSent = emailResp.ok
    if (!emailResp.ok) console.error('restaurant_sales: Resend send failed', await emailResp.text())
  }

  await serviceClient
    .from('restaurant_leads')
    .update({ ai_draft_outreach: `Subject: ${subject}\n\n${body}`, ai_status: 'sent', status: 'contacted', reviewed_by: admin.id, reviewed_at: new Date().toISOString() })
    .eq('id', leadId)

  await serviceClient.from('ai_agent_runs').insert({
    agent_name: 'restaurant_sales',
    entity_type: 'restaurant_lead',
    entity_id: leadId,
    related_entities: [],
    input: { decision: 'approve', subject, body },
    output: { email_sent: emailSent },
    status: 'completed',
    created_by: admin.id,
  })

  return json({ success: true, status: 'sent', email_sent: emailSent })
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { agent_slug, brief, order_id, list_orders, lead_id, decision, final_subject, final_body } = await req.json()

    if (agent_slug === 'restaurant_sales') {
      const { data: agentRow } = await serviceClient.from('ai_agents').select('status').eq('slug', agent_slug).maybeSingle()
      if (agentRow?.status === 'paused') return json({ error: 'restaurant_sales agent is paused.' }, 403)
      if (!lead_id) return json({ error: 'BAD_REQUEST: lead_id required' }, 400)
      if (decision) return await salesApproveOutreach(lead_id, decision, final_subject, final_body, admin)
      return await salesDraftOutreach(lead_id, admin)
    }

    if (agent_slug === 'marketing_content') {
      const { data: agentRow } = await serviceClient.from('ai_agents').select('status').eq('slug', agent_slug).maybeSingle()
      if (agentRow?.status === 'paused') return json({ error: 'marketing_content agent is paused.' }, 403)
      return await generateMarketingContent(brief, admin)
    }

    if (agent_slug === 'dispatch_optimization') {
      const { data: agentRow } = await serviceClient.from('ai_agents').select('status').eq('slug', agent_slug).maybeSingle()
      if (agentRow?.status === 'paused') return json({ error: 'dispatch_optimization agent is paused.' }, 403)
      if (list_orders) {
        const orders = await dispatchOrders()
        return json({ success: true, orders })
      }
      if (!order_id) return json({ error: 'BAD_REQUEST: order_id required' }, 400)
      return await dispatchRankDrivers(order_id, admin)
    }

    const generator = REPORT_GENERATORS[agent_slug]
    if (!generator) return json({ error: `BAD_REQUEST: unknown agent_slug '${agent_slug}'` }, 400)

    const { data: agentRow } = await serviceClient.from('ai_agents').select('status').eq('slug', agent_slug).maybeSingle()
    if (agentRow?.status === 'paused') return json({ error: `${agent_slug} agent is paused.` }, 403)

    const { metrics, relatedEntities, systemPrompt } = await generator()

    let narrative = ''
    if (OPENAI_API_KEY) {
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          messages: [
            { role: 'system', content: systemPrompt },
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
      agent_name: agent_slug,
      entity_type: 'report',
      entity_id: crypto.randomUUID(),
      related_entities: relatedEntities,
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

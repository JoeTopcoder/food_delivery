// ai-admin-briefing — Stage 5: one combined admin briefing per Jamaica day.
//
// Assembles the individual Stage-4 staff reports + the Stage-3 verified metrics
// into a single briefing:
//   * Verified company totals            (deterministic, straight from metrics)
//   * Top 5 operational issues           (LLM clusters duplicate findings)
//   * Top 3 suggested actions            (from ai_suggestions, linked back)
//   * Decisions requiring approval       (pending suggestions, linked back)
//   * Important day-over-day changes     (deterministic deltas, LLM narrates)
//   * Failed reports & missing data      (from report status + data_limitations)
//
// Integrity rules:
//   * The LLM never produces a number — company totals and deltas are computed
//     here from ai_staff_daily_metrics; the model only groups free-text findings
//     and writes prose. Every metric_reference it cites is validated against the
//     real snapshot and dropped if invented.
//   * Every recommendation links to a real ai_suggestions row (by id) and its
//     staff report; every issue records the source roles it was combined from.
//
// Urgent alerts: raised ONLY on clearly-defined, data-backed conditions (payment
// failures, orders stuck unassigned, etc.). Duplicate-safe — an existing open or
// acknowledged alert for the same condition/day is left untouched, preserving its
// acknowledgement status. Alerts are saved to ai_urgent_alerts (the admin panel);
// no external message is sent and no operational change is made automatically.
//
// Auth: admin JWT or service role. Deploy: supabase functions deploy ai-admin-briefing --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const RUNNER_SECRET = Deno.env.get('AUTOMATION_RUNNER_SECRET') ?? ''

function jamaicaToday(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Jamaica' }).format(new Date())
}
function prevDate(d: string): string {
  const dt = new Date(d + 'T12:00:00Z'); dt.setUTCDate(dt.getUTCDate() - 1)
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'UTC' }).format(dt)
}
function collectPaths(obj: unknown, prefix = ''): Set<string> {
  const p = new Set<string>()
  if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
      const path = prefix ? `${prefix}.${k}` : k
      p.add(path); for (const c of collectPaths(v, path)) p.add(c)
    }
  }
  return p
}
function num(metrics: Record<string, unknown>, path: string): number | null {
  let cur: unknown = metrics
  for (const k of path.split('.')) { if (cur && typeof cur === 'object') cur = (cur as Record<string, unknown>)[k]; else return null }
  return typeof cur === 'number' ? cur : null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    let tokenRole = ''
    try { tokenRole = String(JSON.parse(atob((token.split('.')[1] ?? '').replace(/-/g, '+').replace(/_/g, '/'))).role ?? '') } catch { /* */ }
    const isService = tokenRole === 'service_role'
      || (SERVICE_ROLE_KEY.length > 0 && token === SERVICE_ROLE_KEY)
      || (RUNNER_SECRET.length > 0 && token === RUNNER_SECRET)
    if (!isService) { try { await requireAdmin(req) } catch { return json({ error: 'FORBIDDEN' }, 403) } }
    if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)

    const body = await req.json().catch(() => ({}))
    const date: string = (body.report_date as string) || jamaicaToday()
    const yesterday = prevDate(date)

    // ── verified metrics (today + yesterday) ──
    const { data: metrics, error: mErr } = await serviceClient.rpc('ai_staff_daily_metrics', { p_date: date })
    if (mErr) return json({ error: 'metrics failed', details: mErr.message }, 500)
    const { data: metricsPrev } = await serviceClient.rpc('ai_staff_daily_metrics', { p_date: yesterday })
    const M = metrics as Record<string, unknown>
    const P = (metricsPrev ?? {}) as Record<string, unknown>
    const paths = collectPaths(M)

    // ── the run + reports + suggestions for the day ──
    const { data: run } = await serviceClient.from('ai_report_runs').select('id,status,total_roles,completed_roles,failed_roles').eq('report_date', date).maybeSingle()
    const { data: reports } = await serviceClient.from('ai_staff_reports')
      .select('id,role_id,status,summary,evidence,error, ai_staff_roles!inner(slug,title)').eq('report_date', date)
    const repList = (reports ?? []) as Array<Record<string, unknown>>
    const { data: suggestions } = await serviceClient.from('ai_suggestions')
      .select('id,role_id,title,description,rationale,priority,status, ai_staff_roles!inner(slug,title)').eq('report_date', date)
    const sugList = (suggestions ?? []) as Array<Record<string, unknown>>

    // ── deterministic verified totals + day-over-day deltas ──
    const totalKeys = [
      'orders.placed', 'orders.delivered', 'orders.cancelled', 'orders.cancellation_rate_pct',
      'finance.gmv', 'finance.contribution', 'finance.delivery_fee_revenue', 'finance.delivered_revenue',
      'finance.member_savings_cost', 'refunds.amount', 'membership.new_members', 'membership.active_members',
      'payments.failed', 'dispatch.orders_unassigned_active',
    ]
    const verified_totals: Record<string, unknown> = {}
    const deltas: Record<string, unknown> = {}
    for (const k of totalKeys) {
      const t = num(M, k); verified_totals[k] = t === null ? 'data_unavailable' : t
      const y = num(P, k)
      deltas[k] = (t === null || y === null) ? 'data_unavailable' : Math.round((t - y) * 100) / 100
    }

    // ── failures & missing data (deterministic) ──
    const failed_reports = repList.filter((r) => r.status === 'failed')
      .map((r) => ({ role: ((r.ai_staff_roles as Record<string, unknown>)?.slug), error: r.error }))
    const missing_data: string[] = []
    for (const r of repList) {
      const dl = (r.evidence as Record<string, unknown> | null)?.data_limitations
      if (typeof dl === 'string' && dl.trim()) missing_data.push(`${(r.ai_staff_roles as Record<string, unknown>)?.slug}: ${dl}`)
    }

    // ── gather findings (with source role) for LLM clustering ──
    const findings: Array<Record<string, unknown>> = []
    for (const r of repList) {
      const slug = (r.ai_staff_roles as Record<string, unknown>)?.slug
      const fs = (r.evidence as Record<string, unknown> | null)?.findings
      if (Array.isArray(fs)) for (const f of fs as Record<string, unknown>[]) {
        findings.push({ role: slug, text: f.text, refs: f.metric_references, severity: f.severity })
      }
    }
    // suggestions indexed for linking
    const sugIndex = sugList.map((s, i) => ({
      sid: i, id: s.id, role: (s.ai_staff_roles as Record<string, unknown>)?.slug,
      title: s.title, action: s.description, priority: s.priority,
    }))

    // ── LLM: cluster duplicate findings + pick top actions + narrate change ──
    const system = `You are HotBite's Chief of Staff writing ONE daily executive briefing from many AI staff reports.
RULES:
- Do NOT produce or alter any number. Use only the figures in "verified_totals"/"deltas"; when you cite one, put its dotted key in "metric_references".
- COMBINE duplicate findings: if several roles report the same underlying problem (e.g. late orders), merge them into ONE issue and list every role in "source_roles". Never list the same problem twice.
- For each recommended action, reference the real suggestion by its "sid" from the provided suggestions list.
- Be factual and hedged; never assert a cause as certain without evidence.
Respond ONLY with JSON:
{
 "headline": string,
 "executive_summary": string,
 "top_issues": [ { "title": string, "detail": string, "severity": "info"|"warning"|"high"|"critical", "source_roles": string[], "metric_references": string[] } ],   // max 5, most important first
 "top_actions": [ { "title": string, "why": string, "sid": number } ],   // max 3
 "notable_changes": string
}`
    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: JSON.stringify({ date, verified_totals, deltas, findings, suggestions: sugIndex }) },
        ],
        response_format: { type: 'json_object' }, temperature: 0.2,
      }),
    })
    if (!res.ok) return json({ error: 'AI briefing failed', details: (await res.text()).slice(0, 300) }, 502)
    const parsed = JSON.parse((await res.json()).choices?.[0]?.message?.content ?? '{}')

    const keepRefs = (refs: unknown): string[] => Array.isArray(refs) ? refs.filter((r) => typeof r === 'string' && paths.has(r)) : []

    // top issues — validate refs, cap at 5
    const top_issues = (Array.isArray(parsed.top_issues) ? parsed.top_issues as Record<string, unknown>[] : []).slice(0, 5).map((i) => ({
      title: String(i.title ?? '').slice(0, 300),
      detail: String(i.detail ?? '').slice(0, 1500),
      severity: ['info', 'warning', 'high', 'critical'].includes(String(i.severity)) ? i.severity : 'info',
      source_roles: Array.isArray(i.source_roles) ? i.source_roles.map(String) : [],
      metric_references: keepRefs(i.metric_references),
    }))
    // top actions — link back to real suggestion ids
    const top_actions = (Array.isArray(parsed.top_actions) ? parsed.top_actions as Record<string, unknown>[] : []).slice(0, 3).map((a) => {
      const src = sugIndex.find((s) => s.sid === Number(a.sid))
      return { title: String(a.title ?? src?.title ?? '').slice(0, 300), why: String(a.why ?? '').slice(0, 1000),
               suggestion_id: src?.id ?? null, role: src?.role ?? null, priority: src?.priority ?? null }
    })
    // decisions requiring approval — every pending suggestion, linked
    const approvals = sugList.filter((s) => s.status === 'pending').map((s) => ({
      suggestion_id: s.id, role: (s.ai_staff_roles as Record<string, unknown>)?.slug,
      title: s.title, priority: s.priority,
    }))

    // ── deterministic urgent-alert conditions (data-backed) ──
    const cap = (num(M, 'payments.captured') ?? 0), pend = (num(M, 'payments.pending') ?? 0), fail = (num(M, 'payments.failed') ?? 0)
    const payTotal = cap + pend + fail
    const conditions = [
      { key: 'payment_failures', title: 'Widespread payment failures', severity: 'critical',
        metric: 'payments.failed', value: fail,
        triggered: fail >= 5 || (payTotal >= 10 && fail / Math.max(payTotal, 1) >= 0.2),
        message: `${fail} payment(s) failed today${payTotal ? ` of ${payTotal} attempted` : ''}.` },
      { key: 'orders_unassigned', title: 'Orders stuck without a rider', severity: 'high',
        metric: 'dispatch.orders_unassigned_active', value: (num(M, 'dispatch.orders_unassigned_active') ?? 0),
        triggered: (num(M, 'dispatch.orders_unassigned_active') ?? 0) >= 5,
        message: `${num(M, 'dispatch.orders_unassigned_active') ?? 0} active order(s) have no rider assigned.` },
      { key: 'high_cancellation', title: 'High order cancellation rate', severity: 'high',
        metric: 'orders.cancellation_rate_pct', value: (num(M, 'orders.cancellation_rate_pct') ?? 0),
        triggered: (num(M, 'orders.placed') ?? 0) >= 10 && (num(M, 'orders.cancellation_rate_pct') ?? 0) >= 25,
        message: `Cancellation rate is ${num(M, 'orders.cancellation_rate_pct') ?? 0}% today.` },
      { key: 'agent_failures', title: 'Multiple AI staff reports failed', severity: 'high',
        metric: 'reliability.failed_agent_runs', value: failed_reports.length,
        triggered: failed_reports.length >= 3,
        message: `${failed_reports.length} AI staff report(s) failed to generate today.` },
    ]
    let urgentCreated = 0, urgentExisting = 0
    for (const c of conditions.filter((x) => x.triggered)) {
      // Duplicate-safe: skip if an open/acknowledged alert for this condition/day
      // already exists (preserves acknowledgement); otherwise create it.
      const { data: existing } = await serviceClient.from('ai_urgent_alerts')
        .select('id,status').eq('report_date', date).is('role_id', null).eq('title', c.title)
        .in('status', ['open', 'acknowledged']).maybeSingle()
      if (existing) { urgentExisting++; continue }
      await serviceClient.from('ai_urgent_alerts').insert({
        role_id: null, report_id: null, report_date: date, severity: c.severity,
        title: c.title, message: c.message, evidence: { references: [c.metric], value: c.value }, status: 'open',
      })
      urgentCreated++
    }
    const { count: urgentCount } = await serviceClient.from('ai_urgent_alerts')
      .select('id', { count: 'exact', head: true }).eq('report_date', date)

    // ── persist the briefing (one per day, upsert) ──
    const highlights = {
      top_issues, top_actions, approvals, notable_changes: String(parsed.notable_changes ?? ''),
      failures: { failed_reports, missing_data },
      alert_conditions: conditions.map((c) => ({ key: c.key, metric: c.metric, value: c.value, triggered: c.triggered })),
    }
    const { data: brief, error: bErr } = await serviceClient.from('ai_admin_briefings').upsert({
      run_id: (run?.id as string) ?? null, briefing_date: date,
      headline: String(parsed.headline ?? `HotBite daily briefing — ${date}`).slice(0, 300),
      summary: String(parsed.executive_summary ?? '').slice(0, 6000),
      highlights, metrics: { verified_totals, deltas },
      roles_reported: repList.filter((r) => r.status === 'completed').length,
      suggestions_count: sugList.length, urgent_count: urgentCount ?? 0,
      delivery_channel: 'admin_panel', delivered_at: new Date().toISOString(),
    }, { onConflict: 'briefing_date' }).select('id').single()
    if (bErr) return json({ error: 'briefing save failed', details: bErr.message }, 500)

    return json({
      success: true, briefing_id: brief.id, briefing_date: date,
      roles_reported: repList.length, suggestions: sugList.length,
      issues: top_issues.length, actions: top_actions.length, approvals: approvals.length,
      urgent_created: urgentCreated, urgent_existing: urgentExisting, urgent_total: urgentCount ?? 0,
    })
  } catch (e) {
    return json({ error: 'ai-admin-briefing failed', details: String((e as Error).message ?? e) }, 500)
  }
})

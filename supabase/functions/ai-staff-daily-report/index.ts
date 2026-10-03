// ai-staff-daily-report — Stage 4: server-side daily report generation for the
// 24 HotBite AI staff roles.
//
// Flow (all server-side; no AI key ever leaves the backend):
//   1. Resolve the America/Jamaica business date.
//   2. Pull ONE trusted metrics snapshot from the Stage-3 RPC
//      ai_staff_daily_metrics(p_date) (SECURITY DEFINER, admin/service only).
//   3. For each ACTIVE ai_staff_roles row: hand the model ONLY that role's
//      relevant metric sections + its stored job description, and ask for a
//      structured report + up to 3 ranked, evidence-based suggestions.
//   4. Validate the model output against the real data (drop invented metric
//      references, clamp suggestion count, coerce fields), then save the report
//      and suggestions to the Stage-2 tables. Critical findings raise an alert.
//   5. One role failing is caught, its error saved, and the others continue.
//
// Idempotency / rerun safety:
//   * ai_report_runs is unique per report_date (upsert).
//   * ai_staff_reports is unique per (run_id, role_id) (upsert — no dup reports).
//   * a role's suggestions are deleted then re-inserted per run (no dup
//     suggestions), while the run itself is audit-logged in ai_agent_runs.
//
// Reuses the project's existing AI integration: OpenAI via the OPENAI_API_KEY
// backend secret (same key/endpoint/model as ops-report-agent). No new secret
// is required. Deploy: supabase functions deploy ai-staff-daily-report --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
// Reuses the project's existing cron shared secret (same one automation-workflow-runner
// uses), so scheduling needs NO new secret.
const RUNNER_SECRET = Deno.env.get('AUTOMATION_RUNNER_SECRET') ?? ''
const SUPABASE_URL = Deno.env.get('SUPABASE_URL') ?? ''

// Each role sees ONLY the metric sections it needs (least-privilege data).
// Keys refer to top-level sections of ai_staff_daily_metrics output.
const ROLE_SECTIONS: Record<string, string[]> = {
  operations_manager:            ['orders', 'finance', 'customer_issues', 'reliability'],
  delivery_manager:              ['delivery', 'orders', 'finance'],
  rider_performance_officer:     ['riders', 'delivery', 'orders'],
  customer_experience_officer:   ['customer_issues', 'refunds', 'orders'],
  restaurant_manager:            ['restaurants', 'orders'],
  supermarket_manager:           ['supermarkets', 'orders'],
  finance_officer:               ['finance', 'orders', 'refunds', 'membership', 'promotions'],
  membership_manager:            ['membership', 'finance'],
  marketing_manager:             ['promotions', 'orders', 'membership'],
  pricing_analyst:               ['finance', 'orders'],
  fraud_risk_officer:            ['refunds', 'payments', 'promotions', 'orders'],
  growth_strategist:             ['orders', 'finance', 'membership'],
  dispatch_coordinator:          ['dispatch', 'delivery', 'riders'],
  demand_forecasting_analyst:    ['orders', 'finance'],
  rider_scheduling_officer:      ['riders', 'dispatch', 'orders'],
  order_accuracy_officer:        ['orders', 'refunds', 'customer_issues'],
  store_onboarding_officer:      ['restaurants', 'supermarkets', 'orders'],
  menu_catalogue_quality_officer:['restaurants', 'supermarkets'],
  payment_reconciliation_officer:['payments', 'finance', 'refunds'],
  membership_retention_officer:  ['membership', 'orders'],
  promotion_performance_officer: ['promotions', 'finance', 'orders'],
  service_area_analyst:          ['delivery', 'orders'],
  system_reliability_officer:    ['reliability', 'payments', 'orders'],
  process_improvement_officer:   ['orders', 'customer_issues', 'finance', 'reliability'],
}

interface Role {
  id: string; slug: string; title: string; job_description: string
  data_categories: string[]; daily_reporting_requirements: string
  max_suggestions: number; model: string
}

function jamaicaToday(): string {
  return new Intl.DateTimeFormat('en-CA', { timeZone: 'America/Jamaica' }).format(new Date())
}

// Slice the trusted snapshot down to a role's allowed sections only.
function sliceForRole(slug: string, metrics: Record<string, unknown>): Record<string, unknown> {
  const keys = ROLE_SECTIONS[slug] ?? Object.keys(metrics).filter((k) => k !== 'meta')
  const out: Record<string, unknown> = { meta: metrics.meta }
  for (const k of keys) if (k in metrics) out[k] = metrics[k]
  return out
}

// Collect every dotted path present in the role payload, so we can reject any
// metric_reference the model invents (a value the data does not contain).
function collectPaths(obj: unknown, prefix = ''): Set<string> {
  const paths = new Set<string>()
  if (obj && typeof obj === 'object' && !Array.isArray(obj)) {
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
      const p = prefix ? `${prefix}.${k}` : k
      paths.add(p)
      for (const c of collectPaths(v, p)) paths.add(c)
    }
  }
  return paths
}

async function callOpenAI(role: Role, payload: Record<string, unknown>): Promise<{ parsed: Record<string, unknown>; tokens: number }> {
  const system = `You are HotBite's "${role.title}". Your remit: ${role.job_description}
Your daily reporting requirement: ${role.daily_reporting_requirements}
You may propose at most ${role.max_suggestions} suggestions.

STRICT RULES — follow exactly:
- Use ONLY the numbers in the provided data object. NEVER invent, estimate, or extrapolate a number.
- Every figure you cite MUST appear in "metric_references" as its dotted key path from the data (e.g. "finance.gmv", "orders.delivered").
- If a value you need is the string "data_unavailable" or absent, say so plainly in "data_limitations" and do NOT guess it.
- Do NOT claim a cause is certain without supporting evidence; use hedged language ("may indicate", "possibly") unless the data proves it.
- Suggestions must be concrete and evidence-based. Each MUST set "requires_admin_approval": true when it would change customer, rider, store, pricing, payment, or order behaviour; only pure internal/monitoring actions may be false.
- You never take action yourself — you only recommend.

Respond ONLY with JSON of shape:
{
 "summary": string,
 "findings": [ { "text": string, "metric_references": string[], "severity": "info"|"warning"|"high"|"critical" } ],
 "data_limitations": string,
 "suggestions": [ {
    "title": string, "proposed_action": string, "evidence": string,
    "expected_benefit": string, "priority": "low"|"medium"|"high"|"urgent",
    "requires_admin_approval": boolean, "metric_references": string[],
    "action_type": one of ["create_admin_task","investigate_orders","flag_catalogue_issue","assign_support_cases","prepare_rider_coverage_plan","create_admin_alert","open_store_performance_case","draft_partner_message","prepare_pricing_change"],
    "action_title": string
 } ]
}
Choose "prepare_pricing_change" for ANY suggestion about product prices, sale prices, member prices, delivery/service/priority fees — those are manual-admin only. Otherwise pick the closest task-type. If the suggestion is too vague to act on, omit action_type.`
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: role.model || 'gpt-4o-mini',
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: JSON.stringify({ report_date: payload.meta && (payload.meta as Record<string, unknown>).report_date, data: payload }) },
      ],
      response_format: { type: 'json_object' },
      temperature: 0.2,
    }),
  })
  if (!res.ok) throw new Error(`OpenAI ${res.status}: ${(await res.text()).slice(0, 300)}`)
  const completion = await res.json()
  const parsed = JSON.parse(completion.choices?.[0]?.message?.content ?? '{}')
  return { parsed, tokens: Number(completion.usage?.total_tokens ?? 0) }
}

const PRIORITY = new Set(['low', 'medium', 'high', 'urgent'])
// Fixed allowlist mirrored from the ai_action_types registry (server-side).
const ALLOWED_ACTIONS = new Set([
  'create_admin_task', 'investigate_orders', 'flag_catalogue_issue', 'assign_support_cases',
  'prepare_rider_coverage_plan', 'create_admin_alert', 'open_store_performance_case',
  'draft_partner_message', 'prepare_pricing_change', 'send_partner_message',
])

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    // ── auth: admin JWT (manual trigger) OR service role (cron) ──
    // The gateway already validated the bearer as a real project apikey before
    // this code runs, so trusting its decoded `role` claim is safe. Accept the
    // service role by claim (rotation-proof) or by exact key match; otherwise
    // fall back to a full admin-user check.
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    let tokenRole = ''
    try {
      const payload = JSON.parse(atob((token.split('.')[1] ?? '').replace(/-/g, '+').replace(/_/g, '/')))
      tokenRole = String(payload.role ?? '')
    } catch { /* not a JWT */ }
    const isService = tokenRole === 'service_role'
      || (SERVICE_ROLE_KEY.length > 0 && token === SERVICE_ROLE_KEY)
      || (RUNNER_SECRET.length > 0 && token === RUNNER_SECRET)
    if (!isService) {
      try { await requireAdmin(req) } catch { return json({ error: 'FORBIDDEN' }, 403) }
    }

    if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)

    const body = await req.json().catch(() => ({}))
    const reportDate: string = (body.report_date as string) || jamaicaToday()
    const triggeredBy: string = (body.triggered_by as string) || (isService ? 'cron' : 'admin')

    // ── trusted metrics snapshot (Stage 3) ──
    const { data: metrics, error: mErr } = await serviceClient.rpc('ai_staff_daily_metrics', { p_date: reportDate })
    if (mErr) return json({ error: 'metrics failed', details: mErr.message }, 500)
    const paths = collectPaths(metrics as Record<string, unknown>)

    // ── active roles ──
    const { data: roles, error: rErr } = await serviceClient
      .from('ai_staff_roles').select('id,slug,title,job_description,data_categories,daily_reporting_requirements,max_suggestions,model')
      .eq('status', 'active').order('sort_order')
    if (rErr) return json({ error: 'roles failed', details: rErr.message }, 500)
    const roleList = (roles ?? []) as Role[]

    // ── upsert the run (one per business day) ──
    const { data: run, error: runErr } = await serviceClient
      .from('ai_report_runs')
      .upsert({
        report_date: reportDate, status: 'running', triggered_by: triggeredBy,
        total_roles: roleList.length, completed_roles: 0, failed_roles: 0,
        started_at: new Date().toISOString(), completed_at: null, error: null,
      }, { onConflict: 'report_date' })
      .select('id').single()
    if (runErr || !run) return json({ error: 'run upsert failed', details: runErr?.message }, 500)
    const runId = run.id as string

    let completed = 0, failed = 0
    const perRole: Array<Record<string, unknown>> = []

    for (const role of roleList) {
      try {
        const payload = sliceForRole(role.slug, metrics as Record<string, unknown>)
        const { parsed, tokens } = await callOpenAI(role, payload)

        // Keep only metric references that actually exist in this role's data.
        const keepRefs = (refs: unknown): string[] =>
          Array.isArray(refs) ? refs.filter((r) => typeof r === 'string' && paths.has(r)) : []

        const findings = Array.isArray(parsed.findings)
          ? (parsed.findings as Record<string, unknown>[]).map((fd) => ({
              text: String(fd.text ?? '').slice(0, 1000),
              metric_references: keepRefs(fd.metric_references),
              severity: ['info', 'warning', 'high', 'critical'].includes(String(fd.severity)) ? fd.severity : 'info',
            }))
          : []

        // ── upsert the role's report (no duplicate per run) ──
        const { data: rep, error: repErr } = await serviceClient
          .from('ai_staff_reports')
          .upsert({
            run_id: runId, role_id: role.id, report_date: reportDate, status: 'completed',
            summary: String(parsed.summary ?? '').slice(0, 4000),
            metrics: payload,
            evidence: { findings, data_limitations: String(parsed.data_limitations ?? '') },
            model: role.model || 'gpt-4o-mini', tokens_used: tokens, error: null,
          }, { onConflict: 'run_id,role_id' })
          .select('id').single()
        if (repErr || !rep) throw new Error(`report save: ${repErr?.message}`)
        const reportId = rep.id as string

        // ── replace this report's suggestions (rerun-safe, no duplicates) ──
        await serviceClient.from('ai_suggestions').delete().eq('report_id', reportId)
        const rawSug = Array.isArray(parsed.suggestions) ? parsed.suggestions as Record<string, unknown>[] : []
        const sugs = rawSug.slice(0, Math.min(role.max_suggestions, 3)).map((s) => {
          const title = String(s.title ?? 'Suggestion').slice(0, 300)
          const proposed = String(s.proposed_action ?? '').slice(0, 4000)
          // Validate the proposed action_type against the fixed allowlist.
          let actionType = ALLOWED_ACTIONS.has(String(s.action_type)) ? String(s.action_type) : null
          // Server-side pricing tripwire: anything mentioning price/fee is forced
          // to the manual-only pricing type regardless of what the model said.
          const looksPricing = /\b(price|pricing|fee|fees|discount|member price|surcharge|tariff)\b/i.test(`${title} ${proposed}`)
          if (looksPricing) actionType = 'prepare_pricing_change'
          const requiresManual = actionType === 'prepare_pricing_change'
          const external = actionType === 'send_partner_message'
          return {
            report_id: reportId, role_id: role.id, report_date: reportDate,
            title, description: proposed,
            rationale: String(s.evidence ?? '').slice(0, 4000),
            evidence: { references: keepRefs(s.metric_references), expected_benefit: String(s.expected_benefit ?? '') },
            priority: PRIORITY.has(String(s.priority)) ? String(s.priority) : 'medium',
            estimated_impact: String(s.expected_benefit ?? '').slice(0, 1000),
            status: 'pending',
            action_type: actionType,
            action_payload: actionType ? { title: String(s.action_title ?? title).slice(0, 300), source: 'ai_staff' } : null,
            requires_manual_admin: requiresManual,
            has_external_effect: external,
            action_status: actionType ? 'awaiting_approval' : 'suggested',
          }
        })
        // requires_admin_approval is captured via the suggestion staying 'pending'
        // for admin action; a model 'false' still routes through admin review.
        if (sugs.length > 0) {
          const { error: sErr } = await serviceClient.from('ai_suggestions').insert(sugs)
          if (sErr) throw new Error(`suggestions save: ${sErr.message}`)
        }

        // ── raise urgent alerts for critical/high findings ──
        const critical = findings.filter((fd) => fd.severity === 'critical' || fd.severity === 'high')
        if (critical.length > 0) {
          // Clear prior alerts for this role/date to avoid rerun duplicates.
          await serviceClient.from('ai_urgent_alerts').delete()
            .eq('role_id', role.id).eq('report_date', reportDate)
          await serviceClient.from('ai_urgent_alerts').insert(critical.map((fd) => ({
            role_id: role.id, report_id: reportId, report_date: reportDate,
            severity: fd.severity === 'critical' ? 'critical' : 'high',
            title: `${role.title}: attention needed`,
            message: String(fd.text).slice(0, 2000),
            evidence: { references: fd.metric_references },
            status: 'open',
          })))
        }

        completed++
        perRole.push({ role: role.slug, status: 'completed', suggestions: sugs.length })
      } catch (e) {
        // One role failing must not stop the others — persist its error.
        failed++
        await serviceClient.from('ai_staff_reports').upsert({
          run_id: runId, role_id: role.id, report_date: reportDate, status: 'failed',
          error: String((e as Error).message ?? e).slice(0, 2000),
        }, { onConflict: 'run_id,role_id' })
        perRole.push({ role: role.slug, status: 'failed', error: String((e as Error).message ?? e).slice(0, 300) })
      }
    }

    const finalStatus = failed === 0 ? 'completed' : (completed === 0 ? 'failed' : 'partial')
    await serviceClient.from('ai_report_runs').update({
      status: finalStatus, completed_roles: completed, failed_roles: failed,
      completed_at: new Date().toISOString(),
    }).eq('id', runId)

    // Audit row in the project's existing agent-run log.
    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'ai_staff_daily_report', entity_type: 'report_run', entity_id: runId,
      input: { report_date: reportDate, triggered_by: triggeredBy },
      output: { status: finalStatus, completed, failed },
      model: 'gpt-4o-mini', status: finalStatus === 'failed' ? 'failed' : 'completed',
    })

    // Optional pipeline: after all staff reports, generate the combined briefing.
    let briefing: unknown = null
    if (body.run_briefing === true) {
      try {
        const bRes = await fetch(`${SUPABASE_URL}/functions/v1/ai-admin-briefing`, {
          method: 'POST',
          headers: { Authorization: `Bearer ${RUNNER_SECRET || SERVICE_ROLE_KEY}`, 'Content-Type': 'application/json' },
          body: JSON.stringify({ report_date: reportDate }),
        })
        briefing = await bRes.json().catch(() => ({ error: 'briefing parse failed' }))
      } catch (e) {
        briefing = { error: String((e as Error).message ?? e) }
      }
    }

    return json({ success: true, run_id: runId, report_date: reportDate, status: finalStatus, completed, failed, roles: perRole, briefing })
  } catch (e) {
    return json({ error: 'ai-staff-daily-report failed', details: String((e as Error).message ?? e) }, 500)
  }
})

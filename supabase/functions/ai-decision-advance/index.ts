// ai-decision-advance — runs ONE workflow stage of an AI Decision, then returns.
// The client calls this repeatedly (showing progress) until completed/failed.
// Durable: each stage's state lives in ai_decision_stages, so it survives restarts
// and supports retry/cancel. Advisory only — never mutates business data.
//
// Auth: admin + ai_decision_room_allowed + must own the decision (RLS). Provider
// keys stay server-side; mock mode runs when a key is absent.
// Deploy: supabase functions deploy ai-decision-advance
// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h:(r:Request)=>Response|Promise<Response>):void }
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8"
import { callProvider, parseJson } from "../_shared/ai_providers.ts"

const URL = Deno.env.get("SUPABASE_URL") ?? ""
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
const admin = createClient(URL, SERVICE)
const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" }
const json = (b: Record<string, unknown>, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } })

function decisionBrief(d: Record<string, unknown>): string {
  const parts = [
    `QUESTION: ${d.question}`,
    d.context ? `CONTEXT: ${d.context}` : '',
    (d.options && (d.options as unknown[]).length) ? `OPTIONS: ${JSON.stringify(d.options)}` : '',
    d.goals ? `GOALS: ${d.goals}` : '',
    d.budget ? `BUDGET: ${d.budget}` : '',
    d.constraints ? `CONSTRAINTS: ${d.constraints}` : '',
    d.category ? `CATEGORY: ${d.category}` : '',
    d.metrics_snapshot ? `BUSINESS METRICS (aggregate data, analyze only): ${JSON.stringify(d.metrics_snapshot)}` : '',
  ]
  return parts.filter(Boolean).join('\n')
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  const authHeader = req.headers.get("Authorization") ?? ""
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401)
  const asUser = createClient(URL, ANON, { global: { headers: { Authorization: authHeader } } })

  let body: Record<string, unknown>
  try { body = await req.json() } catch { return json({ error: "invalid_json" }, 400) }
  const decisionId = body.decision_id as string
  if (!decisionId) return json({ error: "decision_id required" }, 400)

  // Authorize: allowed AND can see this decision (RLS on the user client).
  const { data: allowed } = await asUser.rpc("ai_decision_room_allowed")
  if (allowed !== true) return json({ ok: false, reason: "not_authorized" }, 403)
  const { data: decRow, error: decErr } = await asUser
    .from("ai_decisions").select("*").eq("id", decisionId).maybeSingle()
  if (decErr || !decRow) return json({ ok: false, reason: "not_found" }, 404)
  if (["completed", "cancelled"].includes(decRow.status))
    return json({ ok: true, decision_status: decRow.status, done: true })

  // Compute metrics snapshot once (aggregate, PII-safe) if requested.
  let dec = decRow as Record<string, unknown>
  if (dec.include_metrics && !dec.metrics_snapshot) {
    const { data: mp } = await asUser.rpc("ai_decision_metrics_preview", { p_days: 30 })
    if (mp?.ok) {
      await admin.from("ai_decisions").update({ metrics_snapshot: mp }).eq("id", decisionId)
      dec = { ...dec, metrics_snapshot: mp }
    }
  }

  // Next pending stage by seq.
  const { data: stages } = await admin.from("ai_decision_stages")
    .select("*").eq("decision_id", decisionId).order("seq")
  const total = stages?.length ?? 5
  const next = (stages ?? []).find((s: Record<string, unknown>) => s.status === "pending")
  if (!next) {
    return json({ ok: true, decision_status: dec.status, done: dec.status === "completed", progress: { done: total, total } })
  }
  const stageName = next.stage as string
  const provider = next.provider as string
  const outputs: Record<string, unknown> = {}
  for (const s of stages ?? []) if (s.status === "done" && s.output) outputs[s.stage as string] = s.output

  // Decision status transition for UX.
  const statusForStage = stageName.includes("assess") ? "assessing"
    : stageName.includes("review") ? "cross_review" : "synthesizing"
  await admin.from("ai_decisions").update({ status: statusForStage, updated_at: new Date().toISOString() }).eq("id", decisionId)
  await admin.from("ai_decision_stages").update({ status: "running", started_at: new Date().toISOString() }).eq("id", next.id)

  // Build the stage prompt.
  const brief = decisionBrief(dec)
  let system = "", user = ""
  if (stageName === "openai_assess" || stageName === "claude_assess") {
    system = 'Independently assess the decision. JSON keys: summary, key_factors (array), risks (array), assumptions (array), recommendation (string), confidence (low|medium|high).'
    user = brief
  } else if (stageName === "openai_review") {
    system = 'Critically review the OTHER assistant\'s assessment vs your own view. JSON keys: agreements (array), disagreements (array), critique (string), missed_points (array).'
    user = `${brief}\n\nOTHER ASSISTANT (Claude) ASSESSMENT:\n${JSON.stringify(outputs["claude_assess"] ?? {})}`
  } else if (stageName === "claude_review") {
    system = 'Critically review the OTHER assistant\'s assessment vs your own view. JSON keys: agreements (array), disagreements (array), critique (string), missed_points (array).'
    user = `${brief}\n\nOTHER ASSISTANT (OpenAI) ASSESSMENT:\n${JSON.stringify(outputs["openai_assess"] ?? {})}`
  } else { // synthesis
    system = 'Synthesize a FINAL recommendation from both assessments and both cross-reviews. JSON keys: recommendation (string), agreements (array), disagreements (array), assumptions (array), facts_to_verify (array), next_actions (array of EXACTLY 3 strings), confidence (low|medium|high).'
    user = `${brief}\n\nOPENAI ASSESS:\n${JSON.stringify(outputs["openai_assess"] ?? {})}\n\nCLAUDE ASSESS:\n${JSON.stringify(outputs["claude_assess"] ?? {})}\n\nOPENAI REVIEW:\n${JSON.stringify(outputs["openai_review"] ?? {})}\n\nCLAUDE REVIEW:\n${JSON.stringify(outputs["claude_review"] ?? {})}`
  }

  const res = await callProvider(provider, system, user)
  const parsed = res.ok ? parseJson(res.text) : null
  if (!res.ok || !parsed) {
    await admin.from("ai_decision_stages").update({
      status: "failed", error: (res.error ?? "invalid_model_json").slice(0, 300), finished_at: new Date().toISOString(),
    }).eq("id", next.id)
    await admin.from("ai_decisions").update({ status: "failed", updated_at: new Date().toISOString() }).eq("id", decisionId)
    return json({ ok: false, stage: stageName, stage_status: "failed", reason: "stage_failed" }, 502)
  }

  await admin.from("ai_decision_stages").update({
    status: "done", output: parsed, tokens_in: res.tokensIn ?? null, tokens_out: res.tokensOut ?? null,
    finished_at: new Date().toISOString(),
  }).eq("id", next.id)

  // Synthesis finishes the decision — validate exactly 3 next actions.
  if (stageName === "synthesis") {
    let acts = Array.isArray(parsed.next_actions) ? parsed.next_actions as string[] : []
    acts = acts.map(String).filter(Boolean).slice(0, 3)
    while (acts.length < 3) acts.push("(no further action proposed)")
    const result = { ...parsed, next_actions: acts, mock: res.mock }
    await admin.from("ai_decisions").update({
      result, status: "completed", completed_at: new Date().toISOString(), updated_at: new Date().toISOString(),
    }).eq("id", decisionId)
    return json({ ok: true, decision_status: "completed", done: true, mock: res.mock, progress: { done: total, total } })
  }

  const doneCount = (stages ?? []).filter((s: Record<string, unknown>) => s.status === "done").length + 1
  return json({ ok: true, stage: stageName, stage_status: "done", mock: res.mock,
    decision_status: statusForStage, progress: { done: doneCount, total } })
})

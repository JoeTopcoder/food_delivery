// call-fallback-request — authenticated driver endpoint to start a private phone
// bridge when the Agora in-app call cannot connect/recover.
//
// Driver submits ONLY { order_id, call_session_id, reason }. Never a phone number.
// Authorization + eligibility + limits are enforced in request_call_fallback (RPC,
// runs as the driver via their JWT). Phone numbers are resolved + dialed here with
// service role and NEVER returned to the driver.
//
// Deploy: supabase functions deploy call-fallback-request
// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h:(r:Request)=>Response|Promise<Response>):void }
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8"
import { getProvider, getCallerId } from "../_shared/telephony.ts"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? ""
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const ANON_KEY     = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
const admin = createClient(SUPABASE_URL, SERVICE_KEY)

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
}
const json = (b: Record<string, unknown>, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } })

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })

  const authHeader = req.headers.get("Authorization") ?? ""
  if (!authHeader.startsWith("Bearer ")) return json({ error: "unauthorized" }, 401)

  let body: Record<string, unknown>
  try { body = await req.json() } catch { return json({ error: "invalid_json" }, 400) }

  const orderId = body.order_id as string
  const callId  = (body.call_session_id ?? body.call_id) as string
  const reason  = (body.reason as string) ?? "connect_timeout"
  if (!orderId) return json({ error: "order_id required" }, 400)
  // Defensive: reject any attempt to pass a destination number from the client.
  for (const k of Object.keys(body)) {
    if (/phone|msisdn|number|dial|to_/i.test(k)) return json({ error: "phone_not_accepted" }, 400)
  }

  // 1. Authorize + create session AS THE DRIVER (auth.uid() from their JWT).
  const asUser = createClient(SUPABASE_URL, ANON_KEY, { global: { headers: { Authorization: authHeader } } })
  const { data: reqRes, error: reqErr } = await asUser.rpc("request_call_fallback", {
    p_order_id: orderId, p_call_id: callId ?? null, p_reason: reason,
  })
  if (reqErr) return json({ error: "request_failed", detail: reqErr.message }, 400)
  const r = reqRes as Record<string, unknown>
  if (!r?.ok) return json({ ok: false, reason: r?.reason ?? "denied" }, 403)
  const fallbackId = r.fallback_id as string

  // Already bridging from a prior request — return safe status, do not re-dial.
  if (r.deduped) {
    const { data: st } = await asUser.rpc("get_call_fallback_status", { p_fallback_id: fallbackId })
    return json({ ok: true, fallback_id: fallbackId, deduped: true, status: st })
  }

  // 2. Resolve phones with SERVICE role (never exposed to the driver).
  const { data: ph, error: phErr } = await admin.rpc("cf_resolve_phones", { p_fallback_id: fallbackId })
  if (phErr || !ph?.ok) {
    await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: "requested",
      p_new_status: "failed", p_failure_code: (ph?.reason as string) ?? "resolve_failed" })
    return json({ ok: false, reason: "unavailable" }, 409)  // sanitized — no phone detail
  }

  // 3. Start the driver leg via the provider (Twilio or mock).
  const provider = getProvider()
  const voiceUrl = `${SUPABASE_URL}/functions/v1/call-fallback-voice?fallback_id=${fallbackId}&leg=driver`
  const statusUrl = `${SUPABASE_URL}/functions/v1/call-fallback-voice?fallback_id=${fallbackId}&leg=status`
  const leg = await provider.startDriverLeg({
    fallbackId, driverPhone: ph.driver_phone as string, callerId: getCallerId(),
    voiceWebhookUrl: voiceUrl, statusCallbackUrl: statusUrl,
  })
  if (!leg.ok) {
    await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: "requested",
      p_new_status: "failed", p_failure_code: "provider_start_failed" })
    return json({ ok: false, reason: "unavailable" }, 502)
  }

  await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: "requested",
    p_new_status: "dialing_driver", p_driver_sid: leg.sid })

  // Mock mode advances to awaiting-press so UI states can be exercised, but is
  // clearly flagged as mock — never presented as a real connected call.
  if (provider.isMock) {
    await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: "dialing_driver",
      p_new_status: "awaiting_driver_press" })
  }

  const { data: safe } = await asUser.rpc("get_call_fallback_status", { p_fallback_id: fallbackId })
  return json({ ok: true, fallback_id: fallbackId, mock: provider.isMock, status: safe })
})

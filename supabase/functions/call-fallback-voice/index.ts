// call-fallback-voice — Twilio Programmable Voice webhook for the private bridge.
//
// Driver leg answered  -> <Gather> "HotBite is connecting your customer call.
//                          Press 1 to continue." (prevents voicemail auto-dial)
// Driver presses 1     -> resolve customer number (service role) and <Dial> it
//                          with the HotBite caller ID (customer never sees driver #)
// Status callbacks     -> update the fallback session state.
//
// Signature-verified. verify_jwt=false (Twilio can't send a Supabase JWT).
// Deploy: supabase functions deploy call-fallback-voice --no-verify-jwt
// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h:(r:Request)=>Response|Promise<Response>):void }
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8"
import { verifyTwilioSignature, getCallerId, getTwilioAuthToken } from "../_shared/telephony.ts"

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? ""
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const admin = createClient(SUPABASE_URL, SERVICE_KEY)

const xml = (twiml: string) =>
  new Response(`<?xml version="1.0" encoding="UTF-8"?><Response>${twiml}</Response>`,
    { status: 200, headers: { "Content-Type": "text/xml" } })
const esc = (s: string) => s.replace(/&/g,"&amp;").replace(/</g,"&lt;").replace(/>/g,"&gt;")

Deno.serve(async (req: Request) => {
  const url = new URL(req.url)
  const fallbackId = url.searchParams.get("fallback_id") ?? ""
  const leg = url.searchParams.get("leg") ?? "driver"
  const step = url.searchParams.get("step") ?? ""

  // Parse form body (Twilio posts application/x-www-form-urlencoded)
  const form = new URLSearchParams(await req.text())
  const params: Record<string,string> = {}
  for (const [k,v] of form) params[k] = v

  // Verify Twilio signature against the FULL request URL + params.
  const token = getTwilioAuthToken()
  const sig = req.headers.get("X-Twilio-Signature") ?? ""
  if (token) {
    const ok = await verifyTwilioSignature(token, req.url, params, sig)
    if (!ok) return new Response("forbidden", { status: 403 })
  }
  if (!fallbackId) return xml(`<Hangup/>`)

  // ── Status callback leg ────────────────────────────────────────────────────
  if (leg === "status") {
    const callStatus = params["CallStatus"] ?? ""
    const map: Record<string,string> = {
      "completed": "completed", "no-answer": "no_answer", "busy": "no_answer",
      "failed": "failed", "canceled": "cancelled",
    }
    const newStatus = map[callStatus]
    if (newStatus) {
      await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: null,
        p_new_status: newStatus, p_failure_code: newStatus === "failed" ? "provider_failed" : null })
    }
    return new Response("ok", { status: 200 })
  }

  // ── Driver leg: ask for press-1 (prevents dialing customer into voicemail) ──
  if (leg === "driver" && step !== "gather") {
    const action = `${SUPABASE_URL}/functions/v1/call-fallback-voice?fallback_id=${fallbackId}&leg=driver&step=gather`
    return xml(
      `<Gather numDigits="1" timeout="10" action="${esc(action)}" method="POST">` +
      `<Say voice="alice">HotBite is connecting your customer call. Press 1 to continue.</Say>` +
      `</Gather><Say voice="alice">No input received. Goodbye.</Say><Hangup/>`)
  }

  // ── Driver pressed a key: only "1" proceeds to dial the customer ───────────
  if (leg === "driver" && step === "gather") {
    if ((params["Digits"] ?? "") !== "1") {
      await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: null,
        p_new_status: "cancelled", p_failure_code: "driver_no_press" })
      return xml(`<Say voice="alice">Cancelled.</Say><Hangup/>`)
    }
    // Re-authorize + resolve the customer number server-side, right before dialing.
    const { data: ph } = await admin.rpc("cf_resolve_phones", { p_fallback_id: fallbackId })
    if (!ph?.ok) {
      await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: null,
        p_new_status: "failed", p_failure_code: "unauthorized_at_dial" })
      return xml(`<Say voice="alice">This call is no longer available. Goodbye.</Say><Hangup/>`)
    }
    await admin.rpc("cf_set_status", { p_fallback_id: fallbackId, p_expected_status: "awaiting_driver_press",
      p_new_status: "dialing_customer" })
    // Dial the customer with the HotBite caller ID explicitly — the driver's
    // number is NOT forwarded. On bridge, mark bridged via dial action callback.
    const dialStatus = `${SUPABASE_URL}/functions/v1/call-fallback-voice?fallback_id=${fallbackId}&leg=status`
    return xml(
      `<Say voice="alice">Connecting you now.</Say>` +
      `<Dial callerId="${esc(getCallerId())}" record="do-not-record" answerOnBridge="true" ` +
      `action="${esc(dialStatus)}" method="POST">` +
      `<Number>${esc(ph.customer_phone as string)}</Number></Dial>`)
  }

  return xml(`<Hangup/>`)
})

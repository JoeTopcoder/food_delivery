// staff-invite — authenticated owner/manager invites staff by email.
// Creates the invitation via SECURITY DEFINER RPC (authorization + hashing +
// rate-limit enforced server-side), then emails the single-use link via Resend.
// The raw token never touches a client-readable row and is not returned to the
// caller. Deploy: supabase functions deploy staff-invite
// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h:(r:Request)=>Response|Promise<Response>):void }
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8"
import { sendEmail } from "../_shared/resend.ts"

const URL = Deno.env.get("SUPABASE_URL") ?? ""
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
const APP_BASE = Deno.env.get("APP_BASE_URL") ?? "https://hotbite.app"
const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type" }
const json = (b: Record<string,unknown>, s=200) => new Response(JSON.stringify(b), { status:s, headers:{...cors,"Content-Type":"application/json"} })

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  const authHeader = req.headers.get("Authorization") ?? ""
  if (!authHeader.startsWith("Bearer ")) return json({ error:"unauthorized" }, 401)
  let body: Record<string,unknown>
  try { body = await req.json() } catch { return json({ error:"invalid_json" }, 400) }
  const restaurantId = body.restaurant_id as string
  const email = (body.email as string ?? "").trim()
  const role = body.role as string
  if (!restaurantId || !email || !role) return json({ error:"restaurant_id, email, role required" }, 400)

  // Create the invitation AS the caller (RPC enforces authority/rate-limit/hash).
  const asUser = createClient(URL, ANON, { global: { headers: { Authorization: authHeader } } })
  const { data, error } = await asUser.rpc("staff_invite_create", {
    p_restaurant: restaurantId, p_email: email, p_role: role,
  })
  if (error) return json({ error:"invite_failed", detail:error.message }, 400)
  const r = data as Record<string, unknown>
  if (!r?.ok) return json({ ok:false, reason: r?.reason ?? "denied" }, 403)

  const token = r.token as string
  const link = `${APP_BASE}/accept-staff-invite?token=${encodeURIComponent(token)}`
  const html = `<!doctype html><div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#1e293b">
    <h2 style="margin:0 0 8px">You're invited to join a HotBite restaurant</h2>
    <p>You've been invited as a <b>${role === 'manager' ? 'Manager' : 'Cashier'}</b>.</p>
    <p>If you already have a HotBite account, sign in with <b>${email}</b> and accept. New here? Create your account with this email, verify it, then accept.</p>
    <p style="margin:20px 0"><a href="${link}" style="background:#2563eb;color:#fff;text-decoration:none;padding:12px 20px;border-radius:10px;font-weight:700">Accept invitation</a></p>
    <p style="font-size:12px;color:#64748b">This invitation expires in 72 hours and can be used once. If the button doesn't work, open the HotBite app → Accept staff invite, and paste this code:<br><code style="font-size:11px;word-break:break-all">${token}</code></p>
  </div>`

  // Resend requires a verified FROM domain — handled by _shared/resend.ts.
  const res = await sendEmail({ to: email, subject: "Your HotBite staff invitation", html })
  if (!res.ok) {
    // Invitation exists; email delivery is the blocker — report it honestly.
    return json({ ok:true, emailed:false, reason:"email_delivery_failed", detail:res.error }, 200)
  }
  return json({ ok:true, emailed:true, invitation_id: r.invitation_id })
})

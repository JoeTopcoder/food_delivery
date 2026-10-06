// staff-password-reset — an owner/manager triggers a standard password-reset
// email for one of their staff, WITHOUT ever viewing or setting the password.
// Authorization is verified server-side; the recovery link is generated with the
// service role and emailed via Resend. Deploy: supabase functions deploy staff-password-reset
// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h:(r:Request)=>Response|Promise<Response>):void }
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8"
import { sendEmail } from "../_shared/resend.ts"

const URL = Deno.env.get("SUPABASE_URL") ?? ""
const ANON = Deno.env.get("SUPABASE_ANON_KEY") ?? ""
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
const APP_BASE = Deno.env.get("APP_BASE_URL") ?? "https://hotbite.app"
const admin = createClient(URL, SERVICE)
const cors = { "Access-Control-Allow-Origin":"*", "Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type" }
const json = (b: Record<string,unknown>, s=200) => new Response(JSON.stringify(b), { status:s, headers:{...cors,"Content-Type":"application/json"} })

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors })
  const authHeader = req.headers.get("Authorization") ?? ""
  if (!authHeader.startsWith("Bearer ")) return json({ error:"unauthorized" }, 401)
  let body: Record<string,unknown>
  try { body = await req.json() } catch { return json({ error:"invalid_json" }, 400) }
  const restaurantId = body.restaurant_id as string
  const targetUser = body.user_id as string
  if (!restaurantId || !targetUser) return json({ error:"restaurant_id, user_id required" }, 400)

  // Caller must be able to manage staff at this restaurant, and the target must
  // be a member there (checked against the membership via the user's own RLS).
  const asUser = createClient(URL, ANON, { global: { headers: { Authorization: authHeader } } })
  const { data: canManage } = await asUser.rpc("can_manage_restaurant_staff", { p_restaurant: restaurantId })
  if (canManage !== true) return json({ ok:false, reason:"not_authorized" }, 403)
  const { data: member } = await asUser.from("restaurant_staff").select("user_id")
    .eq("restaurant_id", restaurantId).eq("user_id", targetUser).maybeSingle()
  if (!member) return json({ ok:false, reason:"not_a_member" }, 404)

  // Look up the target's email (service role) and generate a recovery link.
  const { data: tu } = await admin.from("users").select("email").eq("id", targetUser).maybeSingle()
  const email = tu?.email as string | undefined
  if (!email) return json({ ok:false, reason:"no_email" }, 404)

  const { data: linkData, error: linkErr } = await admin.auth.admin.generateLink({
    type: "recovery", email,
    options: { redirectTo: `${APP_BASE}/reset-password` },
  })
  if (linkErr) return json({ ok:false, reason:"link_failed", detail:linkErr.message }, 502)
  const actionLink = (linkData?.properties as { action_link?: string } | undefined)?.action_link
  if (!actionLink) return json({ ok:false, reason:"no_link" }, 502)

  const html = `<!doctype html><div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#1e293b">
    <h2 style="margin:0 0 8px">Reset your HotBite password</h2>
    <p>A manager at your restaurant requested a password reset for your account.</p>
    <p style="margin:20px 0"><a href="${actionLink}" style="background:#2563eb;color:#fff;text-decoration:none;padding:12px 20px;border-radius:10px;font-weight:700">Set a new password</a></p>
    <p style="font-size:12px;color:#64748b">If you didn't expect this, you can ignore this email — your password won't change until you set a new one.</p>
  </div>`
  const res = await sendEmail({ to: email, subject: "Reset your HotBite password", html })
  if (!res.ok) return json({ ok:true, emailed:false, reason:"email_delivery_failed", detail:res.error }, 200)
  return json({ ok:true, emailed:true })
})

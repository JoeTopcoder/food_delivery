// admin-recovery-code — email-delivered 2FA recovery codes for admins.
//
// Two actions (POST { action }):
//   "request" → generate a 6-digit code, store it hashed, email it to the
//               admin's account email. Only works for role='admin' callers.
//   "verify"  → check a submitted code against the stored hash; if it matches an
//               unexpired, unused code, mark it used and return ok:true.
//
// Codes are stored HASHED (sha256 of pepper+code), expire in 10 minutes, and
// are single-use. The pepper (ADMIN_RECOVERY_PEPPER secret) keeps a DB leak from
// being brute-forceable offline. Everything runs with the service role; the
// admin_mfa_recovery_codes table is not reachable by clients directly.
//
// Deploy: supabase functions deploy admin-recovery-code
// Secrets: RESEND_API_KEY (existing), ADMIN_RECOVERY_PEPPER (set a long random)

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };
// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { sendEmail } from "../_shared/resend.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const pepper = Deno.env.get("ADMIN_RECOVERY_PEPPER") ?? "hotbite-admin-recovery";
const admin = createClient(supabaseUrl, serviceKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

async function hashCode(code: string): Promise<string> {
  const data = new TextEncoder().encode(`${pepper}:${code}`);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function sixDigit(): string {
  // Cryptographically random 000000–999999.
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
}

function maskEmail(email: string): string {
  const [name, domain] = email.split("@");
  if (!domain) return email;
  const shown = name.length <= 2 ? name[0] ?? "" : name.slice(0, 2);
  return `${shown}${"*".repeat(Math.max(1, name.length - shown.length))}@${domain}`;
}

function codeEmailHtml(code: string): string {
  return `<!doctype html><html><body style="margin:0;padding:0;background:#F6F4FF;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
<div style="max-width:520px;margin:32px auto;background:#fff;border-radius:14px;padding:28px">
  <h1 style="margin:0 0 8px;color:#1a1a1a;font-size:20px">Your HotBite admin sign-in code</h1>
  <p style="margin:0 0 20px;color:#555;font-size:14px;line-height:1.5">Use this code to finish signing in to the admin console. It expires in 10 minutes and can be used once.</p>
  <div style="text-align:center;margin:8px 0 20px">
    <div style="display:inline-block;padding:16px 30px;border-radius:12px;background:#111827;color:#fff;font-weight:800;font-size:30px;letter-spacing:8px">${code}</div>
  </div>
  <p style="margin:0;color:#999;font-size:12px;line-height:1.5">Didn't request this? Someone may have your password — sign in and change it, and check your two-step verification settings.</p>
</div></body></html>`;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const action = String(body.action ?? "");

  // ── Authenticate + require admin ───────────────────────────────────────────
  const authHeader = request.headers.get("Authorization") ?? "";
  const token = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7) : "";
  if (!token) return json({ error: "Not signed in." }, 401);
  const { data: authUser, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !authUser?.user) return json({ error: "Session expired. Sign in again." }, 401);
  const userId = authUser.user.id;
  const email = authUser.user.email ?? "";

  const { data: profile } = await admin.from("users").select("role").eq("id", userId).maybeSingle();
  if (profile?.role !== "admin") return json({ error: "Admins only." }, 403);

  if (action === "request") {
    if (!email) return json({ error: "No email on file for this account." }, 400);

    // Simple rate limit: no more than one code every 30s per admin.
    const { data: recent } = await admin
      .from("admin_mfa_recovery_codes")
      .select("created_at")
      .eq("user_id", userId)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (recent?.created_at && Date.now() - new Date(recent.created_at).getTime() < 30_000) {
      return json({ error: "Please wait a moment before requesting another code." }, 429);
    }

    // Invalidate any outstanding unused codes, then issue a fresh one.
    await admin.from("admin_mfa_recovery_codes").delete().eq("user_id", userId).is("used_at", null);
    const code = sixDigit();
    const codeHash = await hashCode(code);
    const expiresAt = new Date(Date.now() + 10 * 60_000).toISOString();
    const { error: insErr } = await admin.from("admin_mfa_recovery_codes")
      .insert({ user_id: userId, code_hash: codeHash, expires_at: expiresAt });
    if (insErr) return json({ error: "Could not create a code. Try again." }, 500);

    const sent = await sendEmail({
      to: email,
      subject: "Your HotBite admin sign-in code",
      html: codeEmailHtml(code),
    });
    if (!sent.ok) return json({ error: "Could not send the email. Try again." }, 502);
    return json({ ok: true, sent_to: maskEmail(email) });
  }

  if (action === "verify") {
    const code = String(body.code ?? "").trim();
    if (!/^\d{6}$/.test(code)) return json({ ok: false, error: "Enter the 6-digit code." }, 400);
    const codeHash = await hashCode(code);
    const { data: row } = await admin
      .from("admin_mfa_recovery_codes")
      .select("id")
      .eq("user_id", userId)
      .eq("code_hash", codeHash)
      .is("used_at", null)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!row) return json({ ok: false, error: "That code is wrong or expired." }, 200);
    await admin.from("admin_mfa_recovery_codes").update({ used_at: new Date().toISOString() }).eq("id", row.id);
    return json({ ok: true });
  }

  return json({ error: "Unknown action." }, 400);
});

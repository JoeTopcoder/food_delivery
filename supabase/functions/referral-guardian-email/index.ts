// referral-guardian-email — emails admins the daily Membership Referral verdict
// (referral wallet payouts vs paying-member revenue). Triggered by the DB
// guardian (referral_guardian_daily) which posts the month-to-date metrics.
// Auth: service-role JWT or AUTOMATION_RUNNER_SECRET.

// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h: (r: Request) => Response | Promise<Response>): void };
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { sendEmail } from "../_shared/resend.ts";

const admin = createClient(Deno.env.get("SUPABASE_URL") ?? "", Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "");
const RUNNER = Deno.env.get("AUTOMATION_RUNNER_SECRET") ?? "";
const SERVICE = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, content-type" };
const json = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

function jwtRole(t: string): string | null {
  try { return JSON.parse(atob(t.split(".")[1].replace(/-/g, "+").replace(/_/g, "/"))).role ?? null; } catch { return null; }
}
function authed(req: Request): boolean {
  const h = req.headers.get("Authorization") ?? "";
  const t = h.startsWith("Bearer ") ? h.slice(7) : "";
  return (!!RUNNER && t === RUNNER) || (!!SERVICE && t === SERVICE) || jwtRole(t) === "service_role";
}
const money = (c: number) => `$${(Number(c || 0) / 100).toFixed(2)}`;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!authed(req)) return json({ error: "UNAUTHORIZED" }, 401);
  const b = await req.json().catch(() => ({}));

  const verdict = (b.verdict as string) ?? "OK";
  const rev = Number(b.membership_revenue_cents) || 0;
  const paid = Number(b.referral_paid_cents) || 0;
  const pending = Number(b.referral_pending_cents) || 0;
  const net = Number(b.net_cents) || 0;
  const members = Number(b.paying_members) || 0;

  // Recipients: all admins (unless overridden).
  let recipients: string[] = Array.isArray(b.to) ? b.to : (b.to ? [b.to] : []);
  if (recipients.length === 0) {
    const { data } = await admin.from("users").select("email").eq("role", "admin");
    recipients = (data ?? []).map((r: { email: string }) => r.email).filter(Boolean);
  }
  if (recipients.length === 0) return json({ ok: false, error: "no_admin_recipients" }, 200);

  const color = verdict === "ALERT" ? "#dc2626" : verdict === "WATCH" ? "#ea580c" : "#16a34a";
  const html = `
    <div style="font-family:Arial,sans-serif;max-width:560px;margin:0 auto">
      <h2 style="margin:0 0 4px">Membership Referral — <span style="color:${color}">${verdict}</span></h2>
      <p style="color:#6b7280;margin:0 0 16px">Referral wallet payouts vs paying-member revenue (month to date)</p>
      <div style="background:${color};color:#fff;padding:16px;border-radius:12px">
        <div style="font-size:13px;opacity:.85">Net contribution</div>
        <div style="font-size:26px;font-weight:800">${money(net)}</div>
        <div style="font-size:12px;opacity:.85">${money(rev)} membership revenue − ${money(paid + pending)} referral payouts</div>
      </div>
      <table style="width:100%;margin-top:16px;border-collapse:collapse;font-size:14px">
        <tr><td style="padding:6px 0;color:#6b7280">Paying members</td><td style="text-align:right;font-weight:600">${members}</td></tr>
        <tr><td style="padding:6px 0;color:#6b7280">Membership revenue</td><td style="text-align:right;font-weight:600">${money(rev)}</td></tr>
        <tr><td style="padding:6px 0;color:#6b7280">Referral paid to wallet</td><td style="text-align:right;font-weight:600">${money(paid)}</td></tr>
        <tr><td style="padding:6px 0;color:#6b7280">Referral pending</td><td style="text-align:right;font-weight:600">${money(pending)}</td></tr>
      </table>
      ${verdict === "ALERT" ? `<p style="color:#dc2626;font-weight:600;margin-top:12px">⚠ Referral payouts are exceeding what paying members contribute. Review the programme.</p>` : ""}
      <p style="color:#9ca3af;font-size:12px;margin-top:16px">HotBite Referral Economics Guardian · automated daily update</p>
    </div>`;

  const r = await sendEmail({ to: recipients, subject: `HotBite Membership Referral — ${verdict}`, html });
  return json({ ok: r.ok, id: r.id, error: r.error, recipients: recipients.length });
});

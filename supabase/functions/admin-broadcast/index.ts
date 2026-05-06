// admin-broadcast — Sends a push notification + email to a set of customers.
// Built for admins to push out promo announcements ("$5 off today!", etc.) via
// both FCM push and Resend email in a single call. Reuses the same FCM
// service-account flow as `send-promotion`.
//
// Auth: caller must present a JWT belonging to a user with role='admin'
//       in public.users. We verify that with the service-role admin client.
//
// Body: {
//   title:     string,           // push title (also email subject if no subject)
//   message:   string,           // push body / email plain-text body
//   subject?:  string,           // optional email subject override
//   html?:     string,           // optional pre-rendered email HTML
//   promo_code?: string,         // optional promo code to highlight
//   target:    'all' | 'active' | 'inactive' | 'segment' | 'user_ids',
//   segment?:  'new_user' | 'casual' | 'regular' | 'power_user',
//   user_ids?: string[],
//   send_push?: boolean,         // default true
//   send_email?: boolean         // default true
// }
//
// Returns { recipients, push_sent, email_sent, errors }

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, serviceRoleKey);

const RESEND_API_KEY = Deno.env.get("RESEND_API_KEY") ?? "";
const FROM_EMAIL =
  Deno.env.get("BROADCAST_FROM_EMAIL") ??
  Deno.env.get("RECEIPT_FROM_EMAIL") ??
  "MealHub <onboarding@resend.dev>";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};
const json = (b: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(b), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

// ── FCM auth (mirror of send-promotion) ─────────────────────────────────────
async function getAccessToken(): Promise<string> {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY_BASE64") ?? "";
  if (!raw) throw new Error("FCM_SERVICE_ACCOUNT_KEY_BASE64 not set");
  const sa = JSON.parse(atob(raw));
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600;

  // @ts-ignore deno
  const { encode: b64url } = await import(
    "https://deno.land/std@0.224.0/encoding/base64url.ts"
  );
  // @ts-ignore deno
  const { crypto } = globalThis;

  const header = b64url(
    new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })),
  );
  const payload = b64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat,
        exp,
      }),
    ),
  );
  const sigInput = new TextEncoder().encode(`${header}.${payload}`);
  const pemBody = sa.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");
  const binaryKey = Uint8Array.from(atob(pemBody), (c: string) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = b64url(
    new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, sigInput)),
  );
  const jwt = `${header}.${payload}.${sig}`;
  const tr = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tj = await tr.json();
  if (!tj.access_token) throw new Error("OAuth: " + JSON.stringify(tj));
  return tj.access_token as string;
}

async function sendFcm(
  accessToken: string,
  projectId: string,
  fcmToken: string,
  title: string,
  body: string,
  data: Record<string, string>,
): Promise<boolean> {
  try {
    const r = await fetch(
      `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: { title, body },
            data,
            android: {
              priority: "high",
              notification: {
                channel_id: "food_driver_promos",
                sound: "default",
              },
            },
          },
        }),
      },
    );
    return r.ok;
  } catch {
    return false;
  }
}

async function sendEmail(
  to: string,
  subject: string,
  html: string,
): Promise<boolean> {
  if (!RESEND_API_KEY) return false;
  try {
    const r = await fetch("https://api.resend.com/emails", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ from: FROM_EMAIL, to, subject, html }),
    });
    return r.ok;
  } catch {
    return false;
  }
}

function escapeHtml(s: string) {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function defaultHtml(
  title: string,
  message: string,
  promoCode: string | null,
): string {
  const code = promoCode
    ? `<div style="margin:24px 0;text-align:center"><div style="display:inline-block;padding:14px 26px;border-radius:12px;background:#7B61FF;color:#fff;font-weight:700;font-size:22px;letter-spacing:1px">${escapeHtml(
        promoCode,
      )}</div><p style="margin:8px 0 0;color:#666;font-size:13px">Use this code at checkout</p></div>`
    : "";
  return `<!doctype html><html><body style="margin:0;padding:0;background:#F6F4FF;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif">
<div style="max-width:560px;margin:0 auto;background:#fff;border-radius:14px;padding:28px;margin-top:32px">
  <h1 style="margin:0 0 12px;color:#1a1a1a;font-size:22px">${escapeHtml(title)}</h1>
  <p style="margin:0;color:#444;line-height:1.55;font-size:15px;white-space:pre-line">${escapeHtml(
    message,
  )}</p>
  ${code}
  <hr style="border:none;border-top:1px solid #eee;margin:24px 0">
  <p style="margin:0;color:#999;font-size:12px">Sent by 7DASH. You can manage notifications in your account settings.</p>
</div></body></html>`;
}

interface Body {
  title: string;
  message: string;
  subject?: string;
  html?: string;
  promo_code?: string;
  target?: "all" | "active" | "inactive" | "segment" | "user_ids";
  segment?: string;
  user_ids?: string[];
  send_push?: boolean;
  send_email?: boolean;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  // ── AuthZ: require an admin caller ────────────────────────────────────────
  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace(/^Bearer\s+/i, "");
  if (!token) return json({ error: "Missing bearer token" }, 401);
  const { data: userData, error: userErr } = await admin.auth.getUser(token);
  if (userErr || !userData?.user) return json({ error: "Invalid token" }, 401);
  const callerId = userData.user.id;
  const { data: caller, error: cErr } = await admin
    .from("users")
    .select("role")
    .eq("id", callerId)
    .maybeSingle();
  if (cErr) return json({ error: "Failed to verify caller", details: cErr.message }, 500);
  if (!caller || caller.role !== "admin") {
    return json({ error: "Admin role required" }, 403);
  }

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  const title = (body.title ?? "").trim();
  const message = (body.message ?? "").trim();
  if (!title || !message) return json({ error: "title and message are required" }, 400);

  const target = body.target ?? "all";
  const sendPush = body.send_push !== false;
  const sendEmail2 = body.send_email !== false;

  // ── Resolve recipients ────────────────────────────────────────────────────
  let userIds: string[] = [];
  if (target === "user_ids" && Array.isArray(body.user_ids)) {
    userIds = body.user_ids;
  } else if (target === "active") {
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const { data } = await admin
      .from("orders")
      .select("user_id")
      .gte("created_at", since);
    userIds = Array.from(new Set((data ?? []).map((o: { user_id: string }) => o.user_id))).filter(
      Boolean,
    );
  } else if (target === "inactive") {
    const since = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString();
    const [{ data: allUsers }, { data: recent }] = await Promise.all([
      admin.from("users").select("id").eq("role", "user"),
      admin.from("orders").select("user_id").gte("created_at", since),
    ]);
    const recentSet = new Set((recent ?? []).map((o: { user_id: string }) => o.user_id));
    userIds = (allUsers ?? [])
      .map((u: { id: string }) => u.id)
      .filter((id: string) => !recentSet.has(id));
  } else if (target === "segment" && body.segment) {
    const { data } = await admin
      .from("user_intelligence_profiles")
      .select("user_id")
      .eq("user_segment", body.segment);
    userIds = (data ?? []).map((p: { user_id: string }) => p.user_id);
  } else {
    // 'all' customers
    const { data } = await admin
      .from("users")
      .select("id")
      .eq("role", "user");
    userIds = (data ?? []).map((u: { id: string }) => u.id);
  }

  if (userIds.length === 0) {
    return json({ recipients: 0, push_sent: 0, email_sent: 0, errors: [] });
  }

  // ── Pull tokens + emails in one shot ─────────────────────────────────────
  const { data: profiles, error: pErr } = await admin
    .from("users")
    .select("id, email, fcm_token")
    .in("id", userIds);
  if (pErr) return json({ error: "Failed to load profiles", details: pErr.message }, 500);

  // ── Push leg ─────────────────────────────────────────────────────────────
  let pushSent = 0;
  const errors: string[] = [];
  if (sendPush) {
    try {
      const accessToken = await getAccessToken();
      const projectId = JSON.parse(
        atob(Deno.env.get("FCM_SERVICE_ACCOUNT_KEY_BASE64") ?? ""),
      ).project_id;
      const data: Record<string, string> = { type: "admin_broadcast" };
      if (body.promo_code) data.promo_code = body.promo_code;
      for (const p of profiles ?? []) {
        const tok = (p as { fcm_token?: string | null }).fcm_token;
        if (!tok) continue;
        if (await sendFcm(accessToken, projectId, tok, title, message, data)) pushSent++;
      }
    } catch (e) {
      errors.push(`push: ${String(e)}`);
    }
  }

  // ── Email leg ────────────────────────────────────────────────────────────
  let emailSent = 0;
  if (sendEmail2) {
    if (!RESEND_API_KEY) {
      errors.push("email: RESEND_API_KEY not configured");
    } else {
      const subject = body.subject?.trim() || title;
      const html = body.html?.trim() || defaultHtml(title, message, body.promo_code ?? null);
      for (const p of profiles ?? []) {
        const e = (p as { email?: string | null }).email;
        if (!e) continue;
        if (await sendEmail(e, subject, html)) emailSent++;
      }
    }
  }

  // ── Audit row in scheduled_promotions for history ────────────────────────
  try {
    await admin.from("scheduled_promotions").insert({
      title,
      body: message,
      target_audience: target,
      sent: true,
      send_at: new Date().toISOString(),
      created_by: callerId,
    });
  } catch (_) {
    /* table optional */
  }

  return json({
    recipients: userIds.length,
    profiles_with_push: (profiles ?? []).filter((p: { fcm_token?: string | null }) => p.fcm_token)
      .length,
    profiles_with_email: (profiles ?? []).filter((p: { email?: string | null }) => p.email).length,
    push_sent: pushSent,
    email_sent: emailSent,
    errors,
  });
});

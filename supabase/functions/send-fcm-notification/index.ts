// send-fcm-notification — Sends push notifications via Firebase Cloud Messaging V1 API
// Uses service account credentials stored as a Supabase secret (base64-encoded)

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// ── Google OAuth2 token generation ──────────────────────────────────────────

function base64UrlEncode(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

async function getAccessToken(
  serviceAccount: {
    client_email: string;
    private_key: string;
    token_uri: string;
  }
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: serviceAccount.token_uri,
    iat: now,
    exp: now + 3600,
  };

  const enc = new TextEncoder();
  const headerB64 = base64UrlEncode(enc.encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(enc.encode(JSON.stringify(payload)));
  const unsignedJwt = `${headerB64}.${payloadB64}`;

  // Import private key
  const pemBody = serviceAccount.private_key
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\n/g, "");
  const binaryKey = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    binaryKey,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = new Uint8Array(
    await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, enc.encode(unsignedJwt))
  );
  const jwt = `${unsignedJwt}.${base64UrlEncode(signature)}`;

  // Exchange JWT for access token
  const tokenRes = await fetch(serviceAccount.token_uri, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!tokenRes.ok) {
    const err = await tokenRes.text();
    throw new Error(`Token exchange failed: ${err}`);
  }

  const { access_token } = await tokenRes.json();
  return access_token;
}

// ── Load service account from env ───────────────────────────────────────────

function getServiceAccount() {
  const b64 = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_B64");
  if (!b64) throw new Error("FIREBASE_SERVICE_ACCOUNT_B64 not set");
  const decoded = atob(b64);
  return JSON.parse(decoded);
}

// ── FCM V1 send ─────────────────────────────────────────────────────────────

interface FcmMessage {
  token?: string;
  topic?: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

async function sendFcm(msg: FcmMessage): Promise<Record<string, unknown>> {
  const sa = getServiceAccount();
  const accessToken = await getAccessToken(sa);

  const isCall = msg.data?.type === 'incoming_call';

  // For incoming calls, send data-only message so the background handler fires
  // on Android even when the app is killed. Regular notifications include the
  // notification block which Android handles itself without waking the app.
  const fcmPayload: Record<string, unknown> = {
    message: {
      ...(isCall ? {} : { notification: { title: msg.title, body: msg.body } }),
      data: {
        ...(msg.data ?? {}),
        // For data-only messages, include title/body in data so the app can
        // build the notification itself
        ...(isCall ? { title: msg.title, body: msg.body } : {}),
      },
      ...(msg.token ? { token: msg.token } : {}),
      ...(msg.topic ? { topic: msg.topic } : {}),
      android: {
        priority: "high",
        ...(isCall ? {} : {
          notification: {
            channel_id: "food_driver_notifications_v3",
            sound: "order_alert",
          },
        }),
      },
      ...(isCall ? {
        apns: {
          payload: {
            aps: {
              'content-available': 1,
              sound: 'default',
              alert: { title: msg.title, body: msg.body },
            },
          },
        },
      } : {}),
    },
  };

  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(fcmPayload),
    }
  );

  const result = await res.json();
  if (!res.ok) {
    throw new Error(`FCM send failed: ${JSON.stringify(result)}`);
  }
  return result;
}

// ── Main handler ────────────────────────────────────────────────────────────


// ── WhatsApp outbox drain ───────────────────────────────────────────────────
// Folded in here rather than shipped as its own function: the project is at
// its 100-function ceiling, and this is the same job — delivering an order
// update to a customer — down a different pipe. Reached with {mode:
// "drain_whatsapp"}; every other request behaves exactly as before.
//
// Configure ONE of:
//   Twilio      TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN, TWILIO_WHATSAPP_FROM
//   Meta Cloud  WHATSAPP_TOKEN, WHATSAPP_PHONE_NUMBER_ID
// With neither, this reports how many messages are waiting rather than
// returning 200 and quietly doing nothing.

/** Jamaican numbers are stored locally as often as not; providers want E.164. */
function toE164(raw: string): string | null {
  const digits = raw.replace(/[^\d+]/g, "");
  if (digits.startsWith("+")) return digits;
  const bare = digits.replace(/\D/g, "");
  if (bare.length === 10) return `+1${bare}`;
  if (bare.length === 11 && bare.startsWith("1")) return `+${bare}`;
  if (bare.length > 11) return `+${bare}`;
  return null;
}

async function waSendTwilio(to: string, text: string): Promise<string> {
  const sid = Deno.env.get("TWILIO_ACCOUNT_SID")!;
  const tok = Deno.env.get("TWILIO_AUTH_TOKEN")!;
  const from = Deno.env.get("TWILIO_WHATSAPP_FROM")!;
  const res = await fetch(
    `https://api.twilio.com/2010-04-01/Accounts/${sid}/Messages.json`,
    {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${sid}:${tok}`)}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        From: `whatsapp:${from}`,
        To: `whatsapp:${to}`,
        Body: text,
      }),
    },
  );
  const d = await res.json();
  if (!res.ok) throw new Error(d.message ?? `Twilio ${res.status}`);
  return d.sid;
}

async function waSendMeta(to: string, text: string): Promise<string> {
  const token = Deno.env.get("WHATSAPP_TOKEN")!;
  const phoneId = Deno.env.get("WHATSAPP_PHONE_NUMBER_ID")!;
  const res = await fetch(
    `https://graph.facebook.com/v20.0/${phoneId}/messages`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        messaging_product: "whatsapp",
        to,
        type: "text",
        text: { body: text },
      }),
    },
  );
  const d = await res.json();
  if (!res.ok) throw new Error(d.error?.message ?? `Meta ${res.status}`);
  return d.messages?.[0]?.id;
}

async function drainWhatsappOutbox() {
  const hasTwilio = !!(Deno.env.get("TWILIO_ACCOUNT_SID") &&
    Deno.env.get("TWILIO_AUTH_TOKEN") && Deno.env.get("TWILIO_WHATSAPP_FROM"));
  const hasMeta = !!(Deno.env.get("WHATSAPP_TOKEN") &&
    Deno.env.get("WHATSAPP_PHONE_NUMBER_ID"));

  const { data: queued } = await admin
    .from("whatsapp_outbox")
    .select("id, to_phone, body, attempts")
    .eq("status", "queued")
    .lt("attempts", 5)
    .order("created_at")
    .limit(50);

  if (!hasTwilio && !hasMeta) {
    return {
      configured: false,
      waiting: queued?.length ?? 0,
      message:
        "No WhatsApp provider configured. Set TWILIO_ACCOUNT_SID/" +
        "TWILIO_AUTH_TOKEN/TWILIO_WHATSAPP_FROM, or WHATSAPP_TOKEN/" +
        "WHATSAPP_PHONE_NUMBER_ID. Messages stay queued until then.",
    };
  }

  let sent = 0, failed = 0, skipped = 0;
  for (const row of queued ?? []) {
    const to = toE164(row.to_phone as string);
    if (!to) {
      await admin.from("whatsapp_outbox").update({
        status: "skipped",
        last_error: `Cannot parse phone "${row.to_phone}"`,
      }).eq("id", row.id);
      skipped++;
      continue;
    }
    try {
      const providerId = hasTwilio
        ? await waSendTwilio(to, row.body as string)
        : await waSendMeta(to, row.body as string);
      await admin.from("whatsapp_outbox").update({
        status: "sent",
        sent_at: new Date().toISOString(),
        provider_id: providerId,
        attempts: (row.attempts as number) + 1,
      }).eq("id", row.id);
      sent++;
    } catch (e) {
      const attempts = (row.attempts as number) + 1;
      // Five tries, then stop. A permanently bad number should not be retried
      // forever.
      await admin.from("whatsapp_outbox").update({
        status: attempts >= 5 ? "failed" : "queued",
        attempts,
        last_error: String(e),
      }).eq("id", row.id);
      failed++;
    }
  }
  return {
    configured: true,
    provider: hasTwilio ? "twilio" : "meta",
    sent,
    failed,
    skipped,
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify caller has a valid Supabase auth or service role key
    const authHeader = req.headers.get("authorization") ?? "";
    if (!authHeader) {
      return json({ error: "Missing authorization header" }, 401);
    }

    const payload = await req.json();

    // WhatsApp drain mode. Checked before the FCM argument validation below,
    // which would otherwise reject it for having no title.
    if (payload?.mode === "drain_whatsapp") {
      return json(await drainWhatsappOutbox());
    }

    const {
      token,   // FCM device token (send to specific device)
      topic,   // FCM topic (send to topic subscribers)
      title,
      body,
      data,
    } = payload;

    if (!title || !body) {
      return json({ error: "title and body are required" }, 400);
    }
    if (!token && !topic) {
      return json({ error: "Either token or topic is required" }, 400);
    }

    const result = await sendFcm({ token, topic, title, body, data });

    // Log notification to DB
    if (data?.user_id) {
      await admin
        .from("notifications")
        .insert({
          user_id: data.user_id,
          title,
          body: body,
          type: data.type ?? "general",
          data: data,
        })
        .then(() => {});
    }

    return json({ success: true, result });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("send-fcm-notification error:", msg);
    return json({ error: msg }, 500);
  }
});

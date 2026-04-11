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

    const {
      token,   // FCM device token (send to specific device)
      topic,   // FCM topic (send to topic subscribers)
      title,
      body,
      data,
    } = await req.json();

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

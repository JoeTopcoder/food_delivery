// send-call-notification — Dedicated edge function for incoming call push notifications
// Fetches recipient FCM token from DB and sends a high-priority data-only FCM message
// so the phone rings even when the app is in the background or killed.

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

// ── Main handler ────────────────────────────────────────────────────────────

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Verify caller has a valid Supabase auth header
    const authHeader = req.headers.get("authorization") ?? "";
    if (!authHeader) {
      return json({ error: "Missing authorization header" }, 401);
    }

    const {
      recipientUserId,
      callerName,
      callId,
      callerId,
      orderId,
      channelName,
    } = await req.json();

    if (!recipientUserId || !callerName || !callId || !channelName) {
      return json(
        { error: "recipientUserId, callerName, callId, and channelName are required" },
        400
      );
    }

    // 1. Fetch recipient's FCM token from the users table
    const { data: user, error: userError } = await admin
      .from("users")
      .select("fcm_token, name")
      .eq("id", recipientUserId)
      .maybeSingle();

    if (userError) {
      console.error("User lookup error:", userError.message);
      return json({ error: "User lookup failed" }, 500);
    }

    if (!user?.fcm_token) {
      console.warn(`No FCM token for user ${recipientUserId}`);
      return json({ error: "Recipient has no FCM token" }, 404);
    }

    // 2. Build and send a data-only FCM message (high priority)
    //    Data-only ensures the background handler fires on Android even when killed
    const sa = getServiceAccount();
    const accessToken = await getAccessToken(sa);

    const fcmPayload = {
      message: {
        token: user.fcm_token,
        // DATA-ONLY — no notification block. This ensures Android delivers to the
        // background handler (firebaseMessagingBackgroundHandler) even when the app
        // is killed. The handler creates the full-screen call notification with the
        // call_ringtone. If a notification block is present Android shows it via the
        // default channel (wrong sound) and skips the background handler entirely.
        data: {
          type: "incoming_call",
          title: "Incoming Call 📞",
          body: `${callerName} is calling you`,
          call_id: callId,
          caller_id: callerId ?? "",
          caller_name: callerName,
          order_id: orderId ?? "",
          channel_name: channelName,
          user_id: recipientUserId,
        },
        android: {
          priority: "high",
        },
        apns: {
          payload: {
            aps: {
              "content-available": 1,
              sound: "default",
              alert: {
                title: "Incoming Call 📞",
                body: `${callerName} is calling you`,
              },
            },
          },
          headers: {
            "apns-priority": "10",
          },
        },
      },
    };

    const fcmRes = await fetch(
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

    const fcmResult = await fcmRes.json();
    if (!fcmRes.ok) {
      console.error("FCM send failed:", JSON.stringify(fcmResult));
      throw new Error(`FCM send failed: ${JSON.stringify(fcmResult)}`);
    }

    // 3. Log the call notification in the notifications table
    await admin
      .from("notifications")
      .insert({
        user_id: recipientUserId,
        title: "Incoming Call",
        body: `${callerName} is calling you`,
        type: "incoming_call",
        data: {
          type: "incoming_call",
          call_id: callId,
          caller_id: callerId,
          order_id: orderId,
          channel_name: channelName,
        },
      })
      .then(() => {});

    console.log(
      `Call notification sent to ${recipientUserId} for call ${callId}`
    );

    return json({ success: true, result: fcmResult });
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error("send-call-notification error:", msg);
    return json({ error: msg }, 500);
  }
});

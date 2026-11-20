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

// ── APNs VoIP push (PushKit → CallKit on iOS) ───────────────────────────────
// Signs an ES256 provider JWT with the Apple VoIP push key (.p8) and POSTs a
// VoIP push to APNs. Secrets (set via `supabase secrets set`):
//   APNS_VOIP_KEY   — contents of the AuthKey_XXXX.p8 (PEM, incl. BEGIN/END)
//   APNS_KEY_ID     — the key's 10-char Key ID
//   APNS_TEAM_ID    — your Apple Developer Team ID
//   APNS_BUNDLE_ID  — the app bundle id (topic is <bundle>.voip)
//   APNS_PRODUCTION — "true" for TestFlight/App Store, "false" for dev builds
async function apnsProviderJwt(): Promise<string> {
  const keyId = Deno.env.get("APNS_KEY_ID");
  const teamId = Deno.env.get("APNS_TEAM_ID");
  const p8 = Deno.env.get("APNS_VOIP_KEY");
  if (!keyId || !teamId || !p8) throw new Error("APNS VoIP secrets not set");

  const now = Math.floor(Date.now() / 1000);
  const enc = new TextEncoder();
  const header = base64UrlEncode(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const payload = base64UrlEncode(enc.encode(JSON.stringify({ iss: teamId, iat: now })));
  const unsigned = `${header}.${payload}`;

  const pemBody = p8
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const binaryKey = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const key = await crypto.subtle.importKey(
    "pkcs8", binaryKey, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]
  );
  const sig = new Uint8Array(
    await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, key, enc.encode(unsigned))
  );
  return `${unsigned}.${base64UrlEncode(sig)}`;
}

async function sendVoipPush(voipToken: string, callData: Record<string, unknown>): Promise<Response> {
  const jwt = await apnsProviderJwt();
  const bundle = Deno.env.get("APNS_BUNDLE_ID") ?? "com.quickdash.app";
  const prod = (Deno.env.get("APNS_PRODUCTION") ?? "true") === "true";
  const host = prod ? "api.push.apple.com" : "api.sandbox.push.apple.com";
  return await fetch(`https://${host}/3/device/${voipToken}`, {
    method: "POST",
    headers: {
      authorization: `bearer ${jwt}`,
      "apns-topic": `${bundle}.voip`,
      "apns-push-type": "voip",
      "apns-priority": "10",
      "content-type": "application/json",
    },
    body: JSON.stringify(callData),
  });
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
      .select("fcm_token, voip_token, name")
      .eq("id", recipientUserId)
      .maybeSingle();

    if (userError) {
      console.error("User lookup error:", userError.message);
      return json({ error: "User lookup failed" }, 500);
    }

    if (!user?.fcm_token && !user?.voip_token) {
      console.warn(`No FCM or VoIP token for user ${recipientUserId}`);
      return json({ error: "Recipient has no push token" }, 404);
    }

    // Look up the caller's role so the receiver's call screen can show who's
    // calling ("Driver", "HotBite", etc.).
    // PRIVACY: never expose a caller's full name to the other party. We derive a
    // first-name-only display from the authoritative DB record and ignore the
    // client-supplied callerName (which was the full name). Falls back to masking
    // the client value if the caller row can't be read.
    const firstNameOnly = (n: string) =>
      (n || "").trim().split(/\s+/)[0] || "Someone";
    let callerRole = "";
    let safeCallerName = firstNameOnly(callerName);
    if (callerId) {
      const { data: callerRow } = await admin
        .from("users").select("role, name").eq("id", callerId).maybeSingle();
      callerRole = (callerRow?.role as string) ?? "";
      const dbName = ((callerRow?.name as string) ?? "").trim();
      if (dbName) safeCallerName = firstNameOnly(dbName);
    }

    // Branded, role-based label shown large on the recipient's ringing screen.
    // A driver is never shown by name to the customer — they see "HotBite Driver"
    // plus the short order code; a customer is shown to the driver as
    // "HotBite Customer". Any other role falls back to the masked first name.
    const shortOrder = (orderId as string | undefined)
      ? String(orderId).replace(/-/g, "").slice(0, 8).toUpperCase()
      : "";
    let displayCaller: string;
    // Branded ringtone bundled in the app's res/raw/ — chosen by the caller's
    // role so the recipient can recognise who's calling by sound. The app maps
    // this to the matching raw resource and falls back to call_ringtone.
    let ringtone = "call_ringtone";
    if (callerRole === "driver") {
      displayCaller = shortOrder
        ? `HotBite Driver · Order #${shortOrder}`
        : "HotBite Driver";
      ringtone = "hotbite_ring_driver";
    } else if (callerRole === "customer") {
      displayCaller = "HotBite Customer";
      ringtone = "hotbite_ring_customer";
    } else if (callerRole === "restaurant") {
      displayCaller = "HotBite Restaurant";
      ringtone = "hotbite_ring_restaurant";
    } else {
      displayCaller = safeCallerName;
    }
    safeCallerName = displayCaller;

    // 1b. iOS VoIP push (PushKit → CallKit ring). Preferred for iOS: it wakes
    //     the app and rings even when backgrounded/locked. If the recipient has
    //     a voip_token and the APNs VoIP key is configured, send it and stop.
    //     Any failure falls through to the FCM path below (so iOS still gets at
    //     least an alert banner until the Apple VoIP key is set).
    if (user.voip_token) {
      try {
        const voipRes = await sendVoipPush(user.voip_token as string, {
          call_id: callId,
          caller_name: safeCallerName,
          caller_id: callerId ?? "",
          caller_role: callerRole,
          channel_name: channelName,
          order_id: orderId ?? "",
          handle: safeCallerName,
          aps: {}, // VoIP pushes carry no alert; CallKit renders the UI
        });
        if (voipRes.ok) {
          await admin.from("notifications").insert({
            user_id: recipientUserId, title: "Incoming Call",
            body: `${safeCallerName} is calling you`, type: "incoming_call",
            data: { type: "incoming_call", call_id: callId, caller_id: callerId,
                    order_id: orderId, channel_name: channelName },
          }).then(() => {});
          console.log(`VoIP call push sent to ${recipientUserId} for call ${callId}`);
          return json({ success: true, via: "voip", status: voipRes.status });
        }
        console.warn(`VoIP push failed (${voipRes.status}): ${await voipRes.text()} — falling back to FCM`);
      } catch (e) {
        console.warn(`VoIP push error (${e instanceof Error ? e.message : e}) — falling back to FCM`);
      }
    }

    // 2. Build and send a data-only FCM message (high priority)
    //    Data-only ensures the background handler fires on Android even when killed
    if (!user.fcm_token) {
      // iOS-only recipient whose VoIP push just failed and has no FCM token.
      return json({ error: "VoIP push failed and no FCM token to fall back to" }, 502);
    }
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
          body: `${safeCallerName} is calling you`,
          call_id: callId,
          caller_id: callerId ?? "",
          caller_name: safeCallerName,
          caller_role: callerRole,
          ringtone: ringtone,
          order_id: orderId ?? "",
          channel_name: channelName,
          user_id: recipientUserId,
        },
        android: {
          priority: "high",
        },
        // iOS: send a real ALERT push (not a silent content-available background
        // push, which iOS throttles and shows nothing). This makes a backgrounded
        // or locked iPhone surface the incoming-call notification with sound; the
        // custom data keys ride along so tapping it opens the call screen.
        // NOTE: true phone-style ringing (CallKit while locked) still needs a
        // PushKit VoIP push — a separate native pipeline, not this FCM path.
        apns: {
          payload: {
            aps: {
              alert: {
                title: "Incoming Call 📞",
                body: `${safeCallerName} is calling you`,
              },
              sound: "default",
              "interruption-level": "time-sensitive",
            },
          },
          headers: {
            "apns-priority": "10",
            "apns-push-type": "alert",
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
        body: `${safeCallerName} is calling you`,
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

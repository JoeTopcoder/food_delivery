// send-promotion — Sends scheduled promotional push notifications to users
// Queries scheduled_promotions table for due promotions and sends FCM to target users

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
async function getAccessToken(): Promise<string> {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY_BASE64") ?? "";
  if (!raw) throw new Error("FCM_SERVICE_ACCOUNT_KEY_BASE64 not set");

  const sa = JSON.parse(atob(raw));
  const iat = Math.floor(Date.now() / 1000);
  const exp = iat + 3600;

  // @ts-ignore: Deno ESM import
  const { encode: b64url } = await import(
    "https://deno.land/std@0.224.0/encoding/base64url.ts"
  );
  // @ts-ignore: Deno crypto
  const { crypto } = globalThis;

  const header = b64url(new TextEncoder().encode(JSON.stringify({ alg: "RS256", typ: "JWT" })));
  const payload = b64url(
    new TextEncoder().encode(
      JSON.stringify({
        iss: sa.client_email,
        scope: "https://www.googleapis.com/auth/firebase.messaging",
        aud: "https://oauth2.googleapis.com/token",
        iat,
        exp,
      })
    )
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
    ["sign"]
  );

  const sig = b64url(new Uint8Array(await crypto.subtle.sign("RSASSA-PKCS1-v1_5", key, sigInput)));
  const jwt = `${header}.${payload}.${sig}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const tokenJson = await tokenRes.json();
  if (!tokenJson.access_token) throw new Error("OAuth token error: " + JSON.stringify(tokenJson));
  return tokenJson.access_token;
}

// ── Send FCM notification to a device ───────────────────────────────────────
async function sendFcm(
  accessToken: string,
  projectId: string,
  fcmToken: string,
  title: string,
  body: string,
  data?: Record<string, string>
): Promise<boolean> {
  try {
    const res = await fetch(
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
            data: data ?? {},
            android: {
              priority: "high",
              notification: {
                channel_id: "food_driver_promos",
                sound: "default",
              },
            },
          },
        }),
      }
    );
    return res.ok;
  } catch {
    return false;
  }
}

// ── Main handler ────────────────────────────────────────────────────────────
Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Fetch due promotions that haven't been sent
    const now = new Date().toISOString();
    const { data: promos, error: promoErr } = await admin
      .from("scheduled_promotions")
      .select("*")
      .eq("sent", false)
      .lte("send_at", now);

    if (promoErr) throw promoErr;
    if (!promos || promos.length === 0) {
      return json({ sent: 0, message: "No promotions due" });
    }

    const raw = Deno.env.get("FCM_SERVICE_ACCOUNT_KEY_BASE64") ?? "";
    const sa = JSON.parse(atob(raw));
    const projectId = sa.project_id;
    const accessToken = await getAccessToken();

    let totalSent = 0;

    for (const promo of promos) {
      // Determine target users
      let targetUserIds: string[] = [];

      if (promo.target_audience === "all") {
        // Send to all users with FCM tokens
        const { data: profiles } = await admin
          .from("profiles")
          .select("id")
          .not("fcm_token", "is", null);
        targetUserIds = (profiles ?? []).map((p: any) => p.id);
      } else if (promo.target_audience === "active") {
        // Users who ordered in the last 30 days
        const thirtyDaysAgo = new Date(
          Date.now() - 30 * 24 * 60 * 60 * 1000
        ).toISOString();
        const { data: recentOrders } = await admin
          .from("orders")
          .select("user_id")
          .gte("created_at", thirtyDaysAgo);
        const uniqueIds = [
          ...new Set((recentOrders ?? []).map((o: any) => o.user_id)),
        ];
        targetUserIds = uniqueIds as string[];
      } else if (promo.target_audience === "inactive") {
        // Users who haven't ordered in 30+ days
        const thirtyDaysAgo = new Date(
          Date.now() - 30 * 24 * 60 * 60 * 1000
        ).toISOString();
        const { data: allProfiles } = await admin
          .from("profiles")
          .select("id")
          .not("fcm_token", "is", null);
        const { data: recentOrders } = await admin
          .from("orders")
          .select("user_id")
          .gte("created_at", thirtyDaysAgo);
        const activeIds = new Set(
          (recentOrders ?? []).map((o: any) => o.user_id)
        );
        targetUserIds = (allProfiles ?? [])
          .filter((p: any) => !activeIds.has(p.id))
          .map((p: any) => p.id);
      }

      // Fetch FCM tokens for target users
      let sentForPromo = 0;
      for (const userId of targetUserIds) {
        const { data: profile } = await admin
          .from("profiles")
          .select("fcm_token")
          .eq("id", userId)
          .single();

        if (profile?.fcm_token) {
          const ok = await sendFcm(
            accessToken,
            projectId,
            profile.fcm_token,
            promo.title,
            promo.body,
            {
              type: "promotion",
              promo_id: promo.id,
              ...(promo.deep_link ? { deep_link: promo.deep_link } : {}),
            }
          );
          if (ok) sentForPromo++;
        }
      }

      // Mark as sent
      await admin
        .from("scheduled_promotions")
        .update({ sent: true })
        .eq("id", promo.id);

      totalSent += sentForPromo;
    }

    return json({ sent: totalSent, promos_processed: promos.length });
  } catch (e: any) {
    console.error("send-promotion error:", e);
    return json({ error: e.message ?? String(e) }, 500);
  }
});

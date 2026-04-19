// stripe-subscription-webhook — Handles Stripe webhook events for subscription lifecycle
// Events: invoice.payment_succeeded, invoice.payment_failed, customer.subscription.deleted
// Deploy: supabase functions deploy stripe-subscription-webhook --no-verify-jwt

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_SUBSCRIPTION_WEBHOOK_SECRET") ?? "";

const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, stripe-signature",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function getConfig(key: string, fallback: string): Promise<string> {
  const { data } = await admin
    .from("app_config")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  return data?.value ?? fallback;
}

// Simple HMAC-SHA256 for Stripe signature verification (Web Crypto API)
async function verifyStripeSignature(
  payload: string,
  sigHeader: string,
  secret: string
): Promise<boolean> {
  if (!secret) return true; // Skip verification if no secret set (dev mode)

  const parts = sigHeader.split(",");
  let timestamp = "";
  let signatures: string[] = [];
  for (const part of parts) {
    const [k, v] = part.split("=");
    if (k === "t") timestamp = v;
    if (k === "v1") signatures.push(v);
  }

  if (!timestamp || signatures.length === 0) return false;

  // Check timestamp freshness (5 min tolerance)
  const ts = parseInt(timestamp);
  if (Math.abs(Date.now() / 1000 - ts) > 300) return false;

  const signedPayload = `${timestamp}.${payload}`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign("HMAC", key, encoder.encode(signedPayload));
  const hex = [...new Uint8Array(sig)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return signatures.includes(hex);
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const rawBody = await request.text();
  const sigHeader = request.headers.get("stripe-signature") ?? "";

  // Verify Stripe signature
  if (STRIPE_WEBHOOK_SECRET) {
    const valid = await verifyStripeSignature(rawBody, sigHeader, STRIPE_WEBHOOK_SECRET);
    if (!valid) {
      return json({ error: "Invalid signature" }, 400);
    }
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody);
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const eventType = event.type as string;
  const dataObject = (event.data as Record<string, unknown>)?.object as Record<
    string,
    unknown
  >;

  console.log(`[subscription-webhook] Event: ${eventType}`);

  // ═══════════════════════════════════════════════════════════════════════════
  // invoice.payment_succeeded — Activate or renew subscription
  // ═══════════════════════════════════════════════════════════════════════════
  if (eventType === "invoice.payment_succeeded") {
    const subscriptionId = dataObject.subscription as string;
    if (!subscriptionId) return json({ received: true });

    // Fetch the Stripe subscription to get metadata
    const res = await fetch(
      `https://api.stripe.com/v1/subscriptions/${encodeURIComponent(subscriptionId)}`,
      {
        headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
      }
    );
    const stripeSub = (await res.json()) as Record<string, unknown>;
    const metadata = (stripeSub.metadata ?? {}) as Record<string, string>;
    const planType = metadata.plan_type ?? "basic";
    const periodEnd = new Date(
      ((stripeSub.current_period_end as number) ?? 0) * 1000
    );

    // Get deliveries for this plan from config
    const deliveries =
      planType === "basic"
        ? await getConfig("subscription_basic_deliveries", "9")
        : await getConfig("subscription_pro_deliveries", "22");
    const serviceFeeDiscount = await getConfig(
      "subscription_service_fee_discount",
      "0.50"
    );

    // Find existing subscription row
    const { data: existingSub } = await admin
      .from("user_subscriptions")
      .select("id, status, deliveries_remaining")
      .eq("stripe_subscription_id", subscriptionId)
      .maybeSingle();

    if (existingSub) {
      // Renewal or initial activation
      const isRenewal = existingSub.status === "active";
      const newDeliveries = isRenewal
        ? existingSub.deliveries_remaining + parseInt(deliveries)
        : parseInt(deliveries);

      await admin
        .from("user_subscriptions")
        .update({
          status: "active",
          current_period_end: periodEnd.toISOString(),
          deliveries_remaining: newDeliveries,
          deliveries_used: isRenewal ? undefined : 0,
          meals_remaining: newDeliveries,
          service_fee_discount: parseFloat(serviceFeeDiscount),
          updated_at: new Date().toISOString(),
        })
        .eq("id", existingSub.id);

      console.log(
        `[subscription-webhook] ${isRenewal ? "Renewed" : "Activated"} subscription ${existingSub.id}, deliveries=${newDeliveries}`
      );
    }

    return json({ received: true });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // invoice.payment_failed — Mark subscription as past_due
  // ═══════════════════════════════════════════════════════════════════════════
  if (eventType === "invoice.payment_failed") {
    const subscriptionId = dataObject.subscription as string;
    if (!subscriptionId) return json({ received: true });

    const { data: existingSub } = await admin
      .from("user_subscriptions")
      .select("id")
      .eq("stripe_subscription_id", subscriptionId)
      .maybeSingle();

    if (existingSub) {
      // Don't cancel — just pause. User can retry.
      await admin
        .from("user_subscriptions")
        .update({
          status: "paused",
          updated_at: new Date().toISOString(),
        })
        .eq("id", existingSub.id);

      console.log(
        `[subscription-webhook] Payment failed, paused subscription ${existingSub.id}`
      );
    }

    return json({ received: true });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // customer.subscription.deleted — Cancel subscription
  // ═══════════════════════════════════════════════════════════════════════════
  if (eventType === "customer.subscription.deleted") {
    const subscriptionId = dataObject.id as string;
    if (!subscriptionId) return json({ received: true });

    const { data: existingSub } = await admin
      .from("user_subscriptions")
      .select("id")
      .eq("stripe_subscription_id", subscriptionId)
      .maybeSingle();

    if (existingSub) {
      await admin
        .from("user_subscriptions")
        .update({
          status: "cancelled",
          deliveries_remaining: 0,
          meals_remaining: 0,
          updated_at: new Date().toISOString(),
        })
        .eq("id", existingSub.id);

      console.log(
        `[subscription-webhook] Cancelled subscription ${existingSub.id}`
      );
    }

    return json({ received: true });
  }

  // Unhandled event type — acknowledge receipt
  console.log(`[subscription-webhook] Unhandled event: ${eventType}`);
  return json({ received: true });
});

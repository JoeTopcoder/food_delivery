// Stripe Webhook Handler — full implementation
//
// Configure in Stripe Dashboard → Developers → Webhooks:
//   Endpoint URL : https://yharweliruemjexmuuxn.supabase.co/functions/v1/stripe-webhook
//   Events       : payment_intent.succeeded
//                  payment_intent.payment_failed
//                  payment_intent.canceled
//
// Required Supabase secrets (set via CLI or dashboard):
//   STRIPE_WEBHOOK_SECRET   – Stripe → Webhooks → Signing secret (starts with whsec_)
//   SUPABASE_SERVICE_ROLE_KEY
//   SUPABASE_URL
//
// Deploy:
//   npx supabase functions deploy stripe-webhook --no-verify-jwt --project-ref yharweliruemjexmuuxn

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const WEBHOOK_SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SRK = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function jsonResp(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

// ── HMAC-SHA-256 Stripe signature verification ────────────────────────────────
// Stripe signs: "{timestamp}.{rawBody}" with the webhook secret.
// Header format: "t=<ts>,v1=<hex>"
async function verifySignature(
  rawBody: string,
  header: string,
  secret: string
): Promise<boolean> {
  if (!secret || !header) return false;

  const parts: Record<string, string> = {};
  for (const chunk of header.split(",")) {
    const eq = chunk.indexOf("=");
    if (eq > 0) parts[chunk.slice(0, eq)] = chunk.slice(eq + 1);
  }

  const ts = parts["t"];
  const v1 = parts["v1"];
  if (!ts || !v1) return false;

  // Reject webhooks older than 5 minutes (Stripe replay-attack protection)
  const ageSeconds = Math.floor(Date.now() / 1000) - parseInt(ts, 10);
  if (ageSeconds > 300) return false;

  const signedPayload = `${ts}.${rawBody}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sigBytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signedPayload)
  );
  const computed = Array.from(new Uint8Array(sigBytes))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Constant-time comparison to prevent timing attacks
  if (computed.length !== v1.length) return false;
  let diff = 0;
  for (let i = 0; i < computed.length; i++) {
    diff |= computed.charCodeAt(i) ^ v1.charCodeAt(i);
  }
  return diff === 0;
}

// ── payment_intent.succeeded ──────────────────────────────────────────────────
// This is the ONLY path that activates a card order. It:
//   1. Upserts the payment record (idempotent via transaction_id)
//   2. Sets payment_status = 'completed' on the order
//   3. Sets status = 'pending' (activates the order — makes it visible to restaurant/driver)
//   4. Sets finalized_at and stores payment_intent_id
//   5. DB triggers then fire restaurant / admin / driver FCM notifications
//   6. Sends receipt email
async function onSucceeded(
  db: ReturnType<typeof createClient>,
  pi: Record<string, unknown>
): Promise<void> {
  const piId = pi.id as string;
  const meta = (pi.metadata ?? {}) as Record<string, string>;
  const orderId = meta["order_id"] ?? "";
  const txnType = meta["type"] ?? "order";
  const userId = meta["user_id"] ?? null;
  const amountReceived = ((pi.amount_received as number) ?? (pi.amount as number) ?? 0) / 100;
  const currency = ((pi.currency as string) ?? "usd").toUpperCase();
  const now = new Date().toISOString();

  // Idempotency guard: if this PI already completed, do nothing.
  const { data: existing } = await db
    .from("payments")
    .select("id, status")
    .eq("transaction_id", piId)
    .maybeSingle();
  if (existing?.status === "completed") return;

  if (txnType === "order" && orderId) {
    // ── Verify order exists and has not been finalized by a prior webhook ─
    const { data: order } = await db
      .from("orders")
      .select("id, payment_status, total_amount, payment_method")
      .eq("id", orderId)
      .maybeSingle();

    if (!order) {
      console.error(`[stripe-webhook] order ${orderId} not found for PI ${piId}`);
      return;
    }
    if (order.payment_status === "completed") {
      // Already finalized — idempotent, skip silently.
      return;
    }

    // Amount guard: confirm charged amount matches order total (within 1 cent)
    const expectedAmount = Math.round((order.total_amount as number) * 100);
    const receivedAmount = Math.round(amountReceived * 100);
    if (Math.abs(expectedAmount - receivedAmount) > 1) {
      console.error(
        `[stripe-webhook] AMOUNT MISMATCH order=${orderId} expected=${expectedAmount} received=${receivedAmount}`
      );
      // Mark payment failed — do not activate the order.
      await db
        .from("orders")
        .update({ payment_status: "failed", updated_at: now })
        .eq("id", orderId);
      return;
    }

    // ── Upsert payment record ─────────────────────────────────────────────
    await db.from("payments").upsert(
      {
        order_id: orderId,
        user_id: userId,
        amount: amountReceived,
        currency,
        method: "card",
        gateway: "stripe",
        status: "completed",
        transaction_id: piId,
        paid_at: now,
        idempotency_key: `wh_succeeded_${piId}`,
        updated_at: now,
      },
      { onConflict: "order_id", ignoreDuplicates: false }
    );

    // ── Activate the order ────────────────────────────────────────────────
    // Setting status = 'preparing' AND payment_status = 'completed' in the
    // same UPDATE satisfies the DB constraint (check_card_payment_gate).
    // Auto-approve: orders skip the pending restaurant-approval step.
    // The DB triggers then fire restaurant/admin/driver FCM notifications.
    await db
      .from("orders")
      .update({
        payment_status: "completed",
        status: "preparing",            // auto-approved — restaurant starts preparing immediately
        checkout_status: "payment_success",
        payment_intent_id: piId,
        finalized_at: now,
        updated_at: now,
      })
      .eq("id", orderId)
      .neq("payment_status", "completed");  // idempotency

    // ── Send receipt email ────────────────────────────────────────────────
    // Fire-and-forget: not critical path.
    const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
    const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
    const admin = createClient(supabaseUrl, serviceKey);
    admin.functions.invoke("send-receipt-email", {
      body: { order_id: orderId },
    }).catch(() => {});
  }
}

// ── payment_intent.payment_failed ─────────────────────────────────────────────
// Order stays in 'draft' status — NOT visible to restaurant or driver.
async function onFailed(
  db: ReturnType<typeof createClient>,
  pi: Record<string, unknown>
): Promise<void> {
  const piId = pi.id as string;
  const meta = (pi.metadata ?? {}) as Record<string, string>;
  const orderId = meta["order_id"] ?? "";
  const txnType = meta["type"] ?? "order";
  const lastError = pi.last_payment_error as Record<string, unknown> | null;
  const errorMsg = (lastError?.message as string) ?? "Payment failed";
  const now = new Date().toISOString();

  if (txnType === "order" && orderId) {
    await db
      .from("payments")
      .update({ status: "failed", error_message: errorMsg, updated_at: now })
      .eq("transaction_id", piId);

    // Keep status = 'draft' — only update payment_status and checkout_status.
    // Do NOT set status = 'pending'; the order must not become visible.
    await db
      .from("orders")
      .update({
        payment_status: "failed",
        checkout_status: "payment_failed",
        updated_at: now,
      })
      .eq("id", orderId)
      .in("payment_status", ["pending", "processing"]);
  }
}

// ── payment_intent.canceled ───────────────────────────────────────────────────
// Order stays in 'draft' — NOT visible to restaurant or driver.
async function onCanceled(
  db: ReturnType<typeof createClient>,
  pi: Record<string, unknown>
): Promise<void> {
  const piId = pi.id as string;
  const meta = (pi.metadata ?? {}) as Record<string, string>;
  const orderId = meta["order_id"] ?? "";
  const txnType = meta["type"] ?? "order";
  const now = new Date().toISOString();

  if (txnType === "order" && orderId) {
    await db
      .from("payments")
      .update({ status: "cancelled", updated_at: now })
      .eq("transaction_id", piId);

    await db
      .from("orders")
      .update({
        payment_status: "cancelled",
        checkout_status: "payment_cancelled",
        updated_at: now,
      })
      .eq("id", orderId)
      .in("payment_status", ["pending", "processing"]);
  }
}

// ── Main request handler ──────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { status: 200 });
  }
  if (req.method !== "POST") {
    return jsonResp({ error: "Method not allowed" }, 405);
  }

  // Read body as raw text — must happen BEFORE JSON.parse for sig verification
  const rawBody = await req.text();
  const sigHeader = req.headers.get("stripe-signature") ?? "";

  if (WEBHOOK_SECRET) {
    const valid = await verifySignature(rawBody, sigHeader, WEBHOOK_SECRET);
    if (!valid) {
      console.error("Stripe webhook signature invalid");
      return jsonResp({ error: "Invalid signature" }, 400);
    }
  } else {
    // Log a warning but continue — allows testing before STRIPE_WEBHOOK_SECRET is set.
    console.warn("STRIPE_WEBHOOK_SECRET not set — skipping signature verification");
  }

  let event: Record<string, unknown>;
  try {
    event = JSON.parse(rawBody) as Record<string, unknown>;
  } catch {
    return jsonResp({ error: "Invalid JSON" }, 400);
  }

  const eventType = (event.type as string) ?? "";
  const eventData = event.data as Record<string, unknown>;
  const pi = eventData?.object as Record<string, unknown>;

  if (!pi?.id) {
    return jsonResp({ error: "Missing event object" }, 400);
  }

  const db = createClient(SUPABASE_URL, SUPABASE_SRK);

  try {
    switch (eventType) {
      case "payment_intent.succeeded":
        await onSucceeded(db, pi);
        break;
      case "payment_intent.payment_failed":
        await onFailed(db, pi);
        break;
      case "payment_intent.canceled":
        await onCanceled(db, pi);
        break;
      default:
        // Acknowledge all events Stripe sends — prevents Stripe from retrying
        break;
    }

    return jsonResp({ received: true, type: eventType });
  } catch (err) {
    // Return 200 anyway so Stripe doesn't retry — log the real error
    console.error(`Webhook handler [${eventType}]:`, (err as Error).message);
    return jsonResp({ received: true, processing_error: (err as Error).message });
  }
});

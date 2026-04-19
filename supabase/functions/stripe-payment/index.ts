// Stripe Payment Edge Function
// Creates PaymentIntents for orders, wallet top-ups, and card verification
// SECURITY: Stripe secret key is stored as a Supabase secret, never exposed to client

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function stripeRequest(
  endpoint: string,
  params: Record<string, string>
): Promise<Record<string, unknown>> {
  const response = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(params).toString(),
  });
  return (await response.json()) as Record<string, unknown>;
}

async function stripeGet(endpoint: string): Promise<Record<string, unknown>> {
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "GET",
    headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
  });
  return (await res.json()) as Record<string, unknown>;
}

async function getOrCreateStripeCustomer(
  adminClient: ReturnType<typeof createClient>,
  userId: string,
  email: string,
  name: string
): Promise<string> {
  // Check users table first
  const { data: userRow } = await adminClient
    .from("users")
    .select("stripe_customer_id")
    .eq("id", userId)
    .single();
  if (userRow?.stripe_customer_id) return userRow.stripe_customer_id;

  // Check user_subscriptions table
  const { data: subRow } = await adminClient
    .from("user_subscriptions")
    .select("stripe_customer_id")
    .eq("user_id", userId)
    .not("stripe_customer_id", "is", null)
    .limit(1)
    .maybeSingle();
  if (subRow?.stripe_customer_id) {
    // Save to users table for future lookups
    await adminClient
      .from("users")
      .update({ stripe_customer_id: subRow.stripe_customer_id })
      .eq("id", userId);
    return subRow.stripe_customer_id;
  }

  // Search Stripe by metadata
  const searchResp = await fetch(
    `https://api.stripe.com/v1/customers/search?query=metadata%5B%27supabase_user_id%27%5D%3A%27${userId}%27`,
    { method: "GET", headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` } }
  );
  const searchResult = (await searchResp.json()) as Record<string, unknown>;
  const existing = (searchResult.data ?? []) as Array<Record<string, unknown>>;
  if (existing.length > 0) {
    const cid = existing[0].id as string;
    await adminClient.from("users").update({ stripe_customer_id: cid }).eq("id", userId);
    return cid;
  }

  // Create new customer
  const newCust = await stripeRequest("/customers", {
    email,
    name,
    "metadata[supabase_user_id]": userId,
  });
  if (newCust.error) throw new Error("Failed to create Stripe customer");
  const cid = newCust.id as string;
  await adminClient.from("users").update({ stripe_customer_id: cid }).eq("id", userId);
  return cid;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!STRIPE_SECRET_KEY) {
    return json(
      { error: "Stripe is not configured. Set STRIPE_SECRET_KEY." },
      500
    );
  }

  // Verify authorization
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing authorization header." }, 401);
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const action = String(body.action ?? "create_payment_intent").trim();

  // ── Create PaymentIntent ──────────────────────────────────────

  if (action === "create_payment_intent") {
    const orderId = String(body.orderId ?? "").trim();
    const amount = Number(body.amount ?? 0);
    const email = String(body.email ?? "").trim();
    const name = String(body.name ?? "").trim();
    const txnType = String(body.type ?? "order").trim(); // order | wallet_topup
    const currency = String(body.currency ?? "usd").trim().toLowerCase();

    if (!orderId || amount <= 0 || !email) {
      return json(
        {
          error:
            "Missing required fields (orderId, amount > 0, email).",
        },
        400
      );
    }

    const isNonOrder = txnType === "wallet_topup";

    // For standard orders, validate the order exists and belongs to user
    if (!isNonOrder) {
      const { data: order, error: orderError } = await adminClient
        .from("orders")
        .select("id, user_id, total_amount, payment_status")
        .eq("id", orderId)
        .single();

      if (orderError || !order) {
        return json({ error: "Order not found." }, 404);
      }

      if (order.user_id !== userData.user.id) {
        return json({ error: "Order does not belong to you." }, 403);
      }

      if (order.payment_status === "completed") {
        return json({ error: "Order is already paid." }, 400);
      }
    }

    // Amount in cents for Stripe
    const amountInCents = Math.round(amount * 100);

    try {
      // Get or create Stripe customer for saved card support
      const customerId = await getOrCreateStripeCustomer(
        adminClient, userData.user.id, email, name
      );

      const params: Record<string, string> = {
        amount: String(amountInCents),
        currency,
        customer: customerId,
        "automatic_payment_methods[enabled]": "true",
        "metadata[order_id]": orderId,
        "metadata[user_id]": userData.user.id,
        "metadata[type]": txnType,
        receipt_email: email,
        description:
          txnType === "wallet_topup"
            ? `Wallet top-up ${orderId}`
            : `Order payment ${orderId}`,
      };

      if (name) {
        params["metadata[customer_name]"] = name;
      }

      const paymentIntent = await stripeRequest("/payment_intents", params);

      if (paymentIntent.error) {
        const err = paymentIntent.error as Record<string, unknown>;
        return json(
          { error: err.message ?? "Failed to create payment intent." },
          400
        );
      }

      // Record the payment in Supabase payments table (for order payments)
      if (!isNonOrder) {
        await adminClient.from("payments").upsert(
          {
            order_id: orderId,
            user_id: userData.user.id,
            amount: amount,
            currency: currency.toUpperCase(),
            payment_method: "card",
            status: "pending",
            transaction_id: paymentIntent.id as string,
            metadata: {
              stripe_payment_intent_id: paymentIntent.id,
              type: txnType,
            },
          },
          { onConflict: "order_id" }
        );
      }

      // Generate ephemeral key so PaymentSheet shows saved cards
      const ephRes = await fetch("https://api.stripe.com/v1/ephemeral_keys", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
          "Stripe-Version": "2024-06-20",
        },
        body: new URLSearchParams({ customer: customerId }).toString(),
      });
      const ephData = (await ephRes.json()) as Record<string, unknown>;

      return json({
        clientSecret: paymentIntent.client_secret,
        paymentIntentId: paymentIntent.id,
        customerId,
        ephemeralKey: ephData.secret,
        amount: amount,
        currency,
      });
    } catch (e) {
      return json({ error: `Stripe error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Confirm Payment (called after Stripe sheet success) ───────

  if (action === "confirm_payment") {
    const paymentIntentId = String(body.paymentIntentId ?? "").trim();
    const orderId = String(body.orderId ?? "").trim();
    const txnType = String(body.type ?? "order").trim();

    if (!paymentIntentId) {
      return json({ error: "Missing paymentIntentId." }, 400);
    }

    try {
      // Retrieve PaymentIntent from Stripe to verify status
      const response = await fetch(
        `https://api.stripe.com/v1/payment_intents/${encodeURIComponent(
          paymentIntentId
        )}`,
        {
          method: "GET",
          headers: {
            Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
          },
        }
      );
      const pi = (await response.json()) as Record<string, unknown>;

      if (pi.error) {
        return json({ error: "Payment intent not found." }, 404);
      }

      const piStatus = pi.status as string;
      const isSucceeded =
        piStatus === "succeeded" || piStatus === "requires_capture";

      if (isSucceeded && orderId && txnType === "order") {
        // Update payment record
        await adminClient
          .from("payments")
          .update({
            status: "completed",
            transaction_id: paymentIntentId,
            updated_at: new Date().toISOString(),
          })
          .eq("order_id", orderId);

        // Update order payment status
        await adminClient
          .from("orders")
          .update({
            payment_status: "completed",
            updated_at: new Date().toISOString(),
          })
          .eq("id", orderId);
      }

      return json({
        status: piStatus,
        success: isSucceeded,
        paymentIntentId: pi.id,
      });
    } catch (e) {
      return json(
        { error: `Verification error: ${(e as Error).message}` },
        500
      );
    }
  }

  // ── Create SetupIntent (for saving cards without charging) ────

  if (action === "create_setup_intent") {
    const email = String(body.email ?? userData.user.email ?? "").trim();
    const name = String(body.name ?? (userData.user.user_metadata?.name as string) ?? email).trim();

    try {
      const customerId = await getOrCreateStripeCustomer(
        adminClient, userData.user.id, email, name
      );

      // Create SetupIntent
      const setupIntent = await stripeRequest("/setup_intents", {
        customer: customerId,
        "automatic_payment_methods[enabled]": "true",
        "metadata[user_id]": userData.user.id,
        usage: "off_session",
      });

      if (setupIntent.error) {
        const err = setupIntent.error as Record<string, unknown>;
        return json(
          { error: err.message ?? "Failed to create setup intent." },
          400
        );
      }

      return json({
        clientSecret: setupIntent.client_secret,
        setupIntentId: setupIntent.id,
        customerId,
      });
    } catch (e) {
      return json(
        { error: `Setup intent error: ${(e as Error).message}` },
        500
      );
    }
  }

  // ── List Payment Methods (saved cards from Stripe) ────────────

  if (action === "list_payment_methods") {
    try {
      const email = userData.user.email ?? "";
      const name = (userData.user.user_metadata?.name as string) ?? email;
      const customerId = await getOrCreateStripeCustomer(
        adminClient, userData.user.id, email, name
      );

      const methods = await stripeGet(
        `/payment_methods?customer=${customerId}&type=card&limit=10`
      );

      const cards = ((methods.data ?? []) as Array<Record<string, unknown>>).map(
        (pm) => {
          const card = pm.card as Record<string, unknown>;
          return {
            payment_method_id: pm.id,
            brand: card.brand,
            last4: card.last4,
            exp_month: card.exp_month,
            exp_year: card.exp_year,
          };
        }
      );

      return json({ cards, customer_id: customerId });
    } catch (e) {
      return json({ error: `List cards error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Ephemeral Key (for PaymentSheet saved cards) ──────────────

  if (action === "ephemeral_key") {
    try {
      const email = userData.user.email ?? "";
      const name = (userData.user.user_metadata?.name as string) ?? email;
      const customerId = await getOrCreateStripeCustomer(
        adminClient, userData.user.id, email, name
      );

      const res = await fetch("https://api.stripe.com/v1/ephemeral_keys", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
          "Content-Type": "application/x-www-form-urlencoded",
          "Stripe-Version": "2024-06-20",
        },
        body: new URLSearchParams({ customer: customerId }).toString(),
      });
      const keyData = (await res.json()) as Record<string, unknown>;

      return json({
        ephemeral_key: keyData.secret,
        customer_id: customerId,
      });
    } catch (e) {
      return json({ error: `Ephemeral key error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Delete Payment Method ─────────────────────────────────────

  if (action === "detach_payment_method") {
    const pmId = String(body.payment_method_id ?? "").trim();
    if (!pmId) return json({ error: "payment_method_id required" }, 400);

    try {
      const result = await stripeRequest(`/payment_methods/${pmId}/detach`, {});
      if (result.error) {
        const err = result.error as Record<string, unknown>;
        return json({ error: err.message ?? "Failed to remove card" }, 400);
      }
      return json({ success: true });
    } catch (e) {
      return json({ error: `Detach error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Create Payout (admin sends funds to connected account / bank) ──

  if (action === "create_payout") {
    // Verify the caller is an admin
    const { data: callerRow } = await adminClient
      .from("users")
      .select("role")
      .eq("id", userData.user.id)
      .single();

    if (!callerRow || callerRow.role !== "admin") {
      return json({ error: "Only admins can process payouts." }, 403);
    }

    const payoutId = String(body.payoutId ?? "").trim();
    const amount = Number(body.amount ?? 0);
    const currency = String(body.currency ?? "usd").trim().toLowerCase();
    const recipientName = String(body.recipientName ?? "").trim();
    const bankAccount = String(body.bankAccount ?? "").trim();
    const bankName = String(body.bankName ?? "").trim();
    const description = String(
      body.description ?? `Payout ${payoutId}`
    ).trim();

    if (!payoutId || amount <= 0) {
      return json(
        { error: "Missing required fields (payoutId, amount > 0)." },
        400
      );
    }

    const amountInCents = Math.round(amount * 100);

    try {
      // Use Stripe Transfers / Payouts API
      // For platforms: create a Transfer to the connected account
      // For direct payouts: create a Payout to the platform's bank
      const payoutResult = await stripeRequest("/payouts", {
        amount: String(amountInCents),
        currency,
        description,
        "metadata[payout_id]": payoutId,
        "metadata[recipient_name]": recipientName,
        "metadata[bank_account]": bankAccount,
        "metadata[bank_name]": bankName,
      });

      if (payoutResult.error) {
        const err = payoutResult.error as Record<string, unknown>;
        return json(
          {
            status: "failed",
            error: err.message ?? "Stripe payout failed.",
          },
          400
        );
      }

      return json({
        status: "success",
        payout_reference: payoutResult.id as string,
        stripe_status: payoutResult.status as string,
        amount,
        currency,
      });
    } catch (e) {
      return json(
        { status: "failed", error: `Stripe payout error: ${(e as Error).message}` },
        500
      );
    }
  }

  // ── Refund Payment (called when customer cancels a card order) ──

  if (action === "refund") {
    const orderId = String(body.orderId ?? "").trim();
    if (!orderId) {
      return json({ error: "orderId required" }, 400);
    }

    try {
      // Verify the order exists, belongs to the user, and is in a cancellable state
      const { data: order, error: orderErr } = await adminClient
        .from("orders")
        .select("id, user_id, status, payment_method, payment_status, total_amount, ordered_at")
        .eq("id", orderId)
        .single();

      if (orderErr || !order) {
        return json({ error: "Order not found" }, 404);
      }

      if (order.user_id !== userData.user.id) {
        return json({ error: "Not authorized to refund this order" }, 403);
      }

      if (order.status !== "cancelled") {
        return json({ error: "Order must be cancelled before refunding" }, 400);
      }

      if (order.payment_method !== "card") {
        return json({ error: "Only card payments can be refunded via Stripe" }, 400);
      }

      if (order.payment_status === "refunded") {
        return json({ error: "Already refunded" }, 400);
      }

      if (order.payment_status !== "completed") {
        return json({ error: "No completed payment to refund" }, 400);
      }

      // Calculate cancellation fee — same rules as cancel_order_with_penalty
      const orderedAt = new Date(order.ordered_at as string);
      const minutesPassed = (Date.now() - orderedAt.getTime()) / 60000;
      let cancellationFee = 0;
      if (minutesPassed >= 10) {
        cancellationFee = 1.50; // flat $1.50 after 10 minutes
      }

      const orderTotal = order.total_amount as number;
      const refundAmount = Math.max(orderTotal - cancellationFee, 0);

      if (refundAmount <= 0) {
        // Fee covers or exceeds total — no Stripe refund needed
        await adminClient.from("orders").update({
          payment_status: "refunded",
          updated_at: new Date().toISOString(),
        }).eq("id", orderId);
        return json({
          success: true,
          refund_amount: 0,
          cancellation_fee: cancellationFee,
          message: "No refund — cancellation fee covers total",
        });
      }

      // Look up the payment record to get the Stripe PaymentIntent ID
      const { data: payment, error: payErr } = await adminClient
        .from("payments")
        .select("transaction_id, status, amount")
        .eq("order_id", orderId)
        .eq("status", "completed")
        .single();

      if (payErr || !payment) {
        return json({ error: "No completed payment found for this order" }, 404);
      }

      const paymentIntentId = payment.transaction_id as string;
      if (!paymentIntentId) {
        return json({ error: "No Stripe payment intent on record" }, 400);
      }

      // Partial refund via Stripe — deduct cancellation fee, refund to original card
      const refundAmountCents = Math.round(refundAmount * 100);
      const refundParams: Record<string, string> = {
        payment_intent: paymentIntentId,
        amount: String(refundAmountCents),
      };
      const refund = await stripeRequest("/refunds", refundParams);

      if (refund.error) {
        const err = refund.error as Record<string, unknown>;
        return json({ error: err.message ?? "Refund failed" }, 400);
      }

      // Update payment record
      await adminClient
        .from("payments")
        .update({
          status: "refunded",
          metadata: {
            stripe_payment_intent_id: paymentIntentId,
            stripe_refund_id: refund.id,
            refunded_at: new Date().toISOString(),
          },
          updated_at: new Date().toISOString(),
        })
        .eq("order_id", orderId);

      // Update order payment_status
      await adminClient
        .from("orders")
        .update({
          payment_status: "refunded",
          updated_at: new Date().toISOString(),
        })
        .eq("id", orderId);

      return json({
        success: true,
        refund_id: refund.id,
        status: refund.status,
        refund_amount: refundAmount,
        cancellation_fee: cancellationFee,
        original_amount: orderTotal,
      });
    } catch (e) {
      return json({ error: `Refund error: ${(e as Error).message}` }, 500);
    }
  }

  return json({ error: `Unknown action: ${action}` }, 400);
});

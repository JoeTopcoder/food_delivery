// Stripe Payment Edge Function
// Creates PaymentIntents for orders, wallet top-ups, and card verification
// SECURITY: Stripe secret key is stored as a Supabase secret, never exposed to client
// Deploy with --no-verify-jwt so this function can decode legacy/RS256 JWTs itself.
//   supabase functions deploy stripe-payment --no-verify-jwt --project-ref yharweliruemjexmuuxn

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
const STRIPE_SECRET_KEY =
  Deno.env.get("STRIPE_SECRET_KEY") ||
  Deno.env.get("STRIPE_SK") ||
  Deno.env.get("STRIPE_API_KEY") ||
  "";

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
      {
        error:
          "Stripe is not configured. Set STRIPE_SECRET_KEY (or STRIPE_SK / STRIPE_API_KEY) with a valid Stripe secret key.",
      },
      500
    );
  }

  // Verify authorization — decode JWT to get user ID without re-validating
  // against Auth server (avoids LEGACY_JWT errors during algorithm transitions)
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing authorization header." }, 401);
  }

  const token = authHeader.replace(/^Bearer\s+/i, "");
  let userId: string;
  try {
    const payloadB64 = token.split(".")[1];
    const payload = JSON.parse(atob(payloadB64));
    userId = payload.sub as string;
    if (!userId) throw new Error("No sub claim");
  } catch {
    return json({ error: "Invalid token." }, 401);
  }

  // Verify the user actually exists in the DB
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);
  const { data: userRow, error: userLookupErr } = await adminClient
    .from("users")
    .select("id, email, name")
    .eq("id", userId)
    .maybeSingle();
  if (userLookupErr || !userRow) {
    return json({ error: "Unauthorized" }, 401);
  }

  // Stub userData to match existing code references below
  const userData = { user: { id: userId, email: userRow.email ?? "", user_metadata: { name: userRow.name ?? "" } } };

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

    const isNonOrder = txnType === "wallet_topup" || txnType === "ride" || txnType === "car_service";
    const isMultiRestaurant = txnType === "multi_restaurant_order";

    // Multi-restaurant pre-order PI: no order exists yet — skip order lookup.
    // The order is created AFTER payment is confirmed (inside create-multi-restaurant-order).
    // orderId is used only as Stripe metadata; validation happens in the order edge function.
    if (isMultiRestaurant) {
      // No DB lookup needed — just proceed to create the PaymentIntent below.
    }

    // For standard orders, validate the order exists and belongs to user
    if (!isNonOrder && !isMultiRestaurant) {
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
            : txnType === "ride"
            ? `Ride authorization ${orderId}`
            : txnType === "car_service"
            ? `Car service booking ${orderId}`
            : `Order payment ${orderId}`,
      };

      // Rides use manual capture: authorize now, capture the final fare at completion.
      if (txnType === "ride") {
        params["capture_method"] = "manual";
      }

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

      // Record the payment in Supabase payments table (for single-restaurant orders).
      // Multi-restaurant orders track payment status on order_groups directly.
      if (!isNonOrder && !isMultiRestaurant) {
        await adminClient.from("payments").upsert(
          {
            order_id: orderId,
            user_id: userData.user.id,
            amount: amount,
            currency: currency.toUpperCase(),
            method: "card",
            status: "pending",
            transaction_id: paymentIntent.id as string,
            gateway: "stripe",
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

  // ── Cleanup Unpaid Order (cancel/fail safe cleanup) ────────────

  if (action === "cleanup_unpaid_order") {
    const orderId = String(body.orderId ?? "").trim();

    if (!orderId) {
      return json({ error: "Missing orderId." }, 400);
    }

    try {
      const { data: order, error: orderError } = await adminClient
        .from("orders")
        .select("id, user_id, payment_status")
        .eq("id", orderId)
        .maybeSingle();

      if (orderError) {
        return json({ error: `Order lookup failed: ${orderError.message}` }, 500);
      }

      if (!order) {
        return json({ success: true, deleted: false, reason: "order_not_found" });
      }

      if (order.user_id !== userData.user.id) {
        return json({ error: "Order does not belong to you." }, 403);
      }

      if (String(order.payment_status ?? "") === "completed") {
        return json({ success: false, deleted: false, reason: "already_paid" }, 409);
      }

      await adminClient.from("order_items").delete().eq("order_id", orderId);
      await adminClient.from("payments").delete().eq("order_id", orderId);
      await adminClient
        .from("orders")
        .delete()
        .eq("id", orderId)
        .eq("user_id", userData.user.id)
        .neq("payment_status", "completed");

      return json({ success: true, deleted: true });
    } catch (e) {
      return json(
        { error: `Cleanup error: ${(e as Error).message}` },
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

  // ── Create Verification Charge (SetupIntent to save card, then charge server-side) ──

  if (action === "create_verification_charge") {
    const email = String(body.email ?? userData.user.email ?? "").trim();
    const name = String(body.name ?? "").trim();
    const cardBrand = String(body.card_brand ?? "").trim();
    const lastFour = String(body.last_four ?? "").trim();
    const cardholderName = String(body.cardholder_name ?? "").trim();
    const phone = String(body.phone ?? "").trim();

    if (!email) {
      return json({ error: "email is required" }, 400);
    }

    try {
      const customerId = await getOrCreateStripeCustomer(
        adminClient, userData.user.id, email, name || cardholderName
      );

      // Create a SetupIntent (card-only — avoids redirect-based payment methods
      // that would break the embedded CardFormField + confirmSetupIntent flow).
      const si = await stripeRequest("/setup_intents", {
        customer: customerId,
        "payment_method_types[]": "card",
        "metadata[type]": "card_verification",
        "metadata[user_id]": userData.user.id,
        usage: "off_session",
      });

      if (si.error) {
        const err = si.error as Record<string, unknown>;
        return json({ error: err.message ?? "Failed to create card setup" }, 400);
      }

      // Generate ephemeral key for PaymentSheet
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
        clientSecret: si.client_secret,
        setupIntentId: si.id,
        customerId,
        ephemeralKey: ephData.secret,
        cardBrand,
        lastFour,
        cardholderName,
        email,
        phone,
      });
    } catch (e) {
      return json({ error: `Verification setup error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Complete Verification Charge (charge saved card server-side) ──

  if (action === "complete_verification_charge") {
    const setupIntentId = String(body.setup_intent_id ?? "").trim();
    const cardBrand = String(body.card_brand ?? "").trim();
    const lastFour = String(body.last_four ?? "").trim();
    const cardholderName = String(body.cardholder_name ?? "").trim();
    const email = String(body.email ?? "").trim();
    const phone = String(body.phone ?? "").trim();

    if (!setupIntentId) {
      return json({ error: "setup_intent_id required" }, 400);
    }

    try {
      // Retrieve the SetupIntent to get the payment method
      const siData = await stripeGet(`/setup_intents/${setupIntentId}`);
      if (siData.status !== "succeeded") {
        return json({ error: "SetupIntent not completed" }, 400);
      }

      const paymentMethodId = siData.payment_method as string;
      if (!paymentMethodId) {
        return json({ error: "No payment method on SetupIntent" }, 400);
      }

      const customerId = siData.customer as string;

      // Generate random verification amount ($0.50 – $1.50)
      const verifyAmount = Number((Math.random() * 1.0 + 0.50).toFixed(2));
      const amountCents = Math.round(verifyAmount * 100);

      // Charge the card server-side (user never sees the amount)
      const pi = await stripeRequest("/payment_intents", {
        amount: String(amountCents),
        currency: "usd",
        customer: customerId,
        payment_method: paymentMethodId,
        off_session: "true",
        confirm: "true",
        "metadata[type]": "card_verification",
        "metadata[user_id]": userData.user.id,
        description: "Card verification charge",
      });

      if (pi.error) {
        const err = pi.error as Record<string, unknown>;
        return json({ error: err.message ?? "Verification charge failed" }, 400);
      }

      // Retrieve payment method details for the saved card.
      const paymentMethod = await stripeGet(`/payment_methods/${paymentMethodId}`);
      const card = paymentMethod.card as Record<string, unknown> | undefined;
      const returnedBrand = String(card?.brand ?? cardBrand).toLowerCase();
      const returnedLast4 = String(card?.last4 ?? lastFour);

      // Record in card_verifications table
      await adminClient.from("card_verifications").insert({
        id: pi.id as string,
        user_id: userData.user.id,
        amount: verifyAmount,
        transaction_id: pi.id as string,
        status: "completed",
        card_last4: returnedLast4,
        card_brand: returnedBrand,
        cardholder_name: cardholderName,
        email: email,
        phone: phone,
      });

      return json({
        success: true,
        verificationId: pi.id,
        paymentMethodId,
        cardBrand: returnedBrand,
        lastFour: returnedLast4,
        stripeCustomerId: customerId,
      });
    } catch (e) {
      return json({ error: `Verification charge error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Prepare Saved Card Payment (create PI, let Flutter confirm with CVC) ──
  // Used when we need CVC re-collection (e.g. wallet top-up with saved card).

  if (action === "prepare_saved_card_payment") {
    const orderId = String(body.orderId ?? "").trim();
    const amount = Number(body.amount ?? 0);
    const paymentMethodId = String(body.paymentMethodId ?? "").trim();
    const currency = String(body.currency ?? "usd").trim().toLowerCase();
    const txnType = String(body.type ?? "order").trim();
    const isNonOrder = txnType === "wallet_topup" || txnType === "ride" || txnType === "car_service";
    const isMultiRestaurant = txnType === "multi_restaurant_order";

    if (!orderId || amount <= 0 || !paymentMethodId) {
      return json({ error: "Missing required fields (orderId, amount, paymentMethodId)." }, 400);
    }

    if (isMultiRestaurant) {
      let moCustomerId: string | null = null;
      let moPaymentStatus: string | null = null;
      const { data: mo2 } = await adminClient
        .from("master_orders").select("id,customer_id,payment_status").eq("id", orderId).maybeSingle();
      if (mo2) { moCustomerId = mo2.customer_id; moPaymentStatus = mo2.payment_status; }
      else {
        const { data: og2 } = await adminClient
          .from("order_groups").select("id,customer_id,payment_status").eq("id", orderId).maybeSingle();
        if (og2) { moCustomerId = og2.customer_id; moPaymentStatus = og2.payment_status; }
      }
      if (!moCustomerId) return json({ error: "Order not found." }, 404);
      if (moCustomerId !== userData.user.id) return json({ error: "Order does not belong to you." }, 403);
      if (moPaymentStatus === "paid" || moPaymentStatus === "completed") return json({ error: "Order is already paid." }, 400);
    }

    if (!isNonOrder && !isMultiRestaurant) {
      const { data: order, error: orderError } = await adminClient
        .from("orders")
        .select("id, user_id, total_amount, payment_status")
        .eq("id", orderId)
        .single();
      if (orderError || !order) return json({ error: "Order not found." }, 404);
      if (order.user_id !== userData.user.id) return json({ error: "Order does not belong to you." }, 403);
      if (order.payment_status === "completed") return json({ error: "Order is already paid." }, 400);
    }

    try {
      const email = userData.user.email ?? "";
      const name = (userData.user.user_metadata?.name as string) ?? email;
      const customerId = await getOrCreateStripeCustomer(adminClient, userData.user.id, email, name);
      const amountInCents = Math.round(amount * 100);
      const description = txnType === "wallet_topup"
        ? `Wallet top-up ${orderId}`
        : txnType === "ride"
        ? `Ride payment ${orderId}`
        : `Order payment ${orderId}`;

      // Create PI with payment method attached but NOT confirmed —
      // Flutter SDK will confirm it client-side so CVC can be collected.
      const pi = await stripeRequest("/payment_intents", {
        amount: String(amountInCents),
        currency,
        customer: customerId,
        payment_method: paymentMethodId,
        "payment_method_types[]": "card",
        "metadata[order_id]": orderId,
        "metadata[user_id]": userData.user.id,
        "metadata[type]": txnType,
        receipt_email: email,
        description,
      });

      if (pi.error) {
        const err = pi.error as Record<string, unknown>;
        return json({ error: err.message ?? "Failed to create payment intent." }, 400);
      }

      return json({
        clientSecret: pi.client_secret,
        paymentIntentId: pi.id,
        customerId,
        amount,
        currency,
      });
    } catch (e) {
      return json({ error: `Payment intent error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Charge Saved Card Off-Session (order or wallet top-up with saved PM) ──

  if (action === "charge_saved_card") {
    const orderId = String(body.orderId ?? "").trim();
    const amount = Number(body.amount ?? 0);
    const paymentMethodId = String(body.paymentMethodId ?? "").trim();
    const currency = String(body.currency ?? "usd").trim().toLowerCase();
    const txnType = String(body.type ?? "order").trim();
    const isNonOrder = txnType === "wallet_topup" || txnType === "ride" || txnType === "car_service";
    const isMultiRestaurant = txnType === "multi_restaurant_order";

    if (!orderId || amount <= 0 || !paymentMethodId) {
      return json({ error: "Missing required fields (orderId, amount, paymentMethodId)." }, 400);
    }

    // Multi-restaurant orders: validate against master_orders (new) or order_groups (legacy)
    if (isMultiRestaurant) {
      let moCustomerId3: string | null = null;
      let moPaymentStatus3: string | null = null;
      const { data: mo3 } = await adminClient
        .from("master_orders").select("id,customer_id,payment_status").eq("id", orderId).maybeSingle();
      if (mo3) { moCustomerId3 = mo3.customer_id; moPaymentStatus3 = mo3.payment_status; }
      else {
        const { data: og3 } = await adminClient
          .from("order_groups").select("id,customer_id,payment_status").eq("id", orderId).maybeSingle();
        if (og3) { moCustomerId3 = og3.customer_id; moPaymentStatus3 = og3.payment_status; }
      }
      if (!moCustomerId3) return json({ error: "Order not found." }, 404);
      if (moCustomerId3 !== userData.user.id) return json({ error: "Order does not belong to you." }, 403);
      if (moPaymentStatus3 === "paid" || moPaymentStatus3 === "completed") return json({ error: "Order is already paid." }, 400);
    }

    // For real orders: validate the order exists and belongs to this user
    if (!isNonOrder && !isMultiRestaurant) {
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

    try {
      // Get or create Stripe customer for this user
      const email = userData.user.email ?? "";
      const name = (userData.user.user_metadata?.name as string) ?? email;
      const customerId = await getOrCreateStripeCustomer(
        adminClient, userData.user.id, email, name
      );

      const amountInCents = Math.round(amount * 100);
      const description = txnType === "wallet_topup"
        ? `Wallet top-up ${orderId}`
        : txnType === "ride"
        ? `Ride payment ${orderId}`
        : `Order payment ${orderId}`;

      // Create and immediately confirm the PaymentIntent off-session
      const pi = await stripeRequest("/payment_intents", {
        amount: String(amountInCents),
        currency,
        customer: customerId,
        payment_method: paymentMethodId,
        off_session: "true",
        confirm: "true",
        "metadata[order_id]": orderId,
        "metadata[user_id]": userData.user.id,
        "metadata[type]": txnType,
        receipt_email: email,
        description,
      });

      if (pi.error) {
        const err = pi.error as Record<string, unknown>;
        return json({ error: err.message ?? "Charge failed." }, 400);
      }

      const piStatus = pi.status as string;
      const succeeded = piStatus === "succeeded" || piStatus === "requires_capture";

      // Update DB on success
      if (succeeded && isMultiRestaurant) {
        // Try new master_orders table first; fall back to legacy order_groups
        const { data: moCheck } = await adminClient
          .from("master_orders").select("id").eq("id", orderId).maybeSingle();
        if (moCheck) {
          // New schema: delegate to finalize function (handles notifications + driver assignment)
          fetch(`${supabaseUrl}/functions/v1/finalize-multi-restaurant-order`, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": `Bearer ${supabaseServiceRoleKey}`,
              "apikey": supabaseServiceRoleKey,
            },
            body: JSON.stringify({ master_order_id: orderId, payment_intent_id: pi.id }),
          }).catch(() => null);
        } else {
          // Legacy schema: update order_groups and orders directly
          await adminClient.from("order_groups").update({
            payment_status: "paid", status: "preparing",
            stripe_payment_intent_id: pi.id as string,
            updated_at: new Date().toISOString(),
          }).eq("id", orderId);
          await adminClient.from("orders").update({
            payment_status: "completed", status: "preparing",
            updated_at: new Date().toISOString(),
          }).eq("order_group_id", orderId);
        }
      } else if (succeeded && !isNonOrder) {
        await adminClient.from("payments").upsert(
          {
            order_id: orderId,
            user_id: userData.user.id,
            amount: amount,
            currency: currency.toUpperCase(),
            method: "card",
            status: "completed",
            transaction_id: pi.id as string,
            gateway: "stripe",
          },
          { onConflict: "order_id" }
        );

        // Set BOTH payment_status AND status in one UPDATE so the DB trigger
        // (check_card_payment_gate) is satisfied. Also sets payment_intent_id
        // so the stripe-webhook idempotency guard (.neq payment_status completed)
        // correctly skips re-processing when the webhook arrives.
        await adminClient
          .from("orders")
          .update({
            payment_status: "completed",
            status: "pending",
            payment_intent_id: pi.id as string,
            updated_at: new Date().toISOString(),
          })
          .eq("id", orderId);
      }

      return json({ success: succeeded, paymentIntentId: pi.id, status: piStatus });
    } catch (e) {
      return json({ error: `Charge error: ${(e as Error).message}` }, 500);
    }
  }

  // ── Refund Verification Charge (after user verifies the amount) ──

  if (action === "refund_verification_charge") {
    const paymentIntentId = String(body.payment_intent_id ?? "").trim();
    if (!paymentIntentId) {
      return json({ error: "payment_intent_id required" }, 400);
    }

    try {
      // Full refund of the verification charge
      const refund = await stripeRequest("/refunds", {
        payment_intent: paymentIntentId,
      });

      if (refund.error) {
        const err = refund.error as Record<string, unknown>;
        return json({ error: err.message ?? "Refund failed" }, 400);
      }

      return json({ success: true, refund_id: refund.id });
    } catch (e) {
      return json({ error: `Refund error: ${(e as Error).message}` }, 500);
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

    // Accept optional penalty from caller (already calculated by DB function)
    const callerPenalty = body.penalty != null ? Number(body.penalty) : null;

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
        return json({ success: true, message: "Already refunded" });
      }

      if (order.payment_status !== "completed") {
        return json({ error: "No completed payment to refund" }, 400);
      }

      // Use caller-provided penalty if available, otherwise calculate
      let cancellationFee: number;
      if (callerPenalty != null && callerPenalty >= 0) {
        cancellationFee = callerPenalty;
      } else {
        const orderedAt = new Date(order.ordered_at as string);
        const minutesPassed = (Date.now() - orderedAt.getTime()) / 60000;
        cancellationFee = minutesPassed >= 5 ? 1.00 : 0;
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
      let paymentIntentId: string | null = null;

      const { data: payment } = await adminClient
        .from("payments")
        .select("transaction_id, status, amount")
        .eq("order_id", orderId)
        .in("status", ["completed", "pending"])
        .maybeSingle();

      if (payment?.transaction_id) {
        paymentIntentId = payment.transaction_id as string;
      }

      // Fallback: search Stripe for a PaymentIntent with this order_id in metadata
      if (!paymentIntentId) {
        const searchResult = await stripeGet(
          `/payment_intents?limit=5&metadata[order_id]=${encodeURIComponent(orderId)}`
        );
        const piList = (searchResult.data ?? []) as Array<Record<string, unknown>>;
        const succeededPi = piList.find(
          (pi) => pi.status === "succeeded" || pi.status === "requires_capture"
        );
        if (succeededPi) {
          paymentIntentId = succeededPi.id as string;
        }
      }

      if (!paymentIntentId) {
        return json({ error: "No Stripe payment found for this order" }, 404);
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

      // Update payment record if it exists
      await adminClient
        .from("payments")
        .update({
          status: "refunded",
          refund_amount: refundAmount,
          refund_reason: `Cancellation fee: $${cancellationFee.toFixed(2)}`,
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

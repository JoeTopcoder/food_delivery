// create-subscription — Creates a Stripe subscription for MealHub Basic/Pro plans
// Deploy: supabase functions deploy create-subscription --no-verify-jwt

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";

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

async function stripePost(
  endpoint: string,
  params: Record<string, string>
): Promise<Record<string, unknown>> {
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: new URLSearchParams(params).toString(),
  });
  return (await res.json()) as Record<string, unknown>;
}

async function stripeEphemeralKey(
  customerId: string
): Promise<string | null> {
  const res = await fetch("https://api.stripe.com/v1/ephemeral_keys", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
      "Content-Type": "application/x-www-form-urlencoded",
      "Stripe-Version": "2024-06-20",
    },
    body: new URLSearchParams({ customer: customerId }).toString(),
  });
  const data = (await res.json()) as Record<string, unknown>;
  return (data.secret as string) ?? null;
}

async function stripeGet(endpoint: string): Promise<Record<string, unknown>> {
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "GET",
    headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
  });
  return (await res.json()) as Record<string, unknown>;
}

async function getConfig(
  admin: ReturnType<typeof createClient>,
  key: string,
  fallback: string
): Promise<string> {
  const { data } = await admin
    .from("app_config")
    .select("value")
    .eq("key", key)
    .maybeSingle();
  return data?.value ?? fallback;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!STRIPE_SECRET_KEY) {
    return json({ error: "Stripe not configured." }, 500);
  }

  // ── Auth — decode JWT directly to avoid LEGACY_JWT from getUser() ────────
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing authorization." }, 401);

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

  const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

  const { data: userRow, error: userLookupErr } = await admin
    .from("users")
    .select("id, email, name")
    .eq("id", userId)
    .maybeSingle();
  if (userLookupErr || !userRow) return json({ error: "Unauthorized" }, 401);

  const user = { id: userId, email: userRow.email ?? "", user_metadata: { name: userRow.name ?? "" } };

  // ── Parse body ─────────────────────────────────────────────────────────────
  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const action = String(body.action ?? "subscribe").trim();

  // ════════════════════════════════════════════════════════════════════════════
  // ACTION: subscribe — create a new Stripe subscription
  // ════════════════════════════════════════════════════════════════════════════
  if (action === "subscribe") {
    const planType = String(body.plan ?? "").trim().toLowerCase();
    if (planType !== "basic" && planType !== "pro") {
      return json({ error: 'plan must be "basic" or "pro"' }, 400);
    }

    // Check if user already has active subscription
    const { data: existing } = await admin
      .from("user_subscriptions")
      .select("id, plan_type, status")
      .eq("user_id", user.id)
      .eq("status", "active")
      .maybeSingle();

    if (existing) {
      return json(
        {
          error: `You already have an active ${existing.plan_type} subscription.`,
          existing_plan: existing.plan_type,
        },
        409
      );
    }

    // Clean up any stale pending subscriptions from previous failed attempts
    await admin
      .from("user_subscriptions")
      .delete()
      .eq("user_id", user.id)
      .eq("status", "pending");

    // ── Load plan config ─────────────────────────────────────────────────────
    const price =
      planType === "basic"
        ? await getConfig(admin, "subscription_basic_price", "12.00")
        : await getConfig(admin, "subscription_pro_price", "24.00");
    const deliveries =
      planType === "basic"
        ? await getConfig(admin, "subscription_basic_deliveries", "9")
        : await getConfig(admin, "subscription_pro_deliveries", "22");
    const serviceFeeDiscount = await getConfig(
      admin,
      "subscription_service_fee_discount",
      "0.50"
    );

    const priceInCents = Math.round(parseFloat(price) * 100);
    const email = user.email ?? "";
    const name =
      (user.user_metadata?.name as string) ?? (user.email ?? "Customer");

    // ── Find or create Stripe customer ───────────────────────────────────────
    let stripeCustomerId: string | null = null;

    // Check existing subscription records for a stripe_customer_id
    const { data: prevSub } = await admin
      .from("user_subscriptions")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .not("stripe_customer_id", "is", null)
      .limit(1)
      .maybeSingle();

    if (prevSub?.stripe_customer_id) {
      stripeCustomerId = prevSub.stripe_customer_id;
    } else {
      // Create new Stripe customer
      const customer = await stripePost("/customers", {
        email,
        name,
        "metadata[user_id]": user.id,
        "metadata[source]": "mealhub_subscription",
      });
      if (customer.error) {
        const err = customer.error as Record<string, unknown>;
        return json(
          { error: err.message ?? "Failed to create Stripe customer" },
          400
        );
      }
      stripeCustomerId = customer.id as string;
    }

    // ── Create a PaymentIntent directly — no subscription/invoice chain ────────
    const pi = await stripePost("/payment_intents", {
      amount: String(priceInCents),
      currency: "usd",
      customer: stripeCustomerId,
      "payment_method_types[0]": "card",
      "metadata[user_id]": user.id,
      "metadata[plan_type]": planType,
      "metadata[action]": "subscribe",
    });

    if (pi.error) {
      const err = pi.error as Record<string, unknown>;
      return json({ error: err.message ?? "Failed to create payment" }, 400);
    }

    const clientSecret = pi.client_secret as string;
    if (!clientSecret) {
      return json({ error: "No client secret from PaymentIntent" }, 500);
    }

    // ── Insert pending subscription row ──────────────────────────────────────
    const now = new Date();
    const periodEnd = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000);

    const { data: subRow, error: insertErr } = await admin
      .from("user_subscriptions")
      .insert({
        user_id: user.id,
        meal_plan_id: null,
        plan_type: planType,
        status: "pending",
        stripe_customer_id: stripeCustomerId,
        // Store PI ID so activate can verify payment before marking active
        stripe_subscription_id: pi.id as string,
        current_period_end: periodEnd.toISOString(),
        deliveries_remaining: parseInt(deliveries),
        deliveries_used: 0,
        service_fee_discount: parseFloat(serviceFeeDiscount),
        start_date: now.toISOString().split("T")[0],
        meals_remaining: parseInt(deliveries),
        auto_renew: true,
      })
      .select()
      .single();

    if (insertErr) {
      return json(
        { error: "Failed to save subscription", detail: insertErr.message },
        500
      );
    }

    const ephemeralKey = await stripeEphemeralKey(stripeCustomerId!);

    return json({
      subscription_id: subRow.id,
      client_secret: clientSecret,
      customer_id: stripeCustomerId,
      ephemeral_key: ephemeralKey,
      plan_type: planType,
      price: parseFloat(price),
      deliveries: parseInt(deliveries),
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ACTION: cancel — cancel an active subscription
  // ════════════════════════════════════════════════════════════════════════════
  if (action === "cancel") {
    const subscriptionId = String(body.subscription_id ?? "").trim();
    if (!subscriptionId) {
      return json({ error: "subscription_id required" }, 400);
    }

    const { data: sub } = await admin
      .from("user_subscriptions")
      .select("id, stripe_subscription_id, user_id")
      .eq("id", subscriptionId)
      .single();

    if (!sub || sub.user_id !== user.id) {
      return json({ error: "Subscription not found" }, 404);
    }

    // Cancel in Stripe at period end — user keeps benefits until then
    if (sub.stripe_subscription_id) {
      await stripePost(`/subscriptions/${sub.stripe_subscription_id}`, {
        cancel_at_period_end: "true",
      });
    }

    // Keep status 'active' so user retains benefits until period end.
    // Stripe will fire customer.subscription.deleted at period end → webhook sets cancelled.
    await admin
      .from("user_subscriptions")
      .update({ auto_renew: false, updated_at: new Date().toISOString() })
      .eq("id", subscriptionId);

    return json({
      success: true,
      message: "Subscription will cancel at end of billing period",
      cancel_at_period_end: true,
    });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ACTION: reactivate — undo a pending cancellation before period ends
  // ════════════════════════════════════════════════════════════════════════════
  if (action === "reactivate") {
    const subscriptionId = String(body.subscription_id ?? "").trim();
    if (!subscriptionId) {
      return json({ error: "subscription_id required" }, 400);
    }

    const { data: sub } = await admin
      .from("user_subscriptions")
      .select("id, stripe_subscription_id, user_id, auto_renew")
      .eq("id", subscriptionId)
      .single();

    if (!sub || sub.user_id !== user.id) {
      return json({ error: "Subscription not found" }, 404);
    }

    // Remove cancel_at_period_end in Stripe
    if (sub.stripe_subscription_id) {
      await stripePost(`/subscriptions/${sub.stripe_subscription_id}`, {
        cancel_at_period_end: "false",
      });
    }

    await admin
      .from("user_subscriptions")
      .update({ auto_renew: true, updated_at: new Date().toISOString() })
      .eq("id", subscriptionId);

    return json({ success: true, message: "Subscription reactivated" });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ACTION: status — get current subscription status
  // ════════════════════════════════════════════════════════════════════════════
  if (action === "status") {
    const { data: sub } = await admin
      .from("user_subscriptions")
      .select("*")
      .eq("user_id", user.id)
      .in("status", ["active", "pending"])
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    return json({ subscription: sub ?? null });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ACTION: activate — verify payment then mark subscription active
  // ════════════════════════════════════════════════════════════════════════════
  if (action === "activate") {
    const subscriptionId = String(body.subscription_id ?? "").trim();
    if (!subscriptionId) {
      return json({ error: "subscription_id required" }, 400);
    }

    const { data: sub } = await admin
      .from("user_subscriptions")
      .select("id, user_id, status, stripe_subscription_id, stripe_customer_id, plan_type")
      .eq("id", subscriptionId)
      .single();

    if (!sub || sub.user_id !== user.id) {
      return json({ error: "Subscription not found" }, 404);
    }

    // stripe_subscription_id stores the PaymentIntent ID (pi_xxx) for PI-based
    // subscriptions. Verify it's succeeded before activating.
    const storedId = sub.stripe_subscription_id as string | null;
    if (storedId?.startsWith("pi_")) {
      const pi = await stripeGet(`/payment_intents/${storedId}`);
      if ((pi.status as string) !== "succeeded") {
        return json(
          { error: "Payment has not been completed. Please complete payment to activate your subscription." },
          402
        );
      }

      const piMeta = (pi.metadata ?? {}) as Record<string, string>;
      const piAction = piMeta.action ?? "";

      if (piAction === "change_plan") {
        // Plan-change payment confirmed — update plan details now.
        const newPlan = piMeta.plan_type ?? sub.plan_type;
        const newDeliveries = parseInt(piMeta.new_deliveries ?? "0");
        const svcDiscount = parseFloat(piMeta.service_fee_discount ?? "0.5");

        await admin
          .from("user_subscriptions")
          .update({
            plan_type: newPlan,
            status: "active",
            deliveries_remaining: newDeliveries,
            deliveries_used: 0,
            service_fee_discount: svcDiscount,
            current_period_end: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
            auto_renew: true,
            stripe_subscription_id: null,
            updated_at: new Date().toISOString(),
          })
          .eq("id", subscriptionId);

        return json({ success: true, message: "Plan changed successfully" });
      }
    }

    // Normal subscribe activation (or already active)
    if (sub.status === "active") {
      return json({ success: true, message: "Already active" });
    }

    await admin
      .from("user_subscriptions")
      .update({
        status: "active",
        auto_renew: true,
        current_period_end: new Date(Date.now() + 30 * 24 * 60 * 60 * 1000).toISOString(),
        stripe_subscription_id: null,
        updated_at: new Date().toISOString(),
      })
      .eq("id", subscriptionId);

    return json({ success: true, message: "Subscription activated" });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ACTION: delete_pending — remove a pending subscription (cancelled payment)
  // ════════════════════════════════════════════════════════════════════════════
  if (action === "delete_pending") {
    const subscriptionId = String(body.subscription_id ?? "").trim();
    if (subscriptionId) {
      await admin
        .from("user_subscriptions")
        .delete()
        .eq("id", subscriptionId)
        .eq("user_id", user.id)
        .eq("status", "pending");
    } else {
      await admin
        .from("user_subscriptions")
        .delete()
        .eq("user_id", user.id)
        .eq("status", "pending");
    }
    return json({ success: true });
  }

  // ════════════════════════════════════════════════════════════════════════════
  // ACTION: change_plan — switch between Basic ↔ Pro
  // ════════════════════════════════════════════════════════════════════════════
  if (action === "change_plan") {
    const subscriptionId = String(body.subscription_id ?? "").trim();
    const newPlan = String(body.plan ?? "").trim().toLowerCase();

    if (!subscriptionId) return json({ error: "subscription_id required" }, 400);
    if (newPlan !== "basic" && newPlan !== "pro") {
      return json({ error: 'plan must be "basic" or "pro"' }, 400);
    }

    const { data: sub } = await admin
      .from("user_subscriptions")
      .select("id, user_id, plan_type, status, stripe_subscription_id")
      .eq("id", subscriptionId)
      .single();

    if (!sub || sub.user_id !== user.id) {
      return json({ error: "Subscription not found" }, 404);
    }
    if (sub.status !== "active") {
      return json({ error: "Only active subscriptions can be changed" }, 400);
    }
    if (sub.plan_type === newPlan) {
      return json({ error: `Already on ${newPlan} plan` }, 409);
    }

    // Load new plan config
    const newPrice =
      newPlan === "basic"
        ? await getConfig(admin, "subscription_basic_price", "12.00")
        : await getConfig(admin, "subscription_pro_price", "24.00");
    const newDeliveries =
      newPlan === "basic"
        ? await getConfig(admin, "subscription_basic_deliveries", "9")
        : await getConfig(admin, "subscription_pro_deliveries", "22");
    const serviceFeeDiscount = await getConfig(
      admin,
      "subscription_service_fee_discount",
      "0.50"
    );

    // Cancel old Stripe subscription immediately
    if (sub.stripe_subscription_id) {
      await fetch(`https://api.stripe.com/v1/subscriptions/${sub.stripe_subscription_id}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` },
      }).catch(() => {});
    }

    const newPriceInCents = Math.round(parseFloat(newPrice) * 100);
    const email = user.email ?? "";
    const name = (user.user_metadata?.name as string) ?? email;

    // Find or create Stripe customer
    let customerId = "";
    const { data: prevSub } = await admin
      .from("user_subscriptions")
      .select("stripe_customer_id")
      .eq("user_id", user.id)
      .not("stripe_customer_id", "is", null)
      .limit(1)
      .maybeSingle();
    if (prevSub?.stripe_customer_id) {
      customerId = prevSub.stripe_customer_id;
    } else {
      const cust = await stripePost("/customers", {
        email,
        name,
        "metadata[user_id]": user.id,
      });
      customerId = cust.id as string;
    }

    // Create a PaymentIntent — embed all plan-change details in metadata so
    // activate() can apply them after verifying payment, without touching the
    // DB before the user actually pays.
    const pi = await stripePost("/payment_intents", {
      amount: String(newPriceInCents),
      currency: "usd",
      customer: customerId,
      "payment_method_types[0]": "card",
      "metadata[user_id]": user.id,
      "metadata[plan_type]": newPlan,
      "metadata[action]": "change_plan",
      "metadata[subscription_id]": subscriptionId,
      "metadata[new_deliveries]": newDeliveries,
      "metadata[service_fee_discount]": serviceFeeDiscount,
    });

    if (pi.error) {
      const err = pi.error as Record<string, unknown>;
      return json({ error: err.message ?? "Failed to create payment" }, 400);
    }

    const clientSecret = pi.client_secret as string;
    if (!clientSecret) {
      return json({ error: "No client secret from PaymentIntent" }, 500);
    }

    const ephemeralKey = await stripeEphemeralKey(customerId);

    // Only store the PI ID on the subscription — do NOT change status or plan_type
    // until payment is confirmed in the activate action.
    await admin
      .from("user_subscriptions")
      .update({
        stripe_customer_id: customerId,
        stripe_subscription_id: pi.id as string,
        updated_at: new Date().toISOString(),
      })
      .eq("id", subscriptionId);

    return json({
      subscription_id: subscriptionId,
      client_secret: clientSecret,
      customer_id: customerId,
      ephemeral_key: ephemeralKey,
      plan_type: newPlan,
      price: parseFloat(newPrice),
      deliveries: parseInt(newDeliveries),
    });
  }

  return json({ error: `Unknown action: ${action}` }, 400);
});

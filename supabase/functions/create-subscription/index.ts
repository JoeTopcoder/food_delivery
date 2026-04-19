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

  // ── Auth ───────────────────────────────────────────────────────────────────
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing authorization." }, 401);

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

  const {
    data: { user },
    error: authErr,
  } = await userClient.auth.getUser();
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

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

    // ── Create a Stripe Price (ad-hoc) for recurring billing ─────────────────
    const stripePrice = await stripePost("/prices", {
      currency: "usd",
      unit_amount: String(priceInCents),
      "recurring[interval]": "month",
      "product_data[name]": `MealHub ${planType === "basic" ? "Basic" : "Pro"}`,
      "product_data[metadata][plan_type]": planType,
    });

    if (stripePrice.error) {
      const err = stripePrice.error as Record<string, unknown>;
      return json(
        { error: err.message ?? "Failed to create price" },
        400
      );
    }

    // ── Create Stripe Subscription with payment ──────────────────────────────
    const subscription = await stripePost("/subscriptions", {
      customer: stripeCustomerId,
      "items[0][price]": stripePrice.id as string,
      payment_behavior: "default_incomplete",
      "payment_settings[save_default_payment_method]": "on_subscription",
      "expand[0]": "latest_invoice.payment_intent",
      "metadata[user_id]": user.id,
      "metadata[plan_type]": planType,
      "metadata[deliveries]": deliveries,
    });

    if (subscription.error) {
      const err = subscription.error as Record<string, unknown>;
      return json(
        { error: err.message ?? "Failed to create subscription" },
        400
      );
    }

    const invoice = subscription.latest_invoice as Record<string, unknown>;
    const paymentIntent = invoice?.payment_intent as Record<string, unknown>;
    const clientSecret = paymentIntent?.client_secret as string | null;

    if (!clientSecret) {
      return json({ error: "No client secret returned from Stripe" }, 500);
    }

    // ── Insert pending subscription row ──────────────────────────────────────
    const now = new Date();
    const periodEnd = new Date(
      ((subscription.current_period_end as number) ?? 0) * 1000
    );

    const { data: subRow, error: insertErr } = await admin
      .from("user_subscriptions")
      .insert({
        user_id: user.id,
        meal_plan_id: null, // Not tied to a meal plan — it's a delivery subscription
        plan_type: planType,
        status: "pending", // Will become 'active' when Stripe confirms payment
        stripe_subscription_id: subscription.id,
        stripe_customer_id: stripeCustomerId,
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

    return json({
      subscription_id: subRow.id,
      stripe_subscription_id: subscription.id,
      client_secret: clientSecret,
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

  return json({ error: `Unknown action: ${action}` }, 400);
});

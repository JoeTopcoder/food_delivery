// @ts-nocheck
// stripe-connect/index.ts
// Creates a Stripe Connect Custom account for a driver and attaches a debit card for payouts.
// Drivers enter their card in-app (flutter_stripe tokenises client-side); no redirect required.
// SECURITY: All Stripe calls via server-side only. Auth verified before any action.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const APP_BASE_URL = Deno.env.get("APP_BASE_URL") ?? "https://mealhub.app";
const STRIPE_CONNECT_COUNTRY = Deno.env.get("STRIPE_CONNECT_COUNTRY") ?? "US";

function json(body: unknown, status = 200) {
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
  return res.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // --- Auth ---
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  const userClient = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    global: { headers: { Authorization: authHeader } },
  });
  const { data: { user }, error: authErr } = await userClient.auth.getUser();
  if (authErr || !user) return json({ error: "Unauthorized" }, 401);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  if (!STRIPE_SECRET_KEY) {
    return json({ error: "Stripe is not configured on server (missing STRIPE_SECRET_KEY)." }, 500);
  }

  const body = await req.json().catch(() => ({}));
  const action = body.action ?? "add_card"; // 'add_card' | 'status'

  // --- Fetch driver record ---
  const { data: driver, error: driverErr } = await adminClient
    .from("drivers")
    .select("id, stripe_account_id, payouts_enabled, stripe_account_status")
    .eq("user_id", user.id)
    .single();

  if (driverErr || !driver) {
    return json({ error: "Driver record not found" }, 404);
  }

  if (action === "status") {
    return json({
      stripe_account_id: driver.stripe_account_id,
      payouts_enabled: driver.payouts_enabled,
      stripe_account_status: driver.stripe_account_status,
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // action === "add_card"
  // Expects: { action: "add_card", token: "tok_xxxx", name: "Driver Name" }
  // Creates a Custom Connected Account (if needed) and attaches the card.
  // ─────────────────────────────────────────────────────────────────────────

  if (action !== "add_card") {
    return json({ error: `Unknown action: ${action}` }, 400);
  }

  const cardToken = body.token as string | undefined;
  if (!cardToken || !cardToken.startsWith("tok_")) {
    return json({ error: "A valid Stripe card token (tok_…) is required." }, 400);
  }

  let stripeAccountId: string = driver.stripe_account_id ?? "";

  // --- Create Custom account if not yet done ---
  if (!stripeAccountId) {
    const { data: profile } = await adminClient
      .from("user_profiles")
      .select("full_name, email")
      .eq("user_id", user.id)
      .single();

    const clientIp =
      req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "127.0.0.1";

    const account = await stripePost("/accounts", {
      type: "custom",
      country: STRIPE_CONNECT_COUNTRY,
      email: profile?.email ?? user.email ?? "",
      "capabilities[transfers][requested]": "true",
      business_type: "individual",
      "tos_acceptance[date]": String(Math.floor(Date.now() / 1000)),
      "tos_acceptance[ip]": clientIp,
    });

    if ((account as any).error) {
      const stripeErr = (account as any).error;
      const stripeMsg = String(stripeErr.message ?? "Unknown Stripe error");
      console.error("[stripe-connect] account create failed", stripeErr);

      if (stripeMsg.toLowerCase().includes("signed up for connect")) {
        return json(
          {
            error:
              "Stripe Connect is not enabled on your Stripe account yet. In Stripe Dashboard → Connect, activate the platform first, then try again.",
          },
          502
        );
      }

      return json({ error: `Stripe account creation failed: ${stripeMsg}` }, 502);
    }

    stripeAccountId = (account as any).id;

    await adminClient
      .from("drivers")
      .update({
        stripe_account_id: stripeAccountId,
        stripe_account_status: "pending",
        updated_at: new Date().toISOString(),
      })
      .eq("id", driver.id);
  }

  // --- Attach card as external payout account ---
  const extAccount = await stripePost(
    `/accounts/${stripeAccountId}/external_accounts`,
    {
      external_account: cardToken,
      default_for_currency: "true",
    }
  );

  if ((extAccount as any).error) {
    const errMsg = String((extAccount as any).error.message ?? "Unknown error");
    console.error("[stripe-connect] card attachment failed", (extAccount as any).error);

    if (errMsg.toLowerCase().includes("debit card")) {
      return json(
        { error: "Only debit cards are accepted for instant payouts. Please use a Visa or Mastercard debit card." },
        422
      );
    }

    return json({ error: `Card could not be added: ${errMsg}` }, 502);
  }

  // --- Mark driver as active with card ---
  await adminClient
    .from("drivers")
    .update({
      stripe_account_id: stripeAccountId,
      payouts_enabled: true,
      stripe_account_status: "active",
      stripe_debit_card_added: true,
      updated_at: new Date().toISOString(),
    })
    .eq("id", driver.id);

  return json({
    success: true,
    stripe_account_id: stripeAccountId,
    external_account_id: (extAccount as any).id,
    last4: (extAccount as any).last4 ?? null,
  });
});

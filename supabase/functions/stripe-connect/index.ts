// @ts-nocheck
// stripe-connect/index.ts
// Creates a Stripe Connect Express account for a driver and returns an onboarding URL.
// SECURITY: All Stripe calls via server-side only. JWT verified before any action.

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

  const body = await req.json().catch(() => ({}));
  const action = body.action ?? "onboard"; // 'onboard' | 'status'

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

  // --- Create Connect account if not exists ---
  let stripeAccountId: string = driver.stripe_account_id;

  if (!stripeAccountId) {
    const { data: profile } = await adminClient
      .from("user_profiles")
      .select("full_name, email, phone")
      .eq("user_id", user.id)
      .single();

    const account = await stripePost("/accounts", {
      type: "express",
      country: "US",
      email: profile?.email ?? user.email ?? "",
      "capabilities[transfers][requested]": "true",
      "capabilities[card_payments][requested]": "true",
      "business_type": "individual",
      "settings[payouts][schedule][interval]": "manual",
    });

    if ((account as any).error) {
      return json(
        { error: `Stripe error: ${(account as any).error.message}` },
        502
      );
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

  // --- Generate onboarding link ---
  const returnUrl = `${APP_BASE_URL}/stripe-return?driver_id=${driver.id}`;
  const refreshUrl = `${APP_BASE_URL}/stripe-refresh?driver_id=${driver.id}`;

  const link = await stripePost("/account_links", {
    account: stripeAccountId,
    refresh_url: refreshUrl,
    return_url: returnUrl,
    type: "account_onboarding",
  });

  if ((link as any).error) {
    return json(
      { error: `Stripe link error: ${(link as any).error.message}` },
      502
    );
  }

  return json({ url: (link as any).url, stripe_account_id: stripeAccountId });
});

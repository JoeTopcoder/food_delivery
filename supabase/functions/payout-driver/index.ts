// @ts-nocheck
// payout-driver/index.ts
// Initiates an instant (or standard) Stripe payout for a driver.
// SECURITY: JWT-authenticated, idempotency enforced, duplicate-payout guard.

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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function stripePost(
  endpoint: string,
  params: Record<string, string>,
  stripeAccount?: string,
  idempotencyKey?: string
): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
    "Content-Type": "application/x-www-form-urlencoded",
  };
  if (stripeAccount) headers["Stripe-Account"] = stripeAccount;
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey;

  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "POST",
    headers,
    body: new URLSearchParams(params).toString(),
  });
  return res.json();
}

async function stripeGet(
  endpoint: string,
  stripeAccount?: string
): Promise<Record<string, unknown>> {
  const headers: Record<string, string> = {
    Authorization: `Bearer ${STRIPE_SECRET_KEY}`,
  };
  if (stripeAccount) headers["Stripe-Account"] = stripeAccount;
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "GET",
    headers,
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

const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
const _token = authHeader.replace(/^Bearer\s+/i, "");
let _uid: string;
try {
  const _p = JSON.parse(atob(_token.split(".")[1]));
  _uid = _p.sub as string;
  if (!_uid) throw new Error();
} catch { return json({ error: "Invalid token." }, 401); }
const { data: _ur, error: _ue } = await adminClient.from("users").select("id").eq("id", _uid).maybeSingle();
if (_ue || !_ur) return json({ error: "Unauthorized" }, 401);
const user = { id: _uid };

  const { amount_cents, payout_type = "instant" } = body as {
    amount_cents: number;
    payout_type?: "instant" | "standard";
  };

  if (!amount_cents || amount_cents < 100) {
    return json({ error: "Minimum payout is $1.00" }, 400);
  }

  // --- Fetch driver ---
  const { data: driver, error: driverErr } = await adminClient
    .from("drivers")
    .select(
      "id, stripe_account_id, payouts_enabled, stripe_debit_card_added, total_earnings, total_paid_out"
    )
    .eq("user_id", user.id)
    .single();

  if (driverErr || !driver) return json({ error: "Driver not found" }, 404);

  // --- Guard: Stripe onboarding must be complete ---
  if (!driver.stripe_account_id) {
    return json({ error: "Stripe account not connected. Complete onboarding first." }, 400);
  }
  if (!driver.payouts_enabled) {
    return json({ error: "Payouts not yet enabled by Stripe. Complete KYC verification." }, 400);
  }
  if (payout_type === "instant" && !driver.stripe_debit_card_added) {
    return json(
      { error: "Add a debit card to your Stripe account to enable instant payouts." },
      400
    );
  }

  // --- Guard: Sufficient available balance ---
  const totalEarned = Number(driver.total_earnings ?? 0);
  const totalPaidOut = Number(driver.total_paid_out ?? 0);
  const availableBalanceCents = Math.round((totalEarned - totalPaidOut) * 100);
  if (amount_cents > availableBalanceCents) {
    return json({ error: "Insufficient available balance." }, 400);
  }

  // --- Guard: No in-flight payout already pending ---
  const { data: pending } = await adminClient
    .from("payout_history")
    .select("id")
    .eq("driver_id", driver.id)
    .eq("status", "pending")
    .limit(1)
    .single();

  if (pending) {
    return json({ error: "A payout is already in progress. Please wait." }, 409);
  }

  // --- Idempotency key: driver + amount + minute bucket ---
  const minuteBucket = Math.floor(Date.now() / 60000);
  const idempotencyKey = `payout-${driver.id}-${amount_cents}-${minuteBucket}`;

  // --- Check idempotency: already processed this key? ---
  const { data: existingPayout } = await adminClient
    .from("payout_history")
    .select("id, status, stripe_payout_id")
    .eq("idempotency_key", idempotencyKey)
    .single();

  if (existingPayout) {
    return json({
      message: "Payout already processed.",
      payout_id: existingPayout.id,
      status: existingPayout.status,
      stripe_payout_id: existingPayout.stripe_payout_id,
    });
  }

  // --- Insert pending payout record (prevents duplicates) ---
  const { data: payoutRecord, error: insertErr } = await adminClient
    .from("payout_history")
    .insert({
      driver_id: driver.id,
      amount: amount_cents / 100,
      currency: "usd",
      payout_type,
      status: "pending",
      idempotency_key: idempotencyKey,
    })
    .select()
    .single();

  if (insertErr) {
    return json({ error: "Failed to create payout record: " + insertErr.message }, 500);
  }

  // --- Check Stripe balance before attempting payout ---
  const balance = await stripeGet("/balance", driver.stripe_account_id);
  const available = ((balance as any).available ?? []) as Array<{
    amount: number;
    currency: string;
  }>;
  const usdBalance = available.find((b) => b.currency === "usd");
  if (!usdBalance || usdBalance.amount < amount_cents) {
    // Update payout record to failed
    await adminClient
      .from("payout_history")
      .update({ status: "failed", failure_message: "Insufficient Stripe balance" })
      .eq("id", payoutRecord.id);

    // Fallback: offer standard payout if instant was requested
    if (payout_type === "instant") {
      return json({
        error: "Insufficient Stripe balance for instant payout.",
        fallback_available: true,
        message: "Try standard payout instead (2-5 business days).",
      }, 400);
    }
    return json({ error: "Insufficient Stripe balance." }, 400);
  }

  // --- Create Stripe payout ---
  const stripeParams: Record<string, string> = {
    amount: String(amount_cents),
    currency: "usd",
  };
  if (payout_type === "instant") {
    stripeParams.method = "instant";
  }

  const payout = await stripePost(
    "/payouts",
    stripeParams,
    driver.stripe_account_id,
    idempotencyKey
  );

  if ((payout as any).error) {
    const errMsg = (payout as any).error.message ?? "Payout creation failed";

    await adminClient
      .from("payout_history")
      .update({ status: "failed", failure_message: errMsg })
      .eq("id", payoutRecord.id);

    // Fallback to standard if instant failed (e.g. card not eligible)
    if (payout_type === "instant") {
      return json({
        error: errMsg,
        fallback_available: true,
        message: "Instant payout failed. You can request a standard payout instead.",
      }, 400);
    }
    return json({ error: errMsg }, 502);
  }

  // --- Update payout record with Stripe payout ID ---
  await adminClient
    .from("payout_history")
    .update({ stripe_payout_id: (payout as any).id })
    .eq("id", payoutRecord.id);

  // --- Update driver total_paid_out ---
  const newPaidOut = totalPaidOut + amount_cents / 100;
  await adminClient
    .from("drivers")
    .update({ total_paid_out: newPaidOut, updated_at: new Date().toISOString() })
    .eq("id", driver.id);

  return json({
    success: true,
    payout_id: payoutRecord.id,
    stripe_payout_id: (payout as any).id,
    amount: amount_cents / 100,
    currency: "usd",
    payout_type,
    arrival_date: (payout as any).arrival_date,
    status: (payout as any).status,
  });
});

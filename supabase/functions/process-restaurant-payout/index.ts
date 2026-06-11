// @ts-nocheck
// process-restaurant-payout/index.ts
// Option B: validates an approved restaurant payout request, records the debit,
// and returns full bank-wire details for the admin to execute manually.
// Does NOT touch Stripe — restaurants use manual bank transfers.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // ── Auth ──────────────────────────────────────────────────────────────────
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization header" }, 401);

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  const token = authHeader.replace(/^Bearer\s+/i, "");
  let uid: string;
  try {
    const payload = JSON.parse(atob(token.split(".")[1]));
    uid = payload.sub as string;
    if (!uid) throw new Error();
  } catch {
    return json({ error: "Invalid token" }, 401);
  }

  // Only admins may trigger payouts
  const { data: callerUser, error: userErr } = await adminClient
    .from("users")
    .select("id, role")
    .eq("id", uid)
    .maybeSingle();

  if (userErr || !callerUser) return json({ error: "Unauthorized" }, 401);
  if (callerUser.role !== "admin") {
    return json({ error: "Admin access required" }, 403);
  }

  // ── Body ──────────────────────────────────────────────────────────────────
  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { payout_request_id } = body as { payout_request_id: string };
  if (!payout_request_id) {
    return json({ error: "payout_request_id is required" }, 400);
  }

  // ── Fetch payout request ──────────────────────────────────────────────────
  const { data: payout, error: payoutErr } = await adminClient
    .from("payout_requests")
    .select("*")
    .eq("id", payout_request_id)
    .single();

  if (payoutErr || !payout) {
    return json({ error: "Payout request not found" }, 404);
  }

  if (payout.requester_type !== "restaurant") {
    return json({ error: "This endpoint is for restaurant payouts only" }, 400);
  }

  if (payout.status !== "approved") {
    return json(
      { error: `Payout must be in 'approved' state (current: ${payout.status})` },
      409
    );
  }

  const restaurantId = payout.restaurant_id as string;
  if (!restaurantId) {
    return json({ error: "Payout has no associated restaurant_id" }, 400);
  }

  // ── Check available balance ───────────────────────────────────────────────
  const { data: balanceRow } = await adminClient
    .from("restaurant_balance_view")
    .select("available_balance, total_earnings, total_paid_out")
    .eq("restaurant_id", restaurantId)
    .maybeSingle();

  const availableBalance = Number(balanceRow?.available_balance ?? 0);
  const requestedAmount = Number(payout.amount);

  if (requestedAmount > availableBalance + 0.005) {
    return json(
      {
        error: `Insufficient balance. Available: $${availableBalance.toFixed(2)}, Requested: $${requestedAmount.toFixed(2)}`,
        available_balance: availableBalance,
        requested_amount: requestedAmount,
      },
      400
    );
  }

  // ── Guard: no other in-flight payout for this restaurant ─────────────────
  const { data: inFlight } = await adminClient
    .from("payout_requests")
    .select("id")
    .eq("restaurant_id", restaurantId)
    .eq("status", "processing")
    .limit(1)
    .maybeSingle();

  if (inFlight) {
    return json(
      { error: "A payout is already being processed for this restaurant. Complete or reject it first." },
      409
    );
  }

  // ── Mark payout as processing ─────────────────────────────────────────────
  const { error: updateErr } = await adminClient
    .from("payout_requests")
    .update({
      status: "processing",
      updated_at: new Date().toISOString(),
    })
    .eq("id", payout_request_id);

  if (updateErr) {
    return json({ error: "Failed to update payout status: " + updateErr.message }, 500);
  }

  // ── Record debit in restaurant_transactions ───────────────────────────────
  const { error: txnErr } = await adminClient
    .from("restaurant_transactions")
    .insert({
      restaurant_id: restaurantId,
      payout_request_id: payout_request_id,
      type: "debit",
      amount: requestedAmount,
      description: `Payout to ${payout.bank_account_holder} via ${payout.bank_name}`,
    });

  if (txnErr) {
    // Roll back to approved so admin can retry
    await adminClient
      .from("payout_requests")
      .update({ status: "approved", updated_at: new Date().toISOString() })
      .eq("id", payout_request_id);
    return json({ error: "Failed to record transaction: " + txnErr.message }, 500);
  }

  // ── Return bank-wire details for admin to action ──────────────────────────
  return json({
    success: true,
    payout_id: payout_request_id,
    restaurant_id: restaurantId,
    amount: requestedAmount,
    currency: "usd",
    status: "processing",
    wire_details: {
      recipient_name: payout.bank_account_holder,
      bank_name: payout.bank_name,
      bank_branch: payout.bank_branch ?? null,
      account_number: payout.bank_account_number,
      account_type: payout.bank_account_type ?? null,
    },
    balance_before: availableBalance,
    balance_after: availableBalance - requestedAmount,
    note: "Debit recorded. Complete the bank wire transfer and then mark this payout as Completed.",
  });
});

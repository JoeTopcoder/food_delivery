// @ts-nocheck
// stripe-payout-webhook/index.ts
// Handles Stripe webhook events for payouts and account updates.
// SECURITY: Webhook signature verified before processing.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import {
  crypto,
  toHashString,
} from "https://deno.land/std@0.224.0/crypto/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_WEBHOOK_SECRET = Deno.env.get("STRIPE_PAYOUT_WEBHOOK_SECRET") ?? "";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/**
 * Verify Stripe webhook signature (HMAC-SHA256).
 * Stripe sends: Stripe-Signature: t=<timestamp>,v1=<sig>
 */
async function verifyStripeSignature(
  payload: string,
  sigHeader: string,
  secret: string
): Promise<boolean> {
  const parts = Object.fromEntries(
    sigHeader.split(",").map((p) => p.split("=") as [string, string])
  );
  const timestamp = parts["t"];
  const expectedSig = parts["v1"];
  if (!timestamp || !expectedSig) return false;

  // Tolerance: 5 minutes
  if (Math.abs(Date.now() / 1000 - Number(timestamp)) > 300) return false;

  const signedPayload = `${timestamp}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signedPayload)
  );
  const computedSig = toHashString(new Uint8Array(sig));
  return computedSig === expectedSig;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const sigHeader = req.headers.get("stripe-signature") ?? "";
  const rawBody = await req.text();

  if (STRIPE_WEBHOOK_SECRET) {
    const valid = await verifyStripeSignature(rawBody, sigHeader, STRIPE_WEBHOOK_SECRET);
    if (!valid) {
      return json({ error: "Invalid webhook signature" }, 400);
    }
  }

  const event = JSON.parse(rawBody) as {
    type: string;
    data: { object: Record<string, unknown> };
  };

  const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

  // ── payout.paid ──────────────────────────────────────────────────────────
  if (event.type === "payout.paid") {
    const payout = event.data.object;
    const stripePayoutId = payout.id as string;

    await adminClient
      .from("payout_history")
      .update({ status: "paid" })
      .eq("stripe_payout_id", stripePayoutId);

    console.log(`[webhook] payout.paid: ${stripePayoutId}`);
  }

  // ── payout.failed ────────────────────────────────────────────────────────
  else if (event.type === "payout.failed") {
    const payout = event.data.object;
    const stripePayoutId = payout.id as string;
    const failureMsg =
      (payout.failure_message as string) ?? "Payout failed";

    // Fetch the payout record to get the driver
    const { data: payoutRecord } = await adminClient
      .from("payout_history")
      .select("driver_id, amount")
      .eq("stripe_payout_id", stripePayoutId)
      .single();

    await adminClient
      .from("payout_history")
      .update({ status: "failed", failure_message: failureMsg })
      .eq("stripe_payout_id", stripePayoutId);

    // Reverse the total_paid_out deduction so driver can retry
    if (payoutRecord) {
      const { data: driver } = await adminClient
        .from("drivers")
        .select("total_paid_out")
        .eq("id", payoutRecord.driver_id)
        .single();

      if (driver) {
        const corrected = Math.max(
          0,
          Number(driver.total_paid_out) - Number(payoutRecord.amount)
        );
        await adminClient
          .from("drivers")
          .update({
            total_paid_out: corrected,
            updated_at: new Date().toISOString(),
          })
          .eq("id", payoutRecord.driver_id);
      }

      // Notify driver via in-app notification
      const { data: driverRow } = await adminClient
        .from("drivers")
        .select("user_id")
        .eq("id", payoutRecord.driver_id)
        .single();

      if (driverRow) {
        await adminClient.from("notifications").insert({
          user_id: driverRow.user_id,
          title: "Payout Failed",
          body: `Your payout of $${Number(payoutRecord.amount).toFixed(2)} failed: ${failureMsg}. Please try again.`,
          type: "payout_failed",
          is_read: false,
        });
      }
    }

    console.log(`[webhook] payout.failed: ${stripePayoutId} — ${failureMsg}`);
  }

  // ── account.updated ──────────────────────────────────────────────────────
  else if (event.type === "account.updated") {
    const account = event.data.object;
    const stripeAccountId = account.id as string;
    const payoutsEnabled = account.payouts_enabled as boolean;
    const chargesEnabled = account.charges_enabled as boolean;

    // Check if debit card is added (external accounts with card type)
    const externalAccounts = (account.external_accounts as any)?.data ?? [];
    const hasDebitCard = externalAccounts.some(
      (ea: any) => ea.object === "card" && ea.account_type !== "credit"
    );

    const newStatus =
      payoutsEnabled && chargesEnabled
        ? "active"
        : chargesEnabled
        ? "pending"
        : "restricted";

    const { error } = await adminClient
      .from("drivers")
      .update({
        payouts_enabled: payoutsEnabled,
        stripe_debit_card_added: hasDebitCard,
        stripe_account_status: newStatus,
        updated_at: new Date().toISOString(),
      })
      .eq("stripe_account_id", stripeAccountId);

    if (!error && payoutsEnabled) {
      // Notify driver that they can now cash out
      const { data: driver } = await adminClient
        .from("drivers")
        .select("user_id")
        .eq("stripe_account_id", stripeAccountId)
        .single();

      if (driver) {
        await adminClient.from("notifications").insert({
          user_id: driver.user_id,
          title: "Payouts Enabled!",
          body: "Your Stripe account is verified. You can now cash out your earnings.",
          type: "payout_enabled",
          is_read: false,
        });
      }
    }

    console.log(
      `[webhook] account.updated: ${stripeAccountId} payouts_enabled=${payoutsEnabled}`
    );
  }

  return json({ received: true });
});

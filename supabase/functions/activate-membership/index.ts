// activate-membership — Server-authoritative HotBite+ purchase.
// Verifies the authenticated user, takes real payment (wallet now; card via a
// pre-confirmed PaymentIntent), then calls activate_membership (service role)
// so the client can never self-activate without paying. Renewal extends the
// existing end date; duplicate payment references are idempotent.
// Deploy: supabase functions deploy activate-membership

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };
// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? Deno.env.get("STRIPE_SK") ?? "";
const admin = createClient(supabaseUrl, serviceKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const planId = body.plan_id as string;
  const paymentMethod = (body.payment_method as string) ?? "wallet";
  const paymentIntentId = body.payment_intent_id as string | undefined;
  if (!planId) return json({ error: "Missing plan_id" }, 400);

  // ── Authenticate the caller ────────────────────────────────────────────────
  const authHeader = request.headers.get("Authorization") ?? "";
  const token = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7) : "";
  if (!token) return json({ error: "Please sign in to join HotBite+." }, 401);
  const { data: authUser, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !authUser?.user) return json({ error: "Please sign in again." }, 401);
  const userId = authUser.user.id;

  // ── HotBite+ must be enabled ───────────────────────────────────────────────
  const { data: enabledCfg } = await admin.from("app_config").select("value").eq("key", "hotbite_plus_enabled").maybeSingle();
  if (!(enabledCfg?.value === "true" || enabledCfg?.value === "1")) {
    return json({ error: "HotBite+ is not available right now." }, 403);
  }

  // ── Server-side price (never trust the client) ─────────────────────────────
  const { data: plan } = await admin.from("membership_plans")
    .select("id, name, price").eq("id", planId).eq("is_active", true).maybeSingle();
  if (!plan) return json({ error: "This plan is not available." }, 404);
  const price = Number(plan.price);

  // ── Take payment ───────────────────────────────────────────────────────────
  const paymentRef = `hbp_${userId.slice(0, 8)}_${Date.now()}`;
  try {
    if (paymentMethod === "wallet") {
      const { error: wErr } = await admin.rpc("wallet_deduct", {
        p_user_id: userId, p_amount: price, p_description: `HotBite+ ${plan.name} membership`,
      });
      if (wErr) {
        const insufficient = (wErr.message ?? "").toLowerCase().includes("insufficient");
        return json({ error: insufficient ? "Insufficient wallet balance." : "Payment failed." }, insufficient ? 402 : 500);
      }
    } else if (paymentMethod === "card") {
      // Flutter confirms the PaymentIntent, we verify it succeeded for the amount.
      if (!paymentIntentId) return json({ error: "Missing payment confirmation." }, 400);
      const res = await fetch(`https://api.stripe.com/v1/payment_intents/${paymentIntentId}`, {
        headers: { Authorization: `Bearer ${stripeKey}` },
      });
      const pi = await res.json() as Record<string, unknown>;
      if (pi.status !== "succeeded") return json({ error: "Your payment was not completed." }, 402);
      if (Math.round(price * 100) !== Number(pi.amount)) {
        return json({ error: "Payment amount mismatch." }, 402);
      }
    } else {
      return json({ error: "Unsupported payment method." }, 400);
    }
  } catch (e) {
    console.error(`[activate-membership] payment error: ${e}`);
    return json({ error: "Payment could not be processed." }, 500);
  }

  // ── Activate (or extend) the membership — trusted, service role ────────────
  const { data: result, error: actErr } = await admin.rpc("activate_membership", {
    p_user_id: userId, p_plan_id: planId, p_payment_reference: paymentRef,
  });
  if (actErr) {
    console.error(`[activate-membership] activation error: ${actErr.message}`);
    // Payment succeeded but activation failed — surface for support/refund.
    return json({ error: "Payment received but activation failed. Please contact support.", payment_reference: paymentRef }, 500);
  }

  return json({ success: true, membership: result, payment_reference: paymentRef });
});

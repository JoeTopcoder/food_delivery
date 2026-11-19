// gas-pay-order — Payment capture for a Cooking Gas order.
// Called AFTER the supplier accepts and the order is 'awaiting_payment'.
//   method 'wallet' → delegates to gas_pay_wallet RPC as the signed-in user
//                     (audited ledger debit; see migration 20261119120000).
//   method 'stripe' → charges the saved card (JMD displayed, USD charged at the
//                     admin usd_jmd_rate, mirroring place-order) then calls the
//                     service-role gas_confirm_payment to advance the order.
// Deploy: supabase functions deploy gas-pay-order
// NOTE: the Stripe path needs a live session JWT + Stripe key to verify end-to-end.

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };
// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const anonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? Deno.env.get("STRIPE_SK") ?? "";
const admin = createClient(supabaseUrl, serviceKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } });
}
async function stripePost(endpoint: string, params: Record<string, string>): Promise<Record<string, unknown>> {
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params).toString(),
  });
  return res.json() as Promise<Record<string, unknown>>;
}
async function stripeGet(endpoint: string): Promise<Record<string, unknown>> {
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, { headers: { Authorization: `Bearer ${stripeKey}` } });
  return res.json() as Promise<Record<string, unknown>>;
}
async function getConfig(key: string, dflt: number): Promise<number> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  const v = parseFloat((data?.value as string) ?? "");
  return Number.isFinite(v) ? v : dflt;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.toLowerCase().startsWith("bearer ") ? authHeader.slice(7) : "";
    if (!token) return json({ error: "Sign in again to pay." }, 401);
    const { data: authUser, error: authErr } = await admin.auth.getUser(token);
    const uid = authUser?.user?.id;
    if (authErr || !uid) return json({ error: "Sign in again to pay." }, 401);

    const body = await req.json().catch(() => ({}));
    const orderId = String(body.orderId ?? body.order_id ?? "");
    const method = String(body.method ?? "wallet");
    const savedCardPaymentMethodId = body.paymentMethodId as string | undefined;
    const incomingPaymentIntentId = body.paymentIntentId as string | undefined;
    if (!orderId) return json({ error: "Missing orderId." }, 400);

    // Load + authorize the order
    const { data: order } = await admin.from("gas_orders")
      .select("id, customer_id, status, payment_status, total_cents")
      .eq("id", orderId).maybeSingle();
    if (!order) return json({ error: "Order not found." }, 404);
    if (order.customer_id !== uid) return json({ error: "Not your order." }, 403);
    if (order.payment_status === "paid") return json({ ok: true, already_paid: true });
    if (order.status !== "awaiting_payment") {
      return json({ error: `Order is not awaiting payment (status ${order.status}).` }, 409);
    }

    // ── Wallet: run the audited RPC AS THE USER ──────────────────────────────
    if (method === "wallet") {
      const userClient = createClient(supabaseUrl, anonKey, {
        global: { headers: { Authorization: `Bearer ${token}` } },
      });
      const { data, error } = await userClient.rpc("gas_pay_wallet", { p_order: orderId });
      if (error) return json({ error: error.message }, 402);
      return json({ ok: true, method: "wallet", result: data });
    }

    // ── Card (Stripe): JMD displayed, USD charged at admin usd_jmd_rate ───────
    if (method === "stripe") {
      if (!stripeKey) return json({ error: "Payment provider not configured." }, 500);
      const totalJmd = (order.total_cents as number) / 100;
      const fxRate = await getConfig("usd_jmd_rate", 160);
      const usdCents = Math.max(50, Math.round((totalJmd / (fxRate > 0 ? fxRate : 160)) * 100));
      let piId = incomingPaymentIntentId ?? "";
      if (savedCardPaymentMethodId) {
        const { data: u } = await admin.from("users").select("stripe_customer_id").eq("id", uid).maybeSingle();
        const custId = u?.stripe_customer_id as string | undefined;
        const pi = await stripePost("/payment_intents", {
          amount: String(usdCents), currency: "usd",
          payment_method: savedCardPaymentMethodId,
          ...(custId ? { customer: custId } : {}),
          off_session: "true", confirm: "true", description: "Cooking Gas Order",
          "metadata[type]": "gas_order", "metadata[user_id]": uid,
          "metadata[gas_order_id]": orderId, "metadata[jmd_total]": String(totalJmd),
        });
        const st = pi.status as string;
        if (pi.error || (st !== "succeeded" && st !== "requires_capture")) {
          const msg = ((pi.error as Record<string, unknown>)?.message as string) ?? "Card charge failed.";
          return json({ error: msg }, 402);
        }
        piId = pi.id as string;
      } else if (incomingPaymentIntentId) {
        const pi = await stripeGet(`/payment_intents/${encodeURIComponent(incomingPaymentIntentId)}`);
        const st = pi.status as string;
        if (st !== "succeeded" && st !== "requires_capture") {
          return json({ error: "Payment not confirmed. Please complete payment first." }, 402);
        }
      } else {
        return json({ error: "Card payment information required." }, 402);
      }
      // advance the order via the trusted service-role confirm (idempotent)
      const { error } = await admin.rpc("gas_confirm_payment", { p_order: orderId, p_method: "stripe", p_ref: piId });
      if (error) return json({ error: error.message }, 500);
      return json({ ok: true, method: "stripe", payment_intent: piId });
    }

    return json({ error: `Unsupported payment method '${method}'.` }, 400);
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});

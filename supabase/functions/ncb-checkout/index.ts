// NCB Genius Checkout — create a hosted checkout session for an order.
// Mirrors the Stripe order flow: the app calls this with an order_id, we create
// a Genius Checkout session on NCB and return the checkout_url for the app to
// open. The webhook (ncb-webhook) is the authoritative confirmation.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const GC_API_KEY   = Deno.env.get("NCB_GC_API_KEY") ?? "";
const GC_BASE      = (Deno.env.get("NCB_GC_BASE_URL") ?? "https://app.geniuscheckout.com").replace(/\/+$/, "");
// Return targets the in-app WebView intercepts (must be allow-listed in the NCB
// Merchant Portal → Domains). The app watches for these path prefixes.
const RETURN_BASE  = Deno.env.get("NCB_RETURN_BASE") ?? "https://hotbite.app/ncb";

const admin = createClient(SUPABASE_URL, SERVICE_KEY);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!GC_API_KEY) return json({ error: "NCB not configured (NCB_GC_API_KEY unset)" }, 503);

    const body = await req.json();
    const orderId = (body.order_id ?? "").toString();
    if (!orderId) return json({ error: "order_id is required" }, 400);

    // Authoritative amounts come from the order row, never the client.
    const { data: order } = await admin
      .from("orders")
      .select("id, user_id, total_amount, subtotal, tax_amount, delivery_fee, payment_status, receipt_number")
      .eq("id", orderId)
      .maybeSingle();
    if (!order) return json({ error: "Order not found" }, 404);
    if (order.payment_status === "completed") return json({ error: "Order already paid" }, 409);

    const { data: user } = await admin
      .from("users").select("name, email").eq("id", order.user_id).maybeSingle();

    // Everything is JMD, a 2-decimal currency → minor units = round(value * 100).
    const minor = (v: number) => Math.round(Number(v || 0) * 100);
    const total = minor(order.total_amount);
    if (total <= 0) return json({ error: "Order total must be positive" }, 422);

    const shortId = orderId.slice(0, 8).toUpperCase();
    const taxAmt = minor(order.tax_amount);
    const subtotalMinor = minor(order.subtotal) + minor(order.delivery_fee); // taxed base is delivery; shown as subtotal

    const payload: Record<string, unknown> = {
      amount: total,
      currency: "JMD",
      success_url: `${RETURN_BASE}/success?order=${orderId}`,
      failure_url: `${RETURN_BASE}/failure?order=${orderId}`,
      cancel_url:  `${RETURN_BASE}/cancel?order=${orderId}`,
      description: `HotBite Order #${shortId}`,
      customer: { name: user?.name ?? "Customer", email: user?.email ?? "" },
      metadata: { order_id: orderId, type: "order", source: "hotbite_app" },
      expires_in_minutes: 30,
    };
    if (taxAmt > 0) {
      payload.subtotal = Math.max(0, total - taxAmt);
      payload.tax_name = "GCT";
      payload.tax_rate = 0.15;
      payload.tax_amount = taxAmt;
    }

    const res = await fetch(`${GC_BASE}/api/v1/checkout-sessions`, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${GC_API_KEY}`,
        "Content-Type": "application/json",
        "Idempotency-Key": `order-${orderId}`,
      },
      body: JSON.stringify(payload),
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) {
      return json({ error: data?.error ?? data?.message ?? "NCB session create failed", status: res.status, details: data }, 502);
    }

    // Link the session to the order for later verification.
    await admin.from("orders")
      .update({ ncb_session_id: data.id, updated_at: new Date().toISOString() })
      .eq("id", orderId);

    return json({
      provider: "ncb",
      session_id: data.id,
      checkout_url: data.checkout_url,
      expires_at: data.expires_at,
    });
  } catch (e) {
    return json({ error: "Server error", details: `${e}` }, 500);
  }
});

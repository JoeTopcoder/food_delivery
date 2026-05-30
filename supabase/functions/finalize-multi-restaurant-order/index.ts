// finalize-multi-restaurant-order
// Called after Stripe payment confirmation.
// Accepts master_order_id (new) or order_group_id (legacy alias — same value).
// Sets master_orders.payment_status = 'paid', activates all restaurant_orders,
// notifies each restaurant, triggers driver assignment.
// Deploy: supabase functions deploy finalize-multi-restaurant-order --no-verify-jwt

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin       = createClient(supabaseUrl, supabaseKey);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}

interface FinalizeRequest {
  master_order_id?:          string;
  order_group_id?:           string;  // backward-compat alias
  payment_intent_id?:        string;
  stripe_payment_intent_id?: string;
  user_id?:                  string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: FinalizeRequest;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  // Accept both field names — order_group_id is the legacy name, master_order_id is new
  const masterOrderId = body.master_order_id ?? body.order_group_id;
  if (!masterOrderId) {
    return json({ error: "master_order_id (or order_group_id) required" }, 400);
  }

  const paymentIntentId = body.payment_intent_id ?? body.stripe_payment_intent_id;

  // ── 1. Load master_order ──────────────────────────────────────────────────
  const { data: masterOrder, error: moErr } = await admin
    .from("master_orders")
    .select("*")
    .eq("id", masterOrderId)
    .single();

  if (moErr || !masterOrder) return json({ error: "Master order not found" }, 404);

  if (masterOrder.payment_status === "paid") {
    return json({ success: true, already_finalized: true, master_order_id: masterOrderId });
  }
  if (masterOrder.payment_status !== "pending") {
    return json({
      error: `Master order payment_status is '${masterOrder.payment_status}' — cannot finalize`,
    }, 409);
  }

  // ── 2. Activate master_order ──────────────────────────────────────────────
  const { error: moUpdateErr } = await admin
    .from("master_orders")
    .update({ payment_status: "paid", status: "preparing", updated_at: new Date().toISOString() })
    .eq("id", masterOrderId);

  if (moUpdateErr) {
    return json({ error: `Failed to update master_order: ${moUpdateErr.message}` }, 500);
  }

  // ── 3. Activate orders sub-records (draft → pending, payment_status → completed) ──
  // Restaurant_orders stay at 'pending' — each restaurant accepts individually.
  await admin
    .from("orders")
    .update({ status: "pending", payment_status: "completed", updated_at: new Date().toISOString() })
    .eq("order_group_id", masterOrderId)
    .eq("status", "draft");

  const { data: restOrders, error: roErr } = await admin
    .from("restaurant_orders")
    .select("id, restaurant_id, subtotal, restaurant_order_number, delivery_otp")
    .eq("master_order_id", masterOrderId);

  if (roErr) return json({ error: `Failed to load restaurant_orders: ${roErr.message}` }, 500);
  if (!restOrders?.length) return json({ error: "No restaurant_orders found for this master_order" }, 404);

  // ── 4. Notify customer ────────────────────────────────────────────────────
  const customerId = masterOrder.customer_id;
  await admin.from("notifications").insert({
    user_id: customerId,
    type:    "order_placed",
    title:   "✅ Order Confirmed!",
    body:    `Your order #${masterOrder.master_order_number} from ${restOrders.length} restaurant${restOrders.length > 1 ? 's' : ''} has been confirmed.`,
    data:    { master_order_id: masterOrderId, master_order_number: masterOrder.master_order_number },
  }).catch(() => null);

  // ── 5. Notify each restaurant ─────────────────────────────────────────────
  for (const ro of restOrders) {
    const { data: restaurant } = await admin
      .from("restaurants")
      .select("owner_id, name")
      .eq("id", ro.restaurant_id)
      .single();

    if (restaurant?.owner_id) {
      await admin.from("notifications").insert({
        user_id: restaurant.owner_id,
        type:    "new_restaurant_order",
        title:   "🔔 New Group Order!",
        body:    `Order ${ro.restaurant_order_number} — part of a multi-restaurant delivery.`,
        data:    {
          restaurant_order_id:     ro.id,
          master_order_id:         masterOrderId,
          restaurant_id:           ro.restaurant_id,
          restaurant_order_number: ro.restaurant_order_number,
        },
      }).catch(() => null);
    }
  }

  // ── 6. Trigger driver assignment (fire-and-forget) ────────────────────────
  fetch(`${supabaseUrl}/functions/v1/assign-driver-multi-pickup`, {
    method:  "POST",
    headers: {
      "Content-Type":  "application/json",
      "Authorization": `Bearer ${supabaseKey}`,
      "apikey":        supabaseKey,
    },
    body: JSON.stringify({ master_order_id: masterOrderId, order_group_id: masterOrderId }),
  }).catch(() => null);

  return json({
    success:            true,
    master_order_id:    masterOrderId,
    order_group_id:     masterOrderId,  // backward-compat
    activated_count:    restOrders.length,
    master_order_number: masterOrder.master_order_number,
  });
});

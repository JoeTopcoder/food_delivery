// place-order — Server-authoritative order placement
// Handles: order creation, order items + sides, receipt number, OTP, commission, ad boost.
// Notifications are handled by DB triggers (migration 108) and are gated on payment_status.
// Deploy: supabase functions deploy place-order

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function round2(n: number): number { return Math.round(n * 100) / 100; }

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function generateOtp(): string {
  return String(1000 + Math.floor(Math.random() * 9000));
}

function generatePickupCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) code += chars[Math.floor(Math.random() * chars.length)];
  return code;
}

async function getConfig(key: string, fallback: number): Promise<number> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  return data ? parseFloat(data.value) : fallback;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const userId = body.user_id as string;
  const restaurantId = body.restaurant_id as string;
  const items = body.items as Array<{
    menu_item_id: string;
    item_name: string;
    price: number;
    quantity: number;
    subtotal: number;
    notes?: string;
    sides?: Array<{ side_name: string; side_price: number }>;
  }>;
  const subtotal = body.subtotal as number;
  const deliveryFee = body.delivery_fee as number;
  const taxAmount = (body.tax_amount as number | undefined) ?? 0;
  const discount = (body.discount as number | undefined) ?? 0;
  const totalAmount = body.total_amount as number;
  const deliveryAddress = body.delivery_address as string;
  const deliveryLatitude = body.delivery_latitude as number;
  const deliveryLongitude = body.delivery_longitude as number;
  const notes = body.notes as string | undefined;
  const paymentMethod = (body.payment_method as string) ?? "cash";
  const contactlessDelivery = body.contactless_delivery === true;
  const driverTip = (body.driver_tip as number | undefined) ?? 0;
  const scheduledFor = body.scheduled_for as string | undefined;
  const isPickup = body.is_pickup === true;
  const pickupFee = body.pickup_fee as number | undefined;
  const fromAd = body.from_ad === true;
  const adId = body.ad_id as string | undefined;
  const promoCode = body.promo_code as string | undefined;

  if (!userId || !restaurantId || !items?.length || !deliveryAddress) {
    return json({ error: "Missing required fields" }, 400);
  }

  // ── PAYMENT GATE: card orders start as 'draft' ─────────────────────────────
  // 'stripe' = food checkout card payment
  // 'card'   = grocery checkout card payment
  // Both are gated: the order remains invisible to restaurant/drivers until
  // stripe-webhook confirms payment and sets status = 'pending'.
  const isCardPayment = paymentMethod === "stripe" || paymentMethod === "card";
  const initialStatus = isCardPayment ? "draft" : "pending";

  try {
    // ── 1. Fetch restaurant commission rate ─────────────────────────────
    const { data: restaurant, error: restErr } = await admin
      .from("restaurants")
      .select("id, name, commission_rate, latitude, longitude")
      .eq("id", restaurantId)
      .single();

    if (restErr || !restaurant) {
      return json({ error: "Restaurant not found" }, 404);
    }

    const defaultCommission = await getConfig("default_commission_rate", 0.15);
    let commissionRate = restaurant.commission_rate ?? defaultCommission;

    if (fromAd) {
      commissionRate = commissionRate + 0.05;
    }
    const commissionAmount = round2(totalAmount * commissionRate);

    // ── 2. Generate OTP + receipt number ────────────────────────────────
    const otp = isPickup ? null : generateOtp();
    const pickupCode = isPickup ? generatePickupCode() : null;

    const now = new Date();
    const dateStr = `${now.getFullYear()}${String(now.getMonth() + 1).padStart(2, "0")}${String(now.getDate()).padStart(2, "0")}`;
    const todayStart = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();

    const { data: countData } = await admin
      .from("orders")
      .select("id", { count: "exact", head: true })
      .gte("ordered_at", todayStart);
    const seq = (countData?.length ?? 0) + 1;
    const receiptNumber = `FD-${dateStr}-${String(seq).padStart(4, "0")}`;

    // ── 3. Calculate distance ────────────────────────────────────────────
    let distanceKm: number | null = null;
    if (restaurant.latitude && restaurant.longitude && deliveryLatitude && deliveryLongitude) {
      distanceKm = round2(haversineKm(
        restaurant.latitude, restaurant.longitude,
        deliveryLatitude, deliveryLongitude,
      ));
    }

    // ── 4. Insert order ──────────────────────────────────────────────────
    const orderData: Record<string, unknown> = {
      user_id: userId,
      restaurant_id: restaurantId,
      subtotal,
      tax_amount: taxAmount,
      delivery_fee: deliveryFee,
      total_amount: totalAmount,
      status: initialStatus,        // 'draft' for card, 'pending' for cash/wallet
      delivery_address: deliveryAddress,
      delivery_latitude: deliveryLatitude,
      delivery_longitude: deliveryLongitude,
      payment_method: paymentMethod,
      payment_status: "pending",
      ordered_at: now.toISOString(),
      contactless_delivery: contactlessDelivery,
      delivery_otp: otp,
      pickup_code: pickupCode,
      receipt_number: receiptNumber,
      commission_rate: commissionRate,
      commission_amount: commissionAmount,
      is_pickup: isPickup,
    };

    if (distanceKm !== null) orderData.distance_km = distanceKm;
    if (notes) orderData.notes = notes;
    if (discount > 0) orderData.discount = discount;
    if (driverTip > 0) orderData.driver_tip = driverTip;
    if (scheduledFor) {
      orderData.scheduled_for = scheduledFor;
      orderData.is_scheduled = true;
    }
    if (isPickup && pickupFee) orderData.pickup_fee = pickupFee;
    if (fromAd) orderData.from_ad = true;
    if (adId) orderData.ad_id = adId;
    if (promoCode && promoCode.trim().length > 0) {
      orderData.promo_code = promoCode.trim().toUpperCase();
      if (discount > 0) orderData.discount_amount = discount;
    }

    const { data: order, error: orderErr } = await admin
      .from("orders")
      .insert(orderData)
      .select()
      .single();

    if (orderErr || !order) {
      return json({ error: "Failed to create order", details: orderErr?.message }, 500);
    }

    const orderId = order.id as string;

    // ── 5. Insert order items + sides ────────────────────────────────────
    for (const item of items) {
      const { data: insertedItem, error: itemErr } = await admin
        .from("order_items")
        .insert({
          order_id: orderId,
          menu_item_id: item.menu_item_id,
          item_name: item.item_name,
          price: item.price,
          quantity: item.quantity,
          subtotal: item.subtotal,
          notes: item.notes ?? null,
        })
        .select("id")
        .single();

      if (itemErr || !insertedItem) continue;

      if (item.sides && item.sides.length > 0) {
        const sideRows = item.sides.map((s) => ({
          order_item_id: insertedItem.id,
          side_name: s.side_name,
          side_price: s.side_price,
        }));
        await admin.from("order_item_sides").insert(sideRows);
      }
    }

    // ── 6. Post-create side-effects ──────────────────────────────────────
    // Restaurant / admin / driver FCM notifications are handled exclusively
    // by DB triggers (migration 108) which gate on payment_status = 'completed'.
    // We must NOT duplicate those calls here.
    //
    // Receipt email: send immediately only for cash/wallet orders because their
    // payment is synchronous. Card orders get the receipt from stripe-webhook
    // once payment_intent.succeeded fires.
    if (!isCardPayment) {
      admin.functions.invoke("send-receipt-email", {
        body: { order_id: orderId },
      }).catch(() => {});
    }

    // ── 7. Return the created order ──────────────────────────────────────
    return json({
      success: true,
      order: {
        id: orderId,
        status: order.status,
        receipt_number: receiptNumber,
        delivery_otp: otp,
        pickup_code: pickupCode,
        total_amount: totalAmount,
        delivery_fee: deliveryFee,
        subtotal,
        tax_amount: taxAmount,
        discount,
        driver_tip: driverTip,
        commission_rate: commissionRate,
        commission_amount: commissionAmount,
        is_pickup: isPickup,
        ordered_at: order.ordered_at,
      },
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

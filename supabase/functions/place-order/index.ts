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
const stripeKey = Deno.env.get("STRIPE_SECRET_KEY") ?? Deno.env.get("STRIPE_SK") ?? "";
const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

async function stripePost(endpoint: string, params: Record<string, string>): Promise<Record<string, unknown>> {
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    method: "POST",
    headers: { Authorization: `Bearer ${stripeKey}`, "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(params).toString(),
  });
  return res.json() as Promise<Record<string, unknown>>;
}

async function stripeGet(endpoint: string): Promise<Record<string, unknown>> {
  const res = await fetch(`https://api.stripe.com/v1${endpoint}`, {
    headers: { Authorization: `Bearer ${stripeKey}` },
  });
  return res.json() as Promise<Record<string, unknown>>;
}

async function getStripeCustomerId(uid: string): Promise<string | null> {
  const { data } = await admin.from("users").select("stripe_customer_id").eq("id", uid).maybeSingle();
  return (data?.stripe_customer_id as string | undefined) ?? null;
}

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

async function notifyUser(userId: string, title: string, body: string, data: Record<string, string>) {
  try {
    const { data: user } = await admin.from("users").select("fcm_token").eq("id", userId).maybeSingle();
    if (!user?.fcm_token) return;
    await fetch(`${supabaseUrl}/functions/v1/send-fcm-notification`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${supabaseServiceRoleKey}` },
      body: JSON.stringify({ token: user.fcm_token, title, body, data }),
    });
  } catch { /* non-critical */ }
}

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

/** Returns effective tax rate for a delivery location using per-zone settings.
 *  Falls back to global app_config tax_rate when the zone has no override. */
async function getTaxRateForLocation(
  lat: number | null,
  lng: number | null,
  globalTaxRate: number,
): Promise<number> {
  if (!lat || !lng) return 0;

  const { data: regions } = await admin
    .from("delivery_regions")
    .select("latitude, longitude, radius_km, polygon, tax_enabled, tax_rate")
    .eq("is_active", true);

  if (!regions || regions.length === 0) return 0;

  for (const region of regions) {
    let inside = false;
    if (region.polygon && Array.isArray(region.polygon) && region.polygon.length >= 3) {
      inside = pointInPolygon(lat, lng, region.polygon as Array<{lat: number; lng: number}>);
    } else {
      const dist = haversineKm(lat, lng, region.latitude, region.longitude);
      inside = dist <= region.radius_km;
    }
    if (inside) {
      if (!region.tax_enabled) return 0;
      return region.tax_rate ?? globalTaxRate;
    }
  }
  return 0; // outside all zones → no tax
}

function pointInPolygon(lat: number, lng: number, polygon: Array<{lat: number; lng: number}>): boolean {
  let inside = false;
  const n = polygon.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const xi = polygon[i].lat, yi = polygon[i].lng;
    const xj = polygon[j].lat, yj = polygon[j].lng;
    const intersect = ((yi > lng) !== (yj > lng)) &&
      (lat < (xj - xi) * (lng - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
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
  const savedCardPaymentMethodId = body.saved_card_payment_method_id as string | undefined;
  const incomingPaymentIntentId = body.payment_intent_id as string | undefined;

  if (!userId || !restaurantId || !items?.length || !deliveryAddress) {
    return json({ error: "Missing required fields" }, 400);
  }

  // ── PAYMENT GATE ───────────────────────────────────────────────────────────
  // card   → charge Stripe BEFORE insert; order only created on success
  // wallet → deduct BEFORE insert (atomic); if deduction fails, no order created
  // cash   → 'preparing' immediately (collected on delivery)
  const isCardPayment = paymentMethod === "stripe" || paymentMethod === "card";
  const isWalletPayment = paymentMethod === "wallet";
  const initialStatus = "preparing";

  // Pre-generate the order UUID so we can pass it to wallet_pay before the insert.
  const orderId: string = crypto.randomUUID();

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

    // ── Zone-based tax (server-authoritative) ───────────────────────────
    const globalTaxRate = await getConfig("tax_rate", 0.0);
    const effectiveTaxRate = isPickup
      ? 0
      : await getTaxRateForLocation(deliveryLatitude, deliveryLongitude, globalTaxRate);
    const serverTaxAmount = round2(subtotal * effectiveTaxRate);

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

    // ── 4a. Wallet payment gate (atomic — must succeed before order is created) ──
    // wallet_deduct has no order_id FK so it safely runs before the order row exists.
    if (isWalletPayment) {
      const { error: walletErr } = await admin.rpc("wallet_deduct", {
        p_user_id:     userId,
        p_amount:      totalAmount,
        p_description: `Food order payment`,
      });
      if (walletErr) {
        const msg = walletErr.message ?? "Wallet payment failed";
        const isInsufficient = msg.toLowerCase().includes("insufficient");
        return json(
          { error: isInsufficient ? "Insufficient wallet balance" : msg },
          isInsufficient ? 402 : 500,
        );
      }
    }

    // ── 4b. Card payment gate — charge/verify BEFORE inserting the order ───
    // This prevents ghost 'draft' orders when the Stripe charge fails.
    // Saved card: create + confirm a PaymentIntent off-session right now.
    // Payment Sheet: Flutter already confirmed the PI — verify it server-side.
    if (isCardPayment) {
      if (!stripeKey) {
        return json({ error: "Payment provider not configured." }, 500);
      }
      if (savedCardPaymentMethodId) {
        const custId = await getStripeCustomerId(userId);
        const pi = await stripePost("/payment_intents", {
          amount:              String(Math.round(totalAmount * 100)),
          currency:            "usd",
          payment_method:      savedCardPaymentMethodId,
          ...(custId ? { customer: custId } : {}),
          off_session:         "true",
          confirm:             "true",
          description:         "Food Order",
          "metadata[type]":    "food_order",
          "metadata[user_id]": userId,
        });
        const piStatus = pi.status as string;
        if (pi.error || (piStatus !== "succeeded" && piStatus !== "requires_capture")) {
          const errMsg = ((pi.error as Record<string, unknown>)?.message as string)
            ?? "Card charge failed. Please try a different card.";
          return json({ error: errMsg }, 402);
        }
      } else if (incomingPaymentIntentId) {
        const pi = await stripeGet(`/payment_intents/${encodeURIComponent(incomingPaymentIntentId)}`);
        const piStatus = pi.status as string;
        if (piStatus !== "succeeded" && piStatus !== "requires_capture") {
          return json({ error: "Payment not confirmed. Please complete payment first." }, 402);
        }
      } else {
        return json({ error: "Card payment information required. Please select a saved card." }, 402);
      }
    }

    // ── 5. Insert order ──────────────────────────────────────────────────
    const orderData: Record<string, unknown> = {
      id: orderId,           // use pre-generated UUID (needed for wallet_pay above)
      user_id: userId,
      restaurant_id: restaurantId,
      subtotal,
      tax_amount: serverTaxAmount,
      delivery_fee: deliveryFee,
      total_amount: totalAmount,
      status: initialStatus,
      delivery_address: deliveryAddress,
      delivery_latitude: deliveryLatitude,
      delivery_longitude: deliveryLongitude,
      payment_method: paymentMethod,
      payment_status: (isCardPayment || isWalletPayment) ? "completed" : "pending",
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

    // ── 6. Insert order items + sides ────────────────────────────────────
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
    // Payment is confirmed before order creation for all methods (card charged
    // above, wallet deducted above, cash on delivery). Send receipt immediately.
    admin.functions.invoke("send-receipt-email", {
      body: { order_id: orderId },
    }).catch(() => {});

    // ── 7. Notify customer ───────────────────────────────────────────────
    await notifyUser(userId, '🍽️ Order Placed!', `Your order #${receiptNumber} has been received and is being prepared.`, {
      type: 'order_placed', order_id: orderId, receipt_number: receiptNumber,
    });

    // ── 8. Return the created order ──────────────────────────────────────
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
        tax_amount: serverTaxAmount,
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

// create-multi-restaurant-order
// Writes to master_orders + restaurant_orders + restaurant_order_items (new schema).
// Returns master_order_id (and order_group_id alias for backward-compat).
// Deploy: supabase functions deploy create-multi-restaurant-order --no-verify-jwt

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl  = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const stripeKey    = Deno.env.get("STRIPE_SECRET_KEY") ?? Deno.env.get("STRIPE_SK") ?? "";
const admin        = createClient(supabaseUrl, supabaseKey);

// ── Stripe helpers ─────────────────────────────────────────────────────────────
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
async function notifyUser(userId: string, title: string, body: string, data: Record<string, string>) {
  try {
    const { data: user } = await admin.from("users").select("fcm_token").eq("id", userId).maybeSingle();
    if (!user?.fcm_token) return;
    await fetch(`${supabaseUrl}/functions/v1/send-fcm-notification`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${supabaseKey}` },
      body: JSON.stringify({ token: user.fcm_token, title, body, data }),
    });
  } catch { /* non-critical */ }
}

async function getStripeCustomerId(userId: string): Promise<string | null> {
  const { data } = await admin.from("users").select("stripe_customer_id").eq("id", userId).maybeSingle();
  return data?.stripe_customer_id ?? null;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}

function round2(n: number) { return Math.round(n * 100) / 100; }

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R    = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a    = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function getConfig(key: string, fallback: number): Promise<number> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  return data ? parseFloat(data.value) : fallback;
}

async function calcRestaurantDeliveryFee(
  restaurant: { latitude: number | null; longitude: number | null; delivery_fee: number | null },
  deliveryLat: number,
  deliveryLng: number,
): Promise<{ fee: number; distanceKm: number | null }> {
  if (restaurant.delivery_fee && restaurant.delivery_fee > 0) {
    let distKm: number | null = null;
    if (restaurant.latitude && restaurant.longitude) {
      distKm = round2(haversineKm(restaurant.latitude, restaurant.longitude, deliveryLat, deliveryLng));
    }
    return { fee: round2(restaurant.delivery_fee), distanceKm: distKm };
  }
  if (restaurant.latitude && restaurant.longitude) {
    const km      = haversineKm(restaurant.latitude, restaurant.longitude, deliveryLat, deliveryLng);
    const miles   = km * 0.621371;
    const baseFee = await getConfig("delivery_base_fee", 2.0);
    const perMile = await getConfig("delivery_per_mile_fee", 2.0);
    const baseMi  = await getConfig("delivery_base_miles", 0.0);
    const surge   = await getConfig("delivery_surge_multiplier", 1.0);
    const minFee  = await getConfig("min_delivery_fee", 2.0);
    const extraMi = Math.max(0, miles - baseMi);
    const raw     = (baseFee + extraMi * perMile) * surge;
    return { fee: round2(Math.max(raw, minFee)), distanceKm: round2(km) };
  }
  const flat = await getConfig("delivery_base_fee", 2.0);
  const min  = await getConfig("min_delivery_fee", 2.0);
  return { fee: round2(Math.max(flat, min)), distanceKm: null };
}

interface IncomingItem {
  menu_item_id: string;
  quantity: number;
  side_ids?: string[];
  notes?: string;
}

interface IncomingRestaurantOrder {
  restaurant_id: string;
  items: IncomingItem[];
}

interface CreateMultiOrderRequest {
  customer_id: string;
  restaurant_orders: IncomingRestaurantOrder[];
  delivery_address: string;
  delivery_latitude: number;
  delivery_longitude: number;
  payment_method: string;
  client_delivery_fee?: number;
  notes?: string;
  contactless_delivery?: boolean;
  driver_tip?: number;
  scheduled_for?: string;
  // Payment confirmation fields (at least one required for card payments)
  payment_intent_id?: string;          // Payment Sheet: PI already confirmed by Flutter
  saved_card_payment_method_id?: string; // Saved card: charge server-side before creating order
  stripe_currency?: string;            // Currency for saved-card charge (default: jmd)
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: CreateMultiOrderRequest;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const {
    customer_id, restaurant_orders,
    delivery_address, delivery_latitude, delivery_longitude,
    payment_method, client_delivery_fee, notes,
    contactless_delivery, driver_tip,
    payment_intent_id, saved_card_payment_method_id,
    stripe_currency,
  } = body;

  if (!customer_id || !restaurant_orders?.length || !delivery_address) {
    return json({ error: "Missing required fields: customer_id, restaurant_orders, delivery_address" }, 400);
  }
  if (restaurant_orders.length < 2) {
    return json({ error: "Use place-order for single-restaurant orders" }, 400);
  }

  // ── Validate multi-restaurant feature is enabled ─────────────────────────
  const enabled = await getConfig("enable_multi_restaurant_orders", 1);
  if (enabled === 0) {
    return json({ error: "Multi-restaurant ordering is currently unavailable." }, 400);
  }

  const maxRest = await getConfig("max_restaurants_per_order", 3);
  if (restaurant_orders.length > maxRest) {
    return json({ error: `Maximum ${maxRest} restaurants allowed per order.` }, 400);
  }

  const isCard   = payment_method === "stripe" || payment_method === "card";
  const isWallet = payment_method === "wallet";

  // ── Load config ───────────────────────────────────────────────────────────
  const extraStopFeeConfig    = await getConfig("extra_stop_fee", 2.0);
  const defaultCommissionRate = await getConfig("default_commission_rate", 0.15);
  const platformFeeRate       = await getConfig("platform_service_fee_rate", 0.05);

  // ── Load restaurants ──────────────────────────────────────────────────────
  const restaurantIds = restaurant_orders.map((o) => o.restaurant_id);
  const { data: restaurants, error: restErr } = await admin
    .from("restaurants")
    .select("id, name, latitude, longitude, delivery_fee, commission_rate, estimated_delivery_time")
    .in("id", restaurantIds);

  if (restErr || !restaurants?.length) {
    return json({ error: "Failed to load restaurant data" }, 500);
  }
  const restaurantMap = new Map(restaurants.map((r: any) => [r.id, r]));

  // ── Load menu items ───────────────────────────────────────────────────────
  const allItemIds = restaurant_orders.flatMap((o) => o.items.map((i) => i.menu_item_id));
  const { data: menuItems, error: menuErr } = await admin
    .from("menus")
    .select("id, name, price, discount, is_available, restaurant_id")
    .in("id", allItemIds);

  if (menuErr) return json({ error: "Failed to load menu item data" }, 500);
  const menuMap = new Map((menuItems ?? []).map((m: any) => [m.id, m]));

  // ── Load sides ────────────────────────────────────────────────────────────
  const allSideIds = restaurant_orders.flatMap((o) => o.items.flatMap((i) => i.side_ids ?? []));
  const sideMap    = new Map<string, { id: string; name: string; price: number }>();
  if (allSideIds.length > 0) {
    const { data: sides } = await admin
      .from("menu_item_sides")
      .select("id, name, price")
      .in("id", allSideIds);
    (sides ?? []).forEach((s: any) => sideMap.set(s.id, s));
  }

  // ── Per-restaurant calculations ───────────────────────────────────────────
  let totalSubtotal    = 0;
  let totalDeliveryFee = 0;

  interface RestaurantCalc {
    restaurant_id: string;
    subtotal: number;
    deliveryFee: number;
    distanceKm: number | null;
    items: Array<{
      menu_item_id: string;
      item_name:    string;
      price:        number;
      quantity:     number;
      notes?:       string;
      sides:        Array<{ side_name: string; side_price: number }>;
    }>;
  }

  const perRestaurant: RestaurantCalc[] = [];

  for (const order of restaurant_orders) {
    const restaurant = restaurantMap.get(order.restaurant_id);
    if (!restaurant) return json({ error: `Restaurant ${order.restaurant_id} not found` }, 404);

    const { fee, distanceKm } = await calcRestaurantDeliveryFee(
      restaurant, delivery_latitude, delivery_longitude,
    );

    let subtotal = 0;
    const processedItems: RestaurantCalc["items"] = [];

    for (const item of order.items) {
      const menuItem = menuMap.get(item.menu_item_id);
      if (!menuItem) return json({ error: `Menu item ${item.menu_item_id} not found` }, 404);
      if (menuItem.is_available === false) {
        return json({ error: `${menuItem.name} is currently unavailable` }, 400);
      }
      if (menuItem.restaurant_id !== order.restaurant_id) {
        return json({ error: `Item ${menuItem.name} does not belong to this restaurant` }, 400);
      }
      const disc   = menuItem.discount ?? 0;
      const price  = disc > 0 ? round2(menuItem.price - (menuItem.price * disc / 100)) : menuItem.price;
      const sides  = (item.side_ids ?? []).map((sid) => {
        const s = sideMap.get(sid);
        return s ? { side_name: s.name, side_price: s.price } : null;
      }).filter(Boolean) as Array<{ side_name: string; side_price: number }>;
      const sideTotal = sides.reduce((s, x) => s + x.side_price, 0);
      subtotal += (price + sideTotal) * item.quantity;
      processedItems.push({ menu_item_id: item.menu_item_id, item_name: menuItem.name,
        price: price + sideTotal, quantity: item.quantity, notes: item.notes, sides });
    }

    subtotal = round2(subtotal);
    totalSubtotal    += subtotal;
    totalDeliveryFee += fee;
    perRestaurant.push({ restaurant_id: order.restaurant_id, subtotal, deliveryFee: fee, distanceKm, items: processedItems });
  }

  totalSubtotal    = round2(totalSubtotal);
  const serverDeliveryFee = round2(totalDeliveryFee);
  totalDeliveryFee = (client_delivery_fee != null && client_delivery_fee > 0)
    ? round2(client_delivery_fee) : serverDeliveryFee;

  if (client_delivery_fee != null && client_delivery_fee > 0 && serverDeliveryFee > 0) {
    for (const calc of perRestaurant) {
      calc.deliveryFee = round2(totalDeliveryFee * (calc.deliveryFee / serverDeliveryFee));
    }
  }

  const extraStopFee = round2(extraStopFeeConfig * (restaurant_orders.length - 1));
  const platformFee  = round2(totalSubtotal * platformFeeRate);
  const grandTotal   = round2(totalSubtotal + totalDeliveryFee + extraStopFee + platformFee);

  // ── PAYMENT FIRST — no records are created until payment is confirmed ────────

  let confirmedPaymentIntentId: string | null = null;

  if (isWallet) {
    // Deduct wallet — if this succeeds, records are created below
    const { error: walletErr } = await admin.rpc("wallet_deduct", {
      p_user_id:     customer_id,
      p_amount:      grandTotal,
      p_description: "Multi-restaurant order payment",
    });
    if (walletErr) {
      const msg = walletErr.message ?? "";
      return json({
        error: msg.toLowerCase().includes("insufficient")
          ? "Insufficient wallet balance." : "Wallet payment failed.",
      }, 402);
    }

  } else if (saved_card_payment_method_id) {
    // Off-session saved card charge — charge first, create order only on success
    if (!stripeKey) return json({ error: "Payment provider not configured." }, 500);
    const custId = await getStripeCustomerId(customer_id);
    const currency = stripe_currency ?? "usd";
    const amountCents = Math.round(grandTotal * 100);
    const pi = await stripePost("/payment_intents", {
      amount:           String(amountCents),
      currency,
      payment_method:   saved_card_payment_method_id,
      ...(custId ? { customer: custId } : {}),
      off_session:      "true",
      confirm:          "true",
      "metadata[type]":        "multi_restaurant_order",
      "metadata[customer_id]": customer_id,
    });
    const piStatus = pi.status as string;
    if (pi.error || (piStatus !== "succeeded" && piStatus !== "requires_capture")) {
      const errMsg = (pi.error as Record<string, unknown>)?.message as string
        ?? pi.message as string ?? "Card charge failed. Please try again.";
      return json({ error: errMsg }, 402);
    }
    confirmedPaymentIntentId = pi.id as string;

  } else if (payment_intent_id) {
    // Payment Sheet: Flutter already collected payment — verify it succeeded on Stripe
    if (!stripeKey) return json({ error: "Payment provider not configured." }, 500);
    const pi = await stripeGet(`/payment_intents/${encodeURIComponent(payment_intent_id)}`);
    const piStatus = pi.status as string;
    if (piStatus !== "succeeded" && piStatus !== "requires_capture") {
      return json({ error: "Payment not confirmed. Please complete payment first." }, 402);
    }
    // Verify amount matches (within 1 unit tolerance for rounding)
    const piAmount = pi.amount as number;
    const expectedCents = Math.round(grandTotal * 100);
    if (Math.abs(piAmount - expectedCents) > 1) {
      return json({ error: "Payment amount mismatch." }, 402);
    }
    confirmedPaymentIntentId = payment_intent_id;

  } else {
    // Card payment but no PI or saved card provided
    return json({
      error: "Payment required before order can be placed. Please complete payment first.",
    }, 402);
  }

  try {
    // ── 1. Generate master order number ──────────────────────────────────
    const now     = new Date();
    const dateStr = `${now.getFullYear()}${String(now.getMonth()+1).padStart(2,"0")}${String(now.getDate()).padStart(2,"0")}`;
    const { count: masterCount } = await admin
      .from("master_orders")
      .select("id", { count: "exact", head: true })
      .gte("created_at", new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString());

    const masterOrderNumber = `FD-${dateStr}-${String((masterCount ?? 0) + 1).padStart(4, "0")}`;

    // ── 2. Create master_order ────────────────────────────────────────────
    const masterOtp = `${1000 + Math.floor(Math.random() * 9000)}`;

    const { data: masterOrder, error: masterErr } = await admin
      .from("master_orders")
      .insert({
        customer_id,
        master_order_number:  masterOrderNumber,
        status:               "pending",   // restaurant accepts from here
        delivery_address,
        delivery_latitude,
        delivery_longitude,
        payment_method,
        payment_status:       "paid",      // always paid — we verified above
        subtotal:             totalSubtotal,
        delivery_fee:         totalDeliveryFee,
        extra_stop_fee:       extraStopFee,
        platform_fee:         platformFee,
        tax_amount:           0,
        discount:             0,
        total_amount:         grandTotal,
        notes:                notes ?? null,
        is_pickup:            false,
        contactless_delivery: contactless_delivery ?? false,
        driver_tip:           driver_tip ?? null,
        delivery_otp:         masterOtp,
      })
      .select()
      .single();

    if (masterErr || !masterOrder) throw new Error(`Failed to create master_order: ${masterErr?.message}`);

    const masterOrderId = masterOrder.id as string;

    // ── 3. Create restaurant_orders + items ───────────────────────────────
    const { count: restOrderCount } = await admin
      .from("restaurant_orders")
      .select("id", { count: "exact", head: true })
      .gte("created_at", new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString());

    const subOrderDetails: Array<Record<string, unknown>> = [];

    for (let seq = 0; seq < perRestaurant.length; seq++) {
      const calc       = perRestaurant[seq];
      const restaurant = restaurantMap.get(calc.restaurant_id)!;
      const commRate   = restaurant.commission_rate ?? defaultCommissionRate;
      const commAmt    = round2(calc.subtotal * commRate);
      const otp        = `${1000 + Math.floor(Math.random() * 9000)}`;
      const roNumber   = `RST-${dateStr}-${String((restOrderCount ?? 0) + seq + 1).padStart(4, "0")}`;

      const { data: restOrder, error: roErr } = await admin
        .from("restaurant_orders")
        .insert({
          master_order_id:        masterOrderId,
          restaurant_id:          calc.restaurant_id,
          restaurant_order_number: roNumber,
          status:                 isCard ? "pending" : "pending",  // restaurant accepts after payment
          subtotal:               calc.subtotal,
          delivery_fee:           calc.deliveryFee,
          commission_rate:        commRate,
          commission_amount:      commAmt,
          distance_km:            calc.distanceKm,
          sequence_in_group:      seq + 1,
          delivery_otp:           otp,
          notes:                  notes ?? null,
        })
        .select()
        .single();

      if (roErr || !restOrder) throw new Error(`Failed to create restaurant_order: ${roErr?.message}`);

      const restaurantOrderId = restOrder.id as string;

      // ── Insert into restaurant_order_items (new schema) ────────────────────
      const roiRows = calc.items.map((item) => ({
        restaurant_order_id: restaurantOrderId,
        menu_item_id:        item.menu_item_id,
        item_name:           item.item_name,
        price:               item.price,
        quantity:            item.quantity,
        notes:               item.notes ?? null,
      }));
      const { data: insertedRoiItems, error: roiErr } = await admin
        .from("restaurant_order_items").insert(roiRows).select("id, menu_item_id");
      if (roiErr) throw new Error(`Failed to insert restaurant_order_items: ${roiErr.message}`);

      for (let i = 0; i < calc.items.length; i++) {
        const item = calc.items[i];
        if (item.sides.length > 0 && insertedRoiItems?.[i]) {
          await admin.from("restaurant_order_item_sides").insert(
            item.sides.map((s) => ({
              restaurant_order_item_id: insertedRoiItems[i].id,
              side_name: s.side_name, side_price: s.side_price,
            }))
          );
        }
      }

      // ── Also insert into legacy orders table (restaurant/driver/admin flows) ─
      const subOrderId = crypto.randomUUID();
      const { error: orderErr } = await admin.from("orders").insert({
        id:                      subOrderId,
        user_id:                 customer_id,
        restaurant_id:           calc.restaurant_id,
        subtotal:                calc.subtotal,
        delivery_fee:            calc.deliveryFee,
        tax_amount:              0,
        discount:                0,
        total_amount:            round2(calc.subtotal + calc.deliveryFee),
        status:                  "pending",    // payment confirmed before reaching here
        delivery_address,
        delivery_latitude,
        delivery_longitude,
        notes:                   notes ?? null,
        payment_method,
        payment_status:          "completed",  // already paid
        ordered_at:              now.toISOString(),
        delivery_otp:            otp,
        commission_rate:         commRate,
        commission_amount:       commAmt,
        distance_km:             calc.distanceKm,
        receipt_number:          masterOrderNumber,
        restaurant_order_number: roNumber,
        is_multi_restaurant:     true,
        order_group_id:          masterOrderId,
        sequence_in_group:       seq + 1,
      });
      if (orderErr) throw new Error(`Failed to create orders entry: ${orderErr.message}`);

      // Insert into legacy order_items
      const legacyItemRows = calc.items.map((item) => ({
        order_id:     subOrderId,
        menu_item_id: item.menu_item_id,
        item_name:    item.item_name,
        price:        item.price,
        quantity:     item.quantity,
        notes:        item.notes ?? null,
      }));
      const { data: insertedLegacyItems, error: legacyItemsErr } = await admin
        .from("order_items").insert(legacyItemRows).select("id, menu_item_id");
      if (legacyItemsErr) throw new Error(`Failed to insert order_items: ${legacyItemsErr.message}`);

      // Insert into legacy order_item_sides
      for (let i = 0; i < calc.items.length; i++) {
        const item = calc.items[i];
        if (item.sides.length > 0 && insertedLegacyItems?.[i]) {
          await admin.from("order_item_sides").insert(
            item.sides.map((s) => ({
              order_item_id: insertedLegacyItems[i].id,
              side_name:     s.side_name,
              side_price:    s.side_price,
            }))
          );
        }
      }

      subOrderDetails.push({
        restaurant_order_id:     restaurantOrderId,
        restaurant_id:           calc.restaurant_id,
        restaurant_name:         restaurant.name,
        restaurant_order_number: roNumber,
        subtotal:                calc.subtotal,
        delivery_fee:            calc.deliveryFee,
        distance_km:             calc.distanceKm,
        delivery_otp:            otp,
        sequence:                seq + 1,
      });
    }

    // ── 4. Notify customer ────────────────────────────────────────────────────
    await notifyUser(
      customer_id,
      '🍽️ Order Placed!',
      `Your order from ${restaurant_orders.length} restaurants has been placed. Order #${masterOrderNumber}`,
      { type: 'order_placed', master_order_id: masterOrderId, master_order_number: masterOrderNumber },
    );

    return json({
      success:               true,
      master_order_id:       masterOrderId,
      order_group_id:        masterOrderId,   // backward-compat alias
      master_order_number:   masterOrderNumber,
      restaurant_orders:     subOrderDetails,
      payment_status:        "paid",
      payment_intent_id:     confirmedPaymentIntentId,
      subtotal:              totalSubtotal,
      total_delivery_fee:    totalDeliveryFee,
      extra_stop_fee:        extraStopFee,
      platform_fee:          platformFee,
      grand_total:           grandTotal,
    });

  } catch (err: any) {
    // Rollback wallet deduction on failure
    if (isWallet) {
      await admin.rpc("wallet_credit", {
        p_user_id:     customer_id,
        p_amount:      grandTotal,
        p_description: "Multi-restaurant order refund (creation failed)",
      }).catch(() => null);
    }
    return json({ error: `Order creation failed: ${err?.message ?? err}` }, 500);
  }
});

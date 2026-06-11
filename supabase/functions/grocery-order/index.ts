// grocery-order — Place a grocery order with server-side validation
// Verifies product availability, stock, prices from DB, calculates totals

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

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function getConfig(key: string, fallback: number): Promise<number> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  return data ? parseFloat(data.value) : fallback;
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

async function getTaxRateForLocation(
  lat: number | null | undefined,
  lng: number | null | undefined,
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
      inside = haversineKm(lat, lng, region.latitude, region.longitude) <= region.radius_km;
    }
    if (inside) {
      if (!region.tax_enabled) return 0;
      return region.tax_rate ?? globalTaxRate;
    }
  }
  return 0;
}

function generatePickupCode(): string {
  return Math.random().toString(36).substring(2, 8).toUpperCase();
}

function generateOtp(): string {
  return String(Math.floor(1000 + Math.random() * 9000));
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

  const storeId = body.store_id as string;
  const userId = body.user_id as string;
  const items = body.items as Array<{ menu_item_id: string; quantity: number }>;
  const isPickup = body.is_pickup === true;
  const paymentMethod = (body.payment_method as string) ?? "cash";
  const deliveryAddress = body.delivery_address as string | undefined;
  const deliveryLat = body.delivery_latitude as number | undefined;
  const deliveryLng = body.delivery_longitude as number | undefined;
  const driverTip = (body.driver_tip as number) ?? 0;
  const specialInstructions = body.special_instructions as string | undefined;
  const promoCode = (body.promo_code as string | undefined)?.toUpperCase();
  const savedCardPaymentMethodId = body.saved_card_payment_method_id as string | undefined;
  const incomingPaymentIntentId = body.payment_intent_id as string | undefined;

  if (!storeId || !userId || !items || items.length === 0) {
    return json({ error: "Missing required fields: store_id, user_id, items" }, 400);
  }

  try {
    // ── 1. Fetch store ──────────────────────────────────────────────────
    const { data: store, error: storeErr } = await admin
      .from("restaurants")
      .select("*")
      .eq("id", storeId)
      .single();

    if (storeErr || !store) {
      return json({ error: "Store not found" }, 404);
    }

    if (!store.is_open) {
      return json({ error: "Store is currently closed" }, 400);
    }

    // ── 2. Verify products from DB ──────────────────────────────────────
    const productIds = items.map((i) => i.menu_item_id);
    const { data: products, error: prodErr } = await admin
      .from("menus")
      .select("id, name, price, discount, is_available, in_stock, max_quantity, product_type")
      .in("id", productIds);

    if (prodErr || !products) {
      return json({ error: "Could not verify products", details: prodErr?.message ?? "No products returned" }, 500);
    }

    const productMap = new Map(products.map((p: Record<string, unknown>) => [p.id as string, p]));
    let subtotal = 0;
    const verifiedItems: Array<Record<string, unknown>> = [];

    for (const item of items) {
      const dbProduct = productMap.get(item.menu_item_id) as Record<string, unknown> | undefined;
      if (!dbProduct) {
        return json({ error: `Product ${item.menu_item_id} not found` }, 400);
      }
      if (dbProduct.product_type !== "grocery") {
        return json({ error: `"${dbProduct.name}" is not a grocery product` }, 400);
      }
      if (!dbProduct.is_available) {
        return json({ error: `"${dbProduct.name}" is currently unavailable` }, 400);
      }
      if (!dbProduct.in_stock) {
        return json({ error: `"${dbProduct.name}" is out of stock` }, 400);
      }
      if (dbProduct.max_quantity && item.quantity > (dbProduct.max_quantity as number)) {
        return json({
          error: `Maximum quantity for "${dbProduct.name}" is ${dbProduct.max_quantity}`,
        }, 400);
      }

      const basePrice = dbProduct.price as number;
      const discountPct = (dbProduct.discount as number) ?? 0;
      const price = discountPct > 0 ? Math.round(basePrice * (1 - discountPct / 100) * 100) / 100 : basePrice;
      const lineTotal = price * item.quantity;
      subtotal += lineTotal;

      verifiedItems.push({
        menu_item_id: item.menu_item_id,
        name: dbProduct.name,
        unit_price: price,
        quantity: item.quantity,
        line_total: lineTotal,
      });
    }

    // ── 3. Fetch config ─────────────────────────────────────────────────
    const [globalTaxRate, taxEnabledFlag, serviceFeeRate, baseFee, perKmFee, baseKm, maxKm, surgeMultiplier, defaultDeliveryFee, peakAddonFee, peakStart, peakEnd, peakStart2, peakEnd2] =
      await Promise.all([
        getConfig("tax_rate", 0.0),
        getConfig("tax_enabled", 0),
        getConfig("platform_service_fee_rate", 0.05),
        getConfig("delivery_base_fee", 50.0),
        getConfig("delivery_per_km_fee", 30.0),
        getConfig("delivery_base_km", 3.0),
        getConfig("delivery_max_km", 25.0),
        getConfig("delivery_surge_multiplier", 1.0),
        getConfig("default_delivery_fee", 50.0),
        getConfig("peak_addon_fee", 0),
        getConfig("peak_hours_start", 11),
        getConfig("peak_hours_end", 14),
        getConfig("peak_hours_start_2", 18),
        getConfig("peak_hours_end_2", 21),
      ]);
    const isTaxEnabled = taxEnabledFlag > 0;

    // Check if current hour is within a peak window
    const currentHour = new Date().getUTCHours();
    const isPeak = peakAddonFee > 0 && (
      (currentHour >= peakStart && currentHour < peakEnd) ||
      (currentHour >= peakStart2 && currentHour < peakEnd2)
    );
    const peakFee = isPeak ? peakAddonFee : 0;

    // ── 4. Delivery fee ─────────────────────────────────────────────────
    let deliveryFee = 0;
    let deliveryDistanceKm: number | null = null;

    if (!isPickup) {
      deliveryFee = store.delivery_fee ?? defaultDeliveryFee;

      if (deliveryLat && deliveryLng && store.latitude && store.longitude) {
        deliveryDistanceKm = haversineKm(
          store.latitude, store.longitude, deliveryLat, deliveryLng
        );
        if (deliveryDistanceKm > maxKm) {
          return json({
            error: `Delivery distance (${deliveryDistanceKm.toFixed(1)} km) exceeds max of ${maxKm} km`,
          }, 400);
        }
        const extraKm = Math.max(0, deliveryDistanceKm - baseKm);
        const calcFee = (baseFee + extraKm * perKmFee) * surgeMultiplier + peakFee;
        deliveryFee = Math.max(deliveryFee, Math.round(calcFee * 100) / 100);
      } else {
        deliveryFee = Math.round((deliveryFee * surgeMultiplier + peakFee) * 100) / 100;
      }
    }

    // ── 5. Subscription eligibility (consumed atomically after order create) ──
    let eligibleSubscriptionId: string | null = null;
    if (!isPickup && deliveryFee > 0) {
      const { data: activeSub } = await admin
        .from("user_subscriptions")
        .select("id")
        .eq("user_id", userId)
        .in("status", ["active", "pending"])
        .not("plan_type", "is", null)
        .gt("deliveries_remaining", 0)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (activeSub?.id) {
        eligibleSubscriptionId = activeSub.id as string;
      }
    }

    // ── 6. Promo code ───────────────────────────────────────────────────
    let promoDiscount = 0;
    let promoId: string | null = null;

    if (promoCode) {
      const { data: promo } = await admin
        .from("promo_codes")
        .select("*")
        .eq("code", promoCode)
        .eq("is_active", true)
        .maybeSingle();

      if (promo) {
        if ((!promo.expires_at || new Date(promo.expires_at) >= new Date()) &&
            (!promo.max_uses || promo.usage_count < promo.max_uses) &&
            (!promo.min_order_amount || subtotal >= promo.min_order_amount)) {
          promoDiscount = promo.discount_type === "percentage"
            ? Math.round(subtotal * promo.discount_value / 100 * 100) / 100
            : Math.min(promo.discount_value, subtotal);
          promoId = promo.id;

          // Increment usage count
          await admin
            .from("promo_codes")
            .update({ usage_count: promo.usage_count + 1 })
            .eq("id", promo.id);
        }
      }
    }

    // ── 7. Calculate totals ─────────────────────────────────────────────
    // Tax: gated by tax_enabled flag from app_config (master on/off switch).
    const effectiveTaxRate = (isTaxEnabled && !isPickup)
      ? await getTaxRateForLocation(deliveryLat, deliveryLng, globalTaxRate)
      : 0;
    const tax = Math.round(subtotal * effectiveTaxRate * 100) / 100;
    // Service fee from app_config (platform_service_fee_rate).
    const platformServiceFee = Math.round(subtotal * serviceFeeRate * 100) / 100;
    const orderTotal = Math.round((subtotal - promoDiscount + deliveryFee + platformServiceFee + tax) * 100) / 100;
    const grandTotal = Math.round((orderTotal + driverTip) * 100) / 100;

    // ── 8. Create order ─────────────────────────────────────────────────
    // PAYMENT GATE:
    //   card   → charge Stripe BEFORE insert; order only created on success
    //   wallet → deduct BEFORE insert (atomic); if deduction fails, no order created
    //   cash   → 'preparing' immediately (collected on delivery)
    const isCardPayment = paymentMethod === "stripe" || paymentMethod === "card";
    const isWalletPayment = paymentMethod === "wallet";
    const initialStatus = "preparing";

    const orderId: string = crypto.randomUUID();

    // ── 8a. Wallet gate ───────────────────────────────────────────────────
    if (isWalletPayment) {
      const { error: walletErr } = await admin.rpc("wallet_deduct", {
        p_user_id:     userId,
        p_amount:      grandTotal,
        p_description: `Grocery order payment`,
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

    // ── 8b. Card gate — charge/verify BEFORE inserting the order ─────────
    // Saved card (single store): charge now.
    // Pre-charged PI (multi-store): caller already charged the full total,
    //   just verify the PI succeeded before creating this store's sub-order.
    if (isCardPayment) {
      if (!stripeKey) {
        return json({ error: "Payment provider not configured." }, 500);
      }
      if (incomingPaymentIntentId) {
        // Multi-store path: PI was pre-charged by Flutter for the full order total.
        // Verify it succeeded — no amount check (each sub-order is a portion of total).
        const pi = await stripeGet(`/payment_intents/${encodeURIComponent(incomingPaymentIntentId)}`);
        const piStatus = pi.status as string;
        if (piStatus !== "succeeded" && piStatus !== "requires_capture") {
          return json({ error: "Payment not confirmed. Please complete payment first." }, 402);
        }
      } else if (savedCardPaymentMethodId) {
        // Single-store path: charge now.
        const custId = await getStripeCustomerId(userId);
        const pi = await stripePost("/payment_intents", {
          amount:          String(Math.round(grandTotal * 100)),
          currency:        "usd",
          payment_method:  savedCardPaymentMethodId,
          ...(custId ? { customer: custId } : {}),
          off_session:     "true",
          confirm:         "true",
          "metadata[type]":    "grocery_order",
          "metadata[user_id]": userId,
        });
        const piStatus = pi.status as string;
        if (pi.error || (piStatus !== "succeeded" && piStatus !== "requires_capture")) {
          const errMsg = ((pi.error as Record<string, unknown>)?.message as string)
            ?? "Card charge failed. Please try a different card.";
          return json({ error: errMsg }, 402);
        }
      } else {
        return json({ error: "Card payment information required. Please select a saved card." }, 402);
      }
    }

    // Generate GRO- receipt number
    const today = new Date().toISOString().split("T")[0];
    const { count: todayCount } = await admin
      .from("orders")
      .select("*", { count: "exact", head: true })
      .gte("ordered_at", today);
    const receiptNumber = `GRO-${today.replace(/-/g, "")}-${String((todayCount ?? 0) + 1).padStart(4, "0")}`;

    const orderData: Record<string, unknown> = {
      id: orderId,
      user_id: userId,
      restaurant_id: storeId,
      status: initialStatus,
      subtotal,
      delivery_fee: deliveryFee,
      tax_amount: tax,
      total_amount: grandTotal,
      payment_method: paymentMethod,
      payment_status: (isCardPayment || isWalletPayment) ? "completed" : "pending",
      is_pickup: isPickup,
      special_instructions: specialInstructions ?? null,
      delivery_address: isPickup ? store.address : deliveryAddress,
      delivery_latitude: isPickup ? store.latitude : deliveryLat,
      delivery_longitude: isPickup ? store.longitude : deliveryLng,
      driver_tip: driverTip,
      promo_code: promoCode ?? null,
      discount_amount: promoDiscount,
      pickup_code: isPickup ? generatePickupCode() : null,
      delivery_otp: !isPickup ? generateOtp() : null,
      receipt_number: receiptNumber,
    };

    const { data: order, error: orderErr } = await admin
      .from("orders")
      .insert(orderData)
      .select()
      .single();

    if (orderErr) {
      return json({ error: "Failed to create order", details: orderErr.message }, 500);
    }

    // ── 9. Create order items ───────────────────────────────────────────
    const orderItems = verifiedItems.map((v) => ({
      order_id: orderId,
      menu_item_id: v.menu_item_id,
      quantity: v.quantity,
      price: v.unit_price,
      subtotal: v.line_total,
      item_name: v.name,
    }));

    const { error: itemsErr } = await admin.from("order_items").insert(orderItems);
    if (itemsErr) {
      // Rollback order
      await admin.from("orders").delete().eq("id", orderId);
      return json({ error: "Failed to create order items", details: itemsErr.message }, 500);
    }

    // ── 10. Try applying subscription delivery (atomic DB function) ────────
    let subscriptionDeliveryFree = false;
    let subscriptionId: string | null = null;
    let finalDeliveryFee = deliveryFee;
    let finalGrandTotal = grandTotal;

    if (!isPickup && deliveryFee > 0 && eligibleSubscriptionId) {
      const { data: usedSub, error: useSubErr } = await admin.rpc(
        "use_subscription_delivery",
        {
          p_subscription_id: eligibleSubscriptionId,
          p_order_id: orderId,
        }
      );

      if (useSubErr) {
        console.error("[grocery-order] use_subscription_delivery failed", useSubErr);
      } else if (usedSub === true) {
        subscriptionDeliveryFree = true;
        subscriptionId = eligibleSubscriptionId;
        finalDeliveryFee = 0;

        const finalOrderTotal = Math.round((subtotal - promoDiscount + tax) * 100) / 100;
        finalGrandTotal = Math.round((finalOrderTotal + driverTip) * 100) / 100;

        await admin
          .from("orders")
          .update({
            delivery_fee: 0,
            total_amount: finalGrandTotal,
            updated_at: new Date().toISOString(),
          })
          .eq("id", orderId);
      }
    }

    // Payment confirmed before insert for all methods — send receipt immediately.
    admin.functions.invoke("send-receipt-email", {
      body: { order_id: orderId },
    }).catch(() => {});

    return json({
      success: true,
      order: {
        id: orderId,
        status: order.status,
        total: finalGrandTotal,
        subtotal,
        delivery_fee: finalDeliveryFee,
        tax,
        promo_discount: promoDiscount,
        driver_tip: driverTip,
        is_pickup: isPickup,
        subscription_delivery_free: subscriptionDeliveryFree,
        subscription_id: subscriptionId,
        pickup_code: order.pickup_code,
        delivery_otp: order.delivery_otp,
        receipt_number: receiptNumber,
        item_count: verifiedItems.length,
        delivery_distance_km: deliveryDistanceKm,
      },
      verified_items: verifiedItems,
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

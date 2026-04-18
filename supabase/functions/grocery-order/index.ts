// grocery-order — Place a grocery order with server-side validation
// Verifies product availability, stock, prices from DB, calculates totals

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
      .filter("id", "in", `(${productIds.map((id) => `"${id}"`).join(",")})`);

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
    const [taxRate, baseFee, perKmFee, baseKm, maxKm, surgeMultiplier, defaultDeliveryFee] =
      await Promise.all([
        getConfig("tax_rate", 0.10),
        getConfig("delivery_base_fee", 50.0),
        getConfig("delivery_per_km_fee", 30.0),
        getConfig("delivery_base_km", 3.0),
        getConfig("delivery_max_km", 25.0),
        getConfig("delivery_surge_multiplier", 1.0),
        getConfig("default_delivery_fee", 50.0),
      ]);

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
        const calcFee = (baseFee + extraKm * perKmFee) * surgeMultiplier;
        deliveryFee = Math.max(deliveryFee, Math.round(calcFee * 100) / 100);
      } else {
        deliveryFee = Math.round(deliveryFee * surgeMultiplier * 100) / 100;
      }
    }

    // ── 5. Promo code ───────────────────────────────────────────────────
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

    // ── 6. Calculate totals ─────────────────────────────────────────────
    const tax = Math.round(subtotal * taxRate * 100) / 100;
    const orderTotal = Math.round((subtotal - promoDiscount + deliveryFee + tax) * 100) / 100;
    const grandTotal = Math.round((orderTotal + driverTip) * 100) / 100;

    // ── 7. Create order ─────────────────────────────────────────────────
    // Generate GRO- receipt number
    const today = new Date().toISOString().split("T")[0];
    const { count: todayCount } = await admin
      .from("orders")
      .select("*", { count: "exact", head: true })
      .gte("ordered_at", today);
    const receiptNumber = `GRO-${today.replace(/-/g, "")}-${String((todayCount ?? 0) + 1).padStart(4, "0")}`;

    const orderData: Record<string, unknown> = {
      user_id: userId,
      restaurant_id: storeId,
      status: "pending",
      subtotal,
      delivery_fee: deliveryFee,
      tax_amount: tax,
      total_amount: grandTotal,
      payment_method: paymentMethod,
      payment_status: paymentMethod === "cash" ? "pending" : "processing",
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

    // ── 8. Create order items ───────────────────────────────────────────
    const orderItems = verifiedItems.map((v) => ({
      order_id: order.id,
      menu_item_id: v.menu_item_id,
      quantity: v.quantity,
      price: v.unit_price,
      subtotal: v.line_total,
      item_name: v.name,
    }));

    const { error: itemsErr } = await admin.from("order_items").insert(orderItems);
    if (itemsErr) {
      // Rollback order
      await admin.from("orders").delete().eq("id", order.id);
      return json({ error: "Failed to create order items", details: itemsErr.message }, 500);
    }

    // Send receipt email to customer (fire-and-forget)
    admin.functions.invoke("send-receipt-email", {
      body: { order_id: order.id },
    }).catch(() => {});

    return json({
      success: true,
      order: {
        id: order.id,
        status: order.status,
        total: grandTotal,
        subtotal,
        delivery_fee: deliveryFee,
        tax,
        promo_discount: promoDiscount,
        driver_tip: driverTip,
        is_pickup: isPickup,
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

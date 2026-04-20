// calculate-order-total — Server-authoritative order total calculation
// Validates cart items against the DB, applies tax, delivery fee, promo, loyalty, tips
// Returns the verified breakdown so the client can't tamper with amounts

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

// Haversine distance in km
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

async function getConfigJson(key: string, fallback: unknown): Promise<unknown> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  if (!data) return fallback;
  try { return JSON.parse(data.value); } catch { return fallback; }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const restaurantId = body.restaurant_id as string;
  const items = body.items as Array<{ menu_item_id: string; quantity: number; side_ids?: string[] }>;
  const promoCode = (body.promo_code as string | undefined)?.toUpperCase();
  const redeemPoints = (body.redeem_points as number | undefined) ?? 0;
  const userId = body.user_id as string;
  const driverTip = (body.driver_tip as number | undefined) ?? 0;
  const paymentMethod = (body.payment_method as string | undefined) ?? "cash";
  const isPickup = body.is_pickup === true;
  const deliveryLat = body.delivery_latitude as number | undefined;
  const deliveryLng = body.delivery_longitude as number | undefined;

  if (!restaurantId || !items || items.length === 0 || !userId) {
    return json({ error: "Missing required fields: restaurant_id, items, user_id" }, 400);
  }

  try {
    // ── 1. Fetch config in parallel ─────────────────────────────────────────
    const [
      taxRate,
      defaultDeliveryFee,
      baseFee,
      perKmFee,
      baseKm,
      maxKm,
      surgeMultiplier,
      loyaltyPointValue,
      loyaltyMaxRedemptionPct,
      cardFeePct,
      bankFeePct,
      cashFeePct,
      defaultCommissionRate,
      subscriptionMinCart,
      peakAddonFee,
      peakStart,
      peakEnd,
      peakStart2,
      peakEnd2,
    ] = await Promise.all([
      getConfig("tax_rate", 0.10),
      getConfig("default_delivery_fee", 50.0),
      getConfig("delivery_base_fee", 50.0),
      getConfig("delivery_per_km_fee", 30.0),
      getConfig("delivery_base_km", 3.0),
      getConfig("delivery_max_km", 25.0),
      getConfig("delivery_surge_multiplier", 1.0),
      getConfig("loyalty_point_value", 0.10),
      getConfig("loyalty_max_redemption_percent", 0.20),
      getConfig("card_fee_percent", 2.5),
      getConfig("bank_transfer_fee_percent", 1.0),
      getConfig("cash_fee_percent", 0),
      getConfig("default_commission_rate", 0.15),
      getConfig("subscription_min_cart", 15.0),
      getConfig("peak_addon_fee", 0),
      getConfig("peak_hours_start", 11),
      getConfig("peak_hours_end", 14),
      getConfig("peak_hours_start_2", 18),
      getConfig("peak_hours_end_2", 21),
    ]);

    // Check if current hour is within a peak window
    const currentHour = new Date().getUTCHours();
    const isPeak = peakAddonFee > 0 && (
      (currentHour >= peakStart && currentHour < peakEnd) ||
      (currentHour >= peakStart2 && currentHour < peakEnd2)
    );
    const peakFee = isPeak ? peakAddonFee : 0;

    // ── 2. Fetch restaurant ────────────────────────────────────────────────
    const { data: restaurant, error: restErr } = await admin
      .from("restaurants")
      .select("id, name, delivery_fee, commission_rate, latitude, longitude, eligible_for_subscription")
      .eq("id", restaurantId)
      .single();
    if (restErr || !restaurant) {
      return json({ error: "Restaurant not found" }, 404);
    }

    // ── 3. Verify menu items from DB (prevent price tampering) ─────────────
    const menuItemIds = items.map((i) => i.menu_item_id);
    const { data: menuItems, error: menuErr } = await admin
      .from("menus")
      .select("id, price, discounted_price, name, is_available")
      .in("id", menuItemIds);
    if (menuErr || !menuItems) {
      return json({ error: "Could not fetch menu items" }, 500);
    }

    const menuMap = new Map(menuItems.map((m: Record<string, unknown>) => [m.id as string, m]));
    let subtotal = 0;
    const verifiedItems: Array<Record<string, unknown>> = [];

    for (const item of items) {
      const dbItem = menuMap.get(item.menu_item_id) as Record<string, unknown> | undefined;
      if (!dbItem) {
        return json({ error: `Menu item ${item.menu_item_id} not found` }, 400);
      }
      if (dbItem.is_available === false) {
        return json({ error: `"${dbItem.name}" is currently unavailable` }, 400);
      }
      const price = (dbItem.discounted_price ?? dbItem.price) as number;
      let sideTotal = 0;

      // Verify sides if provided
      if (item.side_ids && item.side_ids.length > 0) {
        const { data: sides } = await admin
          .from("menu_item_sides")
          .select("id, name, price")
          .in("id", item.side_ids);
        if (sides) {
          for (const s of sides) {
            sideTotal += (s as Record<string, unknown>).price as number;
          }
        }
      }

      const lineTotal = (price + sideTotal) * item.quantity;
      subtotal += lineTotal;
      verifiedItems.push({
        menu_item_id: item.menu_item_id,
        name: dbItem.name,
        unit_price: price,
        side_total: sideTotal,
        quantity: item.quantity,
        line_total: lineTotal,
      });
    }

    // ── 4. Calculate delivery fee (distance-based if coords provided) ──────
    let deliveryFee = restaurant.delivery_fee ?? defaultDeliveryFee;
    let deliveryDistanceKm: number | null = null;

    // Check surge_zones table for zone-specific multiplier at delivery location
    let effectiveSurge = surgeMultiplier;
    if (deliveryLat && deliveryLng) {
      try {
        const now = new Date().toISOString();
        const { data: zones } = await admin
          .from("surge_zones")
          .select("latitude, longitude, radius_km, multiplier")
          .eq("is_active", true)
          .or(`ends_at.is.null,ends_at.gt.${now}`);
        if (zones && zones.length > 0) {
          for (const z of zones) {
            const dist = haversineKm(deliveryLat, deliveryLng, z.latitude, z.longitude);
            if (dist > z.radius_km && z.multiplier > effectiveSurge) {
              effectiveSurge = z.multiplier;
            }
          }
        }
      } catch { /* fall back to global config */ }
    }

    if (deliveryLat && deliveryLng && restaurant.latitude && restaurant.longitude) {
      deliveryDistanceKm = haversineKm(
        restaurant.latitude, restaurant.longitude,
        deliveryLat, deliveryLng
      );

      if (deliveryDistanceKm > maxKm) {
        return json({
          error: `Delivery distance (${deliveryDistanceKm.toFixed(1)} km) exceeds maximum of ${maxKm} km`,
        }, 400);
      }

      // Distance-based fee: base fee + extra per km beyond base distance
      const extraKm = Math.max(0, deliveryDistanceKm - baseKm);
      const calculatedFee = (baseFee + extraKm * perKmFee) * effectiveSurge + peakFee;
      // Use the higher of restaurant override or distance-based fee
      deliveryFee = Math.max(deliveryFee, Math.round(calculatedFee * 100) / 100);
    } else {
      // No coordinates — still apply surge to flat fee
      deliveryFee = Math.round((deliveryFee * effectiveSurge + peakFee) * 100) / 100;
    }

    // ── 4b. MealHub+ free-delivery eligibility (server-authoritative) ─────
    let subscriptionDeliveryFree = false;
    let subscriptionId: string | null = null;
    if (!isPickup) {
      const { data: activeSub } = await admin
        .from("user_subscriptions")
        .select("id, status, deliveries_remaining")
        .eq("user_id", userId)
        .in("status", ["active", "pending"])
        .not("plan_type", "is", null)
        .gt("deliveries_remaining", 0)
        .order("created_at", { ascending: false })
        .limit(1)
        .maybeSingle();

      if (activeSub) {
        subscriptionDeliveryFree = true;
        subscriptionId = activeSub.id as string;
        deliveryFee = 0;
      }
    }

    // ── 5. Tax ─────────────────────────────────────────────────────────────
    const taxAmount = Math.round(subtotal * taxRate * 100) / 100;

    // ── 6. Promo code validation ───────────────────────────────────────────
    let promoDiscount = 0;
    let promoId: string | null = null;
    let promoDetail: string | null = null;

    if (promoCode) {
      const { data: promo } = await admin
        .from("promo_codes")
        .select("*")
        .eq("code", promoCode)
        .eq("is_active", true)
        .maybeSingle();

      if (!promo) {
        return json({ error: "Invalid or expired promo code" }, 400);
      }
      // Server-side validation
      if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
        return json({ error: "Promo code has expired" }, 400);
      }
      if (promo.max_uses && promo.usage_count >= promo.max_uses) {
        return json({ error: "Promo code usage limit reached" }, 400);
      }
      if (promo.min_order_amount && subtotal < promo.min_order_amount) {
        return json({ error: `Minimum order of JMD$${promo.min_order_amount} required for this promo` }, 400);
      }

      if (promo.discount_type === "percentage") {
        promoDiscount = Math.round(subtotal * promo.discount_value / 100 * 100) / 100;
      } else {
        promoDiscount = Math.min(promo.discount_value, subtotal);
      }
      promoId = promo.id;
      promoDetail = `${promo.code}: ${promo.discount_type === "percentage" ? promo.discount_value + "%" : "JMD$" + promo.discount_value} off`;
    }

    // ── 7. Loyalty redemption validation ───────────────────────────────────
    let loyaltyDiscount = 0;
    let loyaltyPointsUsed = 0;

    if (redeemPoints > 0) {
      const { data: account } = await admin
        .from("loyalty_accounts")
        .select("points")
        .eq("user_id", userId)
        .maybeSingle();

      if (!account || account.points < redeemPoints) {
        return json({ error: "Insufficient loyalty points" }, 400);
      }

      const maxRedeemValue = subtotal * loyaltyMaxRedemptionPct;
      const requestedValue = redeemPoints * loyaltyPointValue;
      loyaltyDiscount = Math.min(requestedValue, maxRedeemValue);
      loyaltyPointsUsed = Math.min(
        redeemPoints,
        Math.floor(maxRedeemValue / loyaltyPointValue)
      );
    }

    // ── 8. Payment processing fee ──────────────────────────────────────────
    const feePct = paymentMethod === "card" ? cardFeePct
      : paymentMethod === "bank_transfer" ? bankFeePct
      : cashFeePct;
    
    const orderBeforeFees = subtotal - promoDiscount - loyaltyDiscount + deliveryFee + taxAmount;
    const paymentFee = Math.round(orderBeforeFees * feePct / 100 * 100) / 100;

    // ── 9. Commission ──────────────────────────────────────────────────────
    const commissionRate = restaurant.commission_rate ?? defaultCommissionRate;

    // ── 10. Final total ────────────────────────────────────────────────────
    const orderTotal = Math.max(
      deliveryFee,
      Math.round((orderBeforeFees + paymentFee) * 100) / 100
    );
    const grandTotal = Math.round((orderTotal + driverTip) * 100) / 100;
    const commissionAmount = Math.round(orderTotal * commissionRate * 100) / 100;

    return json({
      verified: true,
      breakdown: {
        items: verifiedItems,
        subtotal,
        tax_rate: taxRate,
        tax_amount: taxAmount,
        delivery_fee: deliveryFee,
        delivery_distance_km: deliveryDistanceKm,
        promo_discount: promoDiscount,
        promo_id: promoId,
        promo_detail: promoDetail,
        loyalty_discount: loyaltyDiscount,
        loyalty_points_used: loyaltyPointsUsed,
        payment_method: paymentMethod,
        payment_fee_percent: feePct,
        payment_fee: paymentFee,
        driver_tip: driverTip,
        commission_rate: commissionRate,
        commission_amount: commissionAmount,
        order_total: orderTotal,
        grand_total: grandTotal,
        subscription_delivery_free: subscriptionDeliveryFree,
        subscription_id: subscriptionId,
      },
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

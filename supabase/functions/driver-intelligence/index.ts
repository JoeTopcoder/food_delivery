// driver-intelligence — Comprehensive driver intelligence system
// Actions: score_order, calculate_payout, check_stacking, update_zone_demand,
//          get_driver_stats, update_performance, check_earnings_floor, get_recommendations
// Deploy: supabase functions deploy driver-intelligence --no-verify-jwt

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey  = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin       = createClient(supabaseUrl, serviceKey);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

// ── Config loader with in-memory cache (60s TTL) ───────────────────
const configCache: Record<string, { value: number; ts: number }> = {};
async function cfg(key: string, fallback: number): Promise<number> {
  const now = Date.now();
  if (configCache[key] && now - configCache[key].ts < 60_000) return configCache[key].value;
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  const val = data ? parseFloat(data.value) : fallback;
  configCache[key] = { value: val, ts: now };
  return val;
}

// ── Haversine distance (km) ────────────────────────────────────────
function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
            Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
            Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

// ════════════════════════════════════════════════════════════════════
// ACTION: score_order — AI-based order quality scoring
// ════════════════════════════════════════════════════════════════════
async function scoreOrder(body: Record<string, unknown>) {
  const orderId    = body.order_id as string;
  const driverId   = body.driver_id as string | null;
  const driverLat  = body.driver_lat as number | null;
  const driverLng  = body.driver_lng as number | null;

  if (!orderId) return json({ error: "order_id required" }, 400);

  // Fetch order
  const { data: order } = await admin.from("orders")
    .select("id, restaurant_id, delivery_fee, driver_tip, delivery_latitude, delivery_longitude, ordered_at, estimated_prep_minutes, subtotal")
    .eq("id", orderId).single();
  if (!order) return json({ error: "Order not found" }, 404);

  // Fetch restaurant location + prep stats
  const { data: rest } = await admin.from("restaurants")
    .select("id, latitude, longitude, name").eq("id", order.restaurant_id).single();

  let prepStats: Record<string, unknown> | null = null;
  if (rest) {
    const { data } = await admin.from("restaurant_prep_stats")
      .select("avg_prep_minutes, is_slow_flag").eq("restaurant_id", rest.id).maybeSingle();
    prepStats = data;
  }

  // Calculate distances
  const restLat = rest?.latitude ?? 0, restLng = rest?.longitude ?? 0;
  const dropLat = order.delivery_latitude ?? 0, dropLng = order.delivery_longitude ?? 0;
  const restToDropKm = haversineKm(restLat, restLng, dropLat, dropLng);

  let driverToRestKm = 0;
  if (driverLat && driverLng) {
    driverToRestKm = haversineKm(driverLat, driverLng, restLat, restLng);
  }
  const totalKm = driverToRestKm + restToDropKm;
  const totalMiles = totalKm * 0.621371;

  // Calculate payout via hybrid formula ($1.50/mile)
  const ratePerMile  = await cfg("driver_rate_per_mile", 1.50);
  const ratePerKm    = await cfg("driver_rate_per_km", 0.93);
  const ratePerMin   = await cfg("driver_rate_per_minute", 0.15);
  const waitPayPerMin = await cfg("driver_wait_pay_per_minute", 0.10);
  const basePayMin   = await cfg("driver_base_pay_minimum", 3.00);

  const prepMinutes = (prepStats?.avg_prep_minutes as number) ?? order.estimated_prep_minutes ?? 15;
  const driveMinutes = totalKm * 3; // ~3 min/km city driving
  const totalMinutes = prepMinutes + driveMinutes;

  const distancePay = totalMiles * ratePerMile;
  const timePay = driveMinutes * ratePerMin;
  const waitPay = Math.max(0, prepMinutes - 5) * waitPayPerMin; // first 5 min free
  const basePay = Math.max(basePayMin, distancePay + timePay + waitPay);

  // Get zone surge
  let surgeMult = 1.0;
  if (rest) {
    const { data: zones } = await admin.from("zones")
      .select("surge_multiplier, latitude, longitude, radius_km")
      .eq("is_active", true);
    if (zones) {
      for (const z of zones) {
        const dist = haversineKm(restLat, restLng, z.latitude, z.longitude);
        if (dist <= z.radius_km && z.surge_multiplier > surgeMult) {
          surgeMult = z.surge_multiplier;
        }
      }
    }
  }

  const tipEstimate = (order.driver_tip as number) ?? 0;
  const totalPayout = basePay * surgeMult + tipEstimate;
  const earningsPerKm = totalKm > 0 ? totalPayout / totalKm : 0;
  const earningsPerMile = totalMiles > 0 ? totalPayout / totalMiles : 0;
  const earningsPerHour = totalMinutes > 0 ? (totalPayout / totalMinutes) * 60 : 0;

  // Hour of day factor
  const hour = new Date().getHours();
  const isPeak = (hour >= 11 && hour < 14) || (hour >= 18 && hour < 21);
  const timeBonus = isPeak ? 8 : 0;

  // ── Score calculation (0–100) ─────────────────────────────────────
  // Dimension weights:
  //   Earnings/hour (0–30), Earnings/mile (0–20), Trip efficiency (0–15),
  //   Tip quality (0–10), Restaurant reliability (0–10), Peak bonus (0–8),
  //   Distance penalty (0–7)
  let score = 0;

  // 1. Earnings per hour (0–30) — $30/hr = max
  score += Math.min(30, (earningsPerHour / 30) * 30);

  // 2. Earnings per mile (0–20) — $3/mi = max
  score += Math.min(20, (earningsPerMile / 3) * 20);

  // 3. Trip efficiency: short + high pay (0–15)
  const efficiency = totalKm > 0 ? totalPayout / totalKm : 0;
  score += Math.min(15, (efficiency / 5) * 15);

  // 4. Tip quality (0–10)
  score += Math.min(10, (tipEstimate / 10) * 10);

  // 5. Restaurant reliability (0–10) — penalize slow restaurants
  const isSlow = prepStats?.is_slow_flag ?? false;
  score += isSlow ? 2 : 10;

  // 6. Peak hour bonus (0–8)
  score += timeBonus;

  // 7. Distance penalty — long distances reduce score (0–7)
  if (totalKm <= 3) score += 7;
  else if (totalKm <= 5) score += 5;
  else if (totalKm <= 8) score += 3;
  else if (totalKm <= 12) score += 1;
  // else 0

  score = Math.round(Math.max(0, Math.min(100, score)));

  // ── Label + recommendation ────────────────────────────────────────
  let label: string, recommendation: string, rejectReason: string | null = null;
  if (score >= 80) { label = "🔥 High Value"; recommendation = "strong_accept"; }
  else if (score >= 60) { label = "✅ Good"; recommendation = "accept"; }
  else if (score >= 40) { label = "⚠️ Average"; recommendation = "neutral"; }
  else { label = "❌ Bad Order"; recommendation = "reject"; rejectReason = `Low earnings: $${earningsPerHour.toFixed(2)}/hr`; }

  // ── Find alternative zone if rejecting ────────────────────────────
  let alternativeZone: string | null = null;
  if (recommendation === "reject" || recommendation === "neutral") {
    const { data: betterZones } = await admin.from("zones")
      .select("name, surge_multiplier, latitude, longitude")
      .gt("surge_multiplier", 1.0)
      .eq("is_active", true)
      .order("surge_multiplier", { ascending: false })
      .limit(1);
    if (betterZones?.length && driverLat && driverLng) {
      const z = betterZones[0];
      const distToZone = haversineKm(driverLat, driverLng, z.latitude, z.longitude);
      alternativeZone = `Move ${distToZone.toFixed(1)}km to ${z.name} for ${z.surge_multiplier}x demand`;
    }
  }

  // ── Persist score ─────────────────────────────────────────────────
  await admin.from("order_scores").upsert({
    order_id: orderId,
    score,
    label,
    earnings_per_km: earningsPerKm,
    earnings_per_hour: earningsPerHour,
    estimated_payout: totalPayout,
    estimated_minutes: totalMinutes,
    distance_km: totalKm,
    base_pay: basePay,
    estimated_tip: tipEstimate,
    surge_multiplier: surgeMult,
    restaurant_prep_minutes: prepMinutes,
    recommendation,
    reject_reason: rejectReason,
    alternative_zone: alternativeZone,
    scored_at: new Date().toISOString(),
  }, { onConflict: "order_id" });

  return json({
    score,
    label,
    recommendation,
    reject_reason: rejectReason,
    alternative_zone: alternativeZone,
    payout: {
      base_pay: +basePay.toFixed(2),
      distance_pay: +distancePay.toFixed(2),
      time_pay: +timePay.toFixed(2),
      wait_pay: +waitPay.toFixed(2),
      surge_multiplier: surgeMult,
      tip_estimate: tipEstimate,
      total_payout: +totalPayout.toFixed(2),
    },
    metrics: {
      distance_km: +totalKm.toFixed(2),
      distance_miles: +totalMiles.toFixed(2),
      estimated_minutes: Math.round(totalMinutes),
      earnings_per_km: +earningsPerKm.toFixed(2),
      earnings_per_mile: +earningsPerMile.toFixed(2),
      earnings_per_hour: +earningsPerHour.toFixed(2),
    },
    restaurant: {
      name: rest?.name,
      avg_prep_minutes: prepMinutes,
      is_slow: isSlow,
    },
    is_peak_hour: isPeak,
  });
}

// ════════════════════════════════════════════════════════════════════
// ACTION: calculate_payout — Hybrid pay formula
// ════════════════════════════════════════════════════════════════════
async function calculatePayout(body: Record<string, unknown>) {
  const distanceKm    = (body.distance_km as number) ?? 0;
  const durationMin   = (body.duration_minutes as number) ?? 0;
  const waitMinutes   = (body.wait_minutes as number) ?? 0;
  const tip           = (body.tip as number) ?? 0;
  const surgeMult     = (body.surge_multiplier as number) ?? 1.0;
  const driverTier    = (body.driver_tier as string) ?? "bronze";

  const ratePerMile  = await cfg("driver_rate_per_mile", 1.50);
  const ratePerKm     = await cfg("driver_rate_per_km", 0.93);
  const ratePerMin    = await cfg("driver_rate_per_minute", 0.15);
  const waitPayPerMin = await cfg("driver_wait_pay_per_minute", 0.10);
  const basePayMin    = await cfg("driver_base_pay_minimum", 3.00);
  const boostAmount   = await cfg("driver_boost_amount", 0.00);
  const commissionCap = await cfg("platform_commission_cap", 0.85);

  // Tier bonus multiplier
  const tierMultiplier: Record<string, number> = { bronze: 1.0, silver: 1.05, gold: 1.10, elite: 1.20 };
  const tierMult = tierMultiplier[driverTier] ?? 1.0;

  const totalMiles = distanceKm * 0.621371;
  const distancePay = totalMiles * ratePerMile;
  const timePay = durationMin * ratePerMin;
  const waitPay = Math.max(0, waitMinutes - 5) * waitPayPerMin;
  const basePay = Math.max(basePayMin, distancePay + timePay + waitPay);
  const boostPay = boostAmount;
  const surgePay = basePay * (surgeMult - 1);

  const totalBeforeTip = (basePay + surgePay + boostPay) * tierMult;
  const totalPayout = totalBeforeTip + tip;

  const totalMiles = distanceKm * 0.621371;
  const earningsPerKm = distanceKm > 0 ? totalPayout / distanceKm : 0;
  const earningsPerMile = totalMiles > 0 ? totalPayout / totalMiles : 0;
  const earningsPerHour = durationMin > 0 ? (totalPayout / durationMin) * 60 : 0;

  return json({
    breakdown: {
      distance_pay: +distancePay.toFixed(2),
      time_pay: +timePay.toFixed(2),
      wait_pay: +waitPay.toFixed(2),
      base_pay: +basePay.toFixed(2),
      surge_pay: +surgePay.toFixed(2),
      boost_pay: +boostPay.toFixed(2),
      tier_multiplier: tierMult,
      tip,
      total_payout: +totalPayout.toFixed(2),
    },
    metrics: {
      distance_km: +distanceKm.toFixed(2),
      distance_miles: +totalMiles.toFixed(2),
      duration_minutes: Math.round(durationMin),
      earnings_per_km: +earningsPerKm.toFixed(2),
      earnings_per_mile: +earningsPerMile.toFixed(2),
      earnings_per_hour: +earningsPerHour.toFixed(2),
    },
    commission_cap: commissionCap,
  });
}

// ════════════════════════════════════════════════════════════════════
// ACTION: check_stacking — Evaluate if orders can be batched
// ════════════════════════════════════════════════════════════════════
async function checkStacking(body: Record<string, unknown>) {
  const driverId  = body.driver_id as string;
  const orderIds  = body.order_ids as string[];

  if (!driverId || !orderIds?.length) return json({ error: "driver_id and order_ids required" }, 400);
  if (orderIds.length > 3) return json({ error: "Maximum 3 orders for stacking" }, 400);

  const maxStack   = await cfg("driver_max_stack_orders", 3);
  const maxExtraKm = await cfg("driver_stack_distance_km", 2.0);
  const minIncrease = await cfg("driver_stack_min_increase", 0.30);
  const maxDelay   = await cfg("driver_stack_max_delay", 10);

  // Fetch all orders with restaurant info
  const { data: orders } = await admin.from("orders")
    .select("id, restaurant_id, delivery_latitude, delivery_longitude, delivery_fee, driver_tip, restaurants(latitude, longitude, name)")
    .in("id", orderIds);

  if (!orders?.length) return json({ error: "No valid orders found" }, 404);

  // Fetch driver position
  const { data: driver } = await admin.from("drivers")
    .select("current_latitude, current_longitude").eq("id", driverId).single();

  const dLat = driver?.current_latitude ?? 0, dLng = driver?.current_longitude ?? 0;

  // Calculate individual vs stacked payouts ($1.50/mile)
  const ratePerMile = await cfg("driver_rate_per_mile", 1.50);
  const ratePerKm = await cfg("driver_rate_per_km", 0.93);
  const basePayMin = await cfg("driver_base_pay_minimum", 3.00);

  let individualTotal = 0;
  const orderDetails: Array<{ id: string; restLat: number; restLng: number; dropLat: number; dropLng: number; payout: number; name: string }> = [];

  for (const o of orders) {
    const restInfo = o.restaurants as Record<string, unknown> | null;
    const rLat = (restInfo?.latitude as number) ?? 0;
    const rLng = (restInfo?.longitude as number) ?? 0;
    const dLat2 = o.delivery_latitude ?? 0;
    const dLng2 = o.delivery_longitude ?? 0;

    const km = haversineKm(dLat, dLng, rLat, rLng) + haversineKm(rLat, rLng, dLat2, dLng2);
    const miles = km * 0.621371;
    const payout = Math.max(basePayMin, miles * ratePerMile) + (o.driver_tip ?? 0);
    individualTotal += payout;

    orderDetails.push({
      id: o.id,
      restLat: rLat, restLng: rLng,
      dropLat: dLat2, dropLng: dLng2,
      payout,
      name: (restInfo?.name as string) ?? "Restaurant",
    });
  }

  // Simple greedy route: driver → restaurant(s) → drop(s)
  // For 2-3 orders, try all permutations (max 6)
  const permutations = getPermutations(orderDetails);
  let bestRoute = orderDetails;
  let bestDistance = Infinity;

  for (const perm of permutations) {
    let dist = 0;
    let prevLat = dLat, prevLng = dLng;

    // Visit all restaurants first
    for (const o of perm) {
      dist += haversineKm(prevLat, prevLng, o.restLat, o.restLng);
      prevLat = o.restLat; prevLng = o.restLng;
    }
    // Then all drops
    for (const o of perm) {
      dist += haversineKm(prevLat, prevLng, o.dropLat, o.dropLng);
      prevLat = o.dropLat; prevLng = o.dropLng;
    }

    if (dist < bestDistance) {
      bestDistance = dist;
      bestRoute = [...perm];
    }
  }

  // Calculate stacked payout ($1.50/mile with 20% stacking bonus)
  const stackedMiles = bestDistance * 0.621371;
  const stackedBasePay = Math.max(basePayMin * orders.length, stackedMiles * ratePerMile * 1.2); // 20% bonus for stacking
  const stackedTips = orders.reduce((s, o) => s + ((o.driver_tip as number) ?? 0), 0);
  const stackedTotal = stackedBasePay + stackedTips;
  const payoutIncrease = individualTotal > 0 ? (stackedTotal - individualTotal) / individualTotal : 0;

  // Calculate delay per customer
  const avgKmPerOrder = bestDistance / orders.length;
  const delayPerCustomer = avgKmPerOrder * 3; // ~3 min/km

  // Evaluate stacking
  const canStack = (
    orders.length <= maxStack &&
    payoutIncrease >= minIncrease &&
    delayPerCustomer <= maxDelay
  );

  const result: Record<string, unknown> = {
    can_stack: canStack,
    order_count: orders.length,
    individual_total: +individualTotal.toFixed(2),
    stacked_total: +stackedTotal.toFixed(2),
    payout_increase_pct: +(payoutIncrease * 100).toFixed(1),
    optimized_distance_km: +bestDistance.toFixed(2),
    estimated_minutes: Math.round(bestDistance * 3),
    delay_per_customer_minutes: Math.round(delayPerCustomer),
    route: bestRoute.map((o, i) => ({
      position: i + 1,
      order_id: o.id,
      restaurant: o.name,
    })),
  };

  if (!canStack) {
    const reasons: string[] = [];
    if (payoutIncrease < minIncrease) reasons.push(`Payout increase ${(payoutIncrease * 100).toFixed(0)}% < required ${(minIncrease * 100).toFixed(0)}%`);
    if (delayPerCustomer > maxDelay) reasons.push(`Delay ${delayPerCustomer.toFixed(0)}min > max ${maxDelay}min`);
    result.reject_reasons = reasons;
  } else {
    // Create stack record
    const { data: stack } = await admin.from("order_stacks").insert({
      driver_id: driverId,
      order_ids: orderIds,
      total_distance_km: bestDistance,
      total_payout: stackedTotal,
      estimated_minutes: bestDistance * 3,
      payout_increase_pct: payoutIncrease * 100,
      max_delay_minutes: delayPerCustomer,
      status: "proposed",
      expires_at: new Date(Date.now() + 120_000).toISOString(), // 2 min to accept
    }).select("id").single();

    result.stack_id = stack?.id;
  }

  return json(result);
}

function getPermutations<T>(arr: T[]): T[][] {
  if (arr.length <= 1) return [arr];
  const result: T[][] = [];
  for (let i = 0; i < arr.length; i++) {
    const rest = [...arr.slice(0, i), ...arr.slice(i + 1)];
    for (const perm of getPermutations(rest)) {
      result.push([arr[i], ...perm]);
    }
  }
  return result;
}

// ════════════════════════════════════════════════════════════════════
// ACTION: update_zone_demand — Recalculate zone demand/surge
// ════════════════════════════════════════════════════════════════════
async function updateZoneDemand() {
  const { data: zones } = await admin.from("zones")
    .select("id, latitude, longitude, radius_km")
    .eq("is_active", true);
  if (!zones) return json({ zones_updated: 0 });

  // Get all pending/ready orders
  const { data: activeOrders } = await admin.from("orders")
    .select("id, restaurant_id, restaurants(latitude, longitude)")
    .in("status", ["pending", "confirmed", "preparing", "ready"])
    .is("driver_id", null);

  // Get all available drivers
  const { data: drivers } = await admin.from("drivers")
    .select("id, current_latitude, current_longitude")
    .eq("is_available", true);

  const results: Array<Record<string, unknown>> = [];

  for (const zone of zones) {
    let orderCount = 0, driverCount = 0;

    // Count orders in zone
    for (const o of activeOrders ?? []) {
      const restInfo = o.restaurants as Record<string, unknown> | null;
      if (!restInfo) continue;
      const dist = haversineKm(zone.latitude, zone.longitude, restInfo.latitude as number, restInfo.longitude as number);
      if (dist <= zone.radius_km) orderCount++;
    }

    // Count drivers in zone
    for (const d of drivers ?? []) {
      if (!d.current_latitude || !d.current_longitude) continue;
      const dist = haversineKm(zone.latitude, zone.longitude, d.current_latitude, d.current_longitude);
      if (dist <= zone.radius_km) driverCount++;
    }

    // Calculate surge: orders/drivers ratio
    const ratio = driverCount > 0 ? orderCount / driverCount : orderCount > 0 ? 3.0 : 0;
    let surgeMult = 1.0;
    let demandLevel = "normal";

    if (ratio >= 3.0) { surgeMult = 2.5; demandLevel = "critical"; }
    else if (ratio >= 2.0) { surgeMult = 2.0; demandLevel = "high"; }
    else if (ratio >= 1.5) { surgeMult = 1.5; demandLevel = "moderate"; }
    else if (ratio < 0.3 && orderCount === 0) { surgeMult = 1.0; demandLevel = "low"; }

    // Cap surge at 3.0x
    surgeMult = Math.min(3.0, surgeMult);

    await admin.from("zones").update({
      active_orders: orderCount,
      available_drivers: driverCount,
      demand_level: demandLevel,
      surge_multiplier: surgeMult,
      updated_at: new Date().toISOString(),
    }).eq("id", zone.id);

    results.push({ zone_id: zone.id, active_orders: orderCount, available_drivers: driverCount, demand_level: demandLevel, surge_multiplier: surgeMult });
  }

  return json({ zones_updated: results.length, zones: results });
}

// ════════════════════════════════════════════════════════════════════
// ACTION: update_performance — Recalculate driver stats & tier
// ════════════════════════════════════════════════════════════════════
async function updatePerformance(body: Record<string, unknown>) {
  const driverId = body.driver_id as string;
  if (!driverId) return json({ error: "driver_id required" }, 400);

  // Fetch driver
  const { data: driver } = await admin.from("drivers")
    .select("id, completed_deliveries, cancelled_deliveries, rating")
    .eq("id", driverId).single();
  if (!driver) return json({ error: "Driver not found" }, 404);

  // Fetch recent orders for this driver (last 30 days)
  const thirtyDaysAgo = new Date(Date.now() - 30 * 86400_000).toISOString();
  const { data: recentOrders } = await admin.from("orders")
    .select("id, status, driver_rating, driver_tip, delivery_fee, ordered_at, completed_at, picked_up_at, distance_km")
    .eq("driver_id", driverId)
    .gte("ordered_at", thirtyDaysAgo);

  const total = recentOrders?.length ?? 0;
  const completed = recentOrders?.filter(o => o.status === "delivered") ?? [];
  const cancelled = recentOrders?.filter(o => o.status === "cancelled") ?? [];

  const completionRate = total > 0 ? (completed.length / total) * 100 : 0;
  const cancellationRate = total > 0 ? (cancelled.length / total) * 100 : 0;

  // On-time: delivered within estimated time (use 45 min as default cutoff)
  const onTimeCount = completed.filter(o => {
    if (!o.completed_at || !o.ordered_at) return true;
    const diff = (new Date(o.completed_at).getTime() - new Date(o.ordered_at).getTime()) / 60_000;
    return diff <= 45;
  }).length;
  const onTimeRate = completed.length > 0 ? (onTimeCount / completed.length) * 100 : 0;

  // Average rating
  const ratings = completed.filter(o => o.driver_rating).map(o => o.driver_rating as number);
  const avgRating = ratings.length > 0 ? ratings.reduce((a, b) => a + b, 0) / ratings.length : driver.rating ?? 0;

  // Average tip percentage
  const tipData = completed.filter(o => o.driver_tip && o.delivery_fee)
    .map(o => ((o.driver_tip as number) / (o.delivery_fee as number)) * 100);
  const avgTipPercent = tipData.length > 0 ? tipData.reduce((a, b) => a + b, 0) / tipData.length : 0;

  // Average delivery time
  const deliveryTimes = completed.filter(o => o.completed_at && o.ordered_at)
    .map(o => (new Date(o.completed_at!).getTime() - new Date(o.ordered_at!).getTime()) / 60_000);
  const avgDeliveryMin = deliveryTimes.length > 0 ? deliveryTimes.reduce((a, b) => a + b, 0) / deliveryTimes.length : 0;

  // Total distance
  const totalDistKm = completed.reduce((s, o) => s + ((o.distance_km as number) ?? 0), 0);
  const totalTips = completed.reduce((s, o) => s + ((o.driver_tip as number) ?? 0), 0);

  // Declined orders
  const { count: declinedCount } = await admin.from("driver_declined_orders")
    .select("*", { count: "exact", head: true })
    .eq("driver_id", driverId)
    .gte("declined_at", thirtyDaysAgo);

  const totalOffered = total + (declinedCount ?? 0);
  const acceptanceRate = totalOffered > 0 ? (total / totalOffered) * 100 : 100;

  // Upsert stats
  await admin.from("driver_stats").upsert({
    driver_id: driverId,
    acceptance_rate: +acceptanceRate.toFixed(1),
    completion_rate: +completionRate.toFixed(1),
    on_time_rate: +onTimeRate.toFixed(1),
    avg_delivery_minutes: +avgDeliveryMin.toFixed(1),
    avg_customer_rating: +avgRating.toFixed(2),
    avg_tip_percent: +avgTipPercent.toFixed(1),
    total_tips: +totalTips.toFixed(2),
    total_distance_km: +totalDistKm.toFixed(2),
    orders_accepted: total,
    orders_declined: declinedCount ?? 0,
    updated_at: new Date().toISOString(),
  }, { onConflict: "driver_id" });

  // Calculate score & tier
  const { data: scoreResult } = await admin.rpc("calculate_driver_score", { p_driver_id: driverId });
  const newScore = scoreResult?.[0]?.score ?? 50;
  const newTier = scoreResult?.[0]?.tier ?? "bronze";

  // Set bonus multiplier based on tier
  const bonusMultipliers: Record<string, number> = { bronze: 1.0, silver: 1.05, gold: 1.10, elite: 1.20 };
  const priorityDispatch = newTier === "gold" || newTier === "elite";

  await admin.from("driver_stats").update({
    bonus_multiplier: bonusMultipliers[newTier] ?? 1.0,
    priority_dispatch: priorityDispatch,
  }).eq("driver_id", driverId);

  return json({
    driver_id: driverId,
    score: +newScore.toFixed(1),
    tier: newTier,
    stats: {
      acceptance_rate: +acceptanceRate.toFixed(1),
      completion_rate: +completionRate.toFixed(1),
      on_time_rate: +onTimeRate.toFixed(1),
      avg_delivery_minutes: +avgDeliveryMin.toFixed(1),
      avg_customer_rating: +avgRating.toFixed(2),
      avg_tip_percent: +avgTipPercent.toFixed(1),
      total_orders_30d: total,
      total_completed_30d: completed.length,
      total_tips: +totalTips.toFixed(2),
      total_distance_km: +totalDistKm.toFixed(2),
    },
    rewards: {
      bonus_multiplier: bonusMultipliers[newTier] ?? 1.0,
      priority_dispatch: priorityDispatch,
    },
  });
}

// ════════════════════════════════════════════════════════════════════
// ACTION: check_earnings_floor — Guaranteed minimum hourly rate
// ════════════════════════════════════════════════════════════════════
async function checkEarningsFloor(body: Record<string, unknown>) {
  const driverId = body.driver_id as string;
  if (!driverId) return json({ error: "driver_id required" }, 400);

  const floor = await cfg("driver_earnings_floor", 20.00);

  const { data: stats } = await admin.from("driver_stats")
    .select("session_earnings, session_active_minutes, active_session_start, floor_topup_total")
    .eq("driver_id", driverId).maybeSingle();

  if (!stats || !stats.active_session_start) {
    return json({
      driver_id: driverId,
      floor_rate: floor,
      session_active: false,
      topup_amount: 0,
      message: "No active session",
    });
  }

  const sessionMinutes = stats.session_active_minutes ?? 0;
  const sessionEarnings = stats.session_earnings ?? 0;
  const sessionHours = sessionMinutes / 60;

  if (sessionHours < 0.5) {
    return json({
      driver_id: driverId,
      floor_rate: floor,
      session_hours: +sessionHours.toFixed(2),
      hourly_rate: 0,
      topup_amount: 0,
      message: "Minimum 30 minutes active time required",
    });
  }

  const hourlyRate = sessionEarnings / sessionHours;
  let topupAmount = 0;

  if (hourlyRate < floor) {
    topupAmount = +(floor * sessionHours - sessionEarnings).toFixed(2);
    topupAmount = Math.max(0, topupAmount);

    // Apply topup
    if (topupAmount > 0) {
      await admin.from("driver_stats").update({
        floor_topup_total: (stats.floor_topup_total ?? 0) + topupAmount,
        session_earnings: sessionEarnings + topupAmount,
        updated_at: new Date().toISOString(),
      }).eq("driver_id", driverId);

      // Credit to driver earnings
      await admin.from("driver_earnings").insert({
        driver_id: driverId,
        floor_topup: topupAmount,
        total_payout: topupAmount,
        earned_at: new Date().toISOString(),
      });

      // Add to driver total
      await admin.rpc("increment_driver_earnings", { p_driver_id: driverId, p_amount: topupAmount }).catch(() => {
        // Fallback: direct update
        admin.from("drivers").update({
          total_earnings: (admin as any).raw(`total_earnings + ${topupAmount}`),
        }).eq("id", driverId);
      });
    }
  }

  return json({
    driver_id: driverId,
    floor_rate: floor,
    session_hours: +sessionHours.toFixed(2),
    session_earnings: +sessionEarnings.toFixed(2),
    hourly_rate: +hourlyRate.toFixed(2),
    topup_amount: topupAmount,
    total_topups: +((stats.floor_topup_total ?? 0) + topupAmount).toFixed(2),
    above_floor: hourlyRate >= floor,
  });
}

// ════════════════════════════════════════════════════════════════════
// ACTION: get_recommendations — Smart suggestions for driver
// ════════════════════════════════════════════════════════════════════
async function getRecommendations(body: Record<string, unknown>) {
  const driverId = body.driver_id as string;
  const driverLat = body.driver_lat as number;
  const driverLng = body.driver_lng as number;

  if (!driverId) return json({ error: "driver_id required" }, 400);

  const tips: string[] = [];

  // 1. Check nearby surge zones
  const { data: surgeZones } = await admin.from("zones")
    .select("name, surge_multiplier, latitude, longitude, demand_level")
    .gt("surge_multiplier", 1.0).eq("is_active", true)
    .order("surge_multiplier", { ascending: false }).limit(3);

  if (surgeZones?.length && driverLat && driverLng) {
    const closest = surgeZones.map(z => ({
      ...z,
      dist: haversineKm(driverLat, driverLng, z.latitude, z.longitude),
    })).sort((a, b) => a.dist - b.dist)[0];

    if (closest.dist > 0.5) {
      tips.push(`🔥 ${closest.name} has ${closest.surge_multiplier}x surge — ${closest.dist.toFixed(1)}km away`);
    } else {
      tips.push(`🔥 You're in a ${closest.surge_multiplier}x surge zone!`);
    }
  }

  // 2. Check driver stats for improvement tips
  const { data: stats } = await admin.from("driver_stats")
    .select("acceptance_rate, completion_rate, tier, hourly_earnings_current")
    .eq("driver_id", driverId).maybeSingle();

  if (stats) {
    if ((stats.acceptance_rate ?? 0) < 70) {
      tips.push("📈 Accept more orders to boost your tier. Higher tier = better orders.");
    }
    if (stats.tier === "bronze") {
      tips.push("⭐ Complete 10 more deliveries on time to reach Silver tier (+5% pay boost).");
    }
    if (stats.tier === "silver") {
      tips.push("⭐ Maintain 4.5+ rating to reach Gold tier (+10% pay boost + priority orders).");
    }
  }

  // 3. Peak hour check
  const hour = new Date().getHours();
  const isPeak = (hour >= 11 && hour < 14) || (hour >= 18 && hour < 21);
  if (isPeak) {
    tips.push("⏰ Peak hours active — orders pay more right now!");
  } else {
    const nextPeak = hour < 11 ? "11:00 AM" : hour < 18 ? "6:00 PM" : "11:00 AM tomorrow";
    tips.push(`⏰ Next peak period starts at ${nextPeak}.`);
  }

  // 4. Nearby high-value orders
  if (driverLat && driverLng) {
    const { data: nearbyScores } = await admin.from("order_scores")
      .select("order_id, score, label, estimated_payout, distance_km")
      .gte("score", 70)
      .order("score", { ascending: false })
      .limit(3);

    if (nearbyScores?.length) {
      tips.push(`💰 ${nearbyScores.length} high-value order(s) available nearby.`);
    }
  }

  return json({
    driver_id: driverId,
    recommendation_count: tips.length,
    tips,
    surge_zones: surgeZones?.map(z => ({
      name: z.name,
      surge: z.surge_multiplier,
      demand: z.demand_level,
      distance_km: driverLat && driverLng ? +haversineKm(driverLat, driverLng, z.latitude, z.longitude).toFixed(1) : null,
    })) ?? [],
    is_peak_hour: isPeak,
  });
}

// ════════════════════════════════════════════════════════════════════
// ACTION: start_session / end_session — Track active driver time
// ════════════════════════════════════════════════════════════════════
async function startSession(body: Record<string, unknown>) {
  const driverId = body.driver_id as string;
  if (!driverId) return json({ error: "driver_id required" }, 400);

  await admin.from("driver_stats").upsert({
    driver_id: driverId,
    active_session_start: new Date().toISOString(),
    session_earnings: 0,
    session_active_minutes: 0,
    updated_at: new Date().toISOString(),
  }, { onConflict: "driver_id" });

  return json({ driver_id: driverId, session_started: true });
}

async function endSession(body: Record<string, unknown>) {
  const driverId = body.driver_id as string;
  if (!driverId) return json({ error: "driver_id required" }, 400);

  const { data: stats } = await admin.from("driver_stats")
    .select("active_session_start, session_earnings, session_active_minutes, total_active_minutes")
    .eq("driver_id", driverId).maybeSingle();

  if (!stats?.active_session_start) return json({ driver_id: driverId, session_ended: false, message: "No active session" });

  const sessionStart = new Date(stats.active_session_start).getTime();
  const sessionMinutes = (Date.now() - sessionStart) / 60_000;
  const totalActiveMinutes = (stats.total_active_minutes ?? 0) + sessionMinutes;

  await admin.from("driver_stats").update({
    active_session_start: null,
    session_active_minutes: sessionMinutes,
    total_active_minutes: totalActiveMinutes,
    updated_at: new Date().toISOString(),
  }).eq("driver_id", driverId);

  // Check and apply earnings floor
  const floorResult = await checkEarningsFloor({ driver_id: driverId });
  const floorData = await floorResult.json();

  return json({
    driver_id: driverId,
    session_ended: true,
    session_minutes: Math.round(sessionMinutes),
    session_earnings: stats.session_earnings ?? 0,
    floor_topup: floorData.topup_amount ?? 0,
  });
}

// ════════════════════════════════════════════════════════════════════
// ACTION: get_driver_earnings — Detailed earnings for dashboard
// ════════════════════════════════════════════════════════════════════
async function getDriverEarnings(body: Record<string, unknown>) {
  const driverId = body.driver_id as string;
  const period   = (body.period as string) ?? "today"; // today | week | month | all

  if (!driverId) return json({ error: "driver_id required" }, 400);

  let since: string;
  const now = new Date();
  switch (period) {
    case "today":
      since = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
      break;
    case "week":
      since = new Date(now.getTime() - 7 * 86400_000).toISOString();
      break;
    case "month":
      since = new Date(now.getTime() - 30 * 86400_000).toISOString();
      break;
    default:
      since = new Date(0).toISOString();
  }

  const { data: earnings } = await admin.from("driver_earnings")
    .select("*")
    .eq("driver_id", driverId)
    .gte("earned_at", since)
    .order("earned_at", { ascending: false });

  const items = earnings ?? [];
  const totalBase = items.reduce((s, e) => s + (e.base_pay ?? 0), 0);
  const totalDistance = items.reduce((s, e) => s + (e.distance_pay ?? 0), 0);
  const totalTime = items.reduce((s, e) => s + (e.time_pay ?? 0), 0);
  const totalWait = items.reduce((s, e) => s + (e.wait_pay ?? 0), 0);
  const totalBoost = items.reduce((s, e) => s + (e.boost_pay ?? 0), 0);
  const totalSurge = items.reduce((s, e) => s + (e.surge_pay ?? 0), 0);
  const totalTips = items.reduce((s, e) => s + (e.tip ?? 0), 0);
  const totalTopup = items.reduce((s, e) => s + (e.floor_topup ?? 0), 0);
  const totalPayout = items.reduce((s, e) => s + (e.total_payout ?? 0), 0);
  const totalKm = items.reduce((s, e) => s + (e.distance_km ?? 0), 0);
  const totalMinutes = items.reduce((s, e) => s + (e.duration_minutes ?? 0), 0);

  return json({
    driver_id: driverId,
    period,
    delivery_count: items.length,
    summary: {
      total_payout: +totalPayout.toFixed(2),
      base_pay: +totalBase.toFixed(2),
      distance_pay: +totalDistance.toFixed(2),
      time_pay: +totalTime.toFixed(2),
      wait_pay: +totalWait.toFixed(2),
      boost_pay: +totalBoost.toFixed(2),
      surge_pay: +totalSurge.toFixed(2),
      tips: +totalTips.toFixed(2),
      floor_topups: +totalTopup.toFixed(2),
      total_distance_km: +totalKm.toFixed(2),
      total_minutes: Math.round(totalMinutes),
      avg_per_delivery: items.length > 0 ? +(totalPayout / items.length).toFixed(2) : 0,
      avg_per_hour: totalMinutes > 0 ? +((totalPayout / totalMinutes) * 60).toFixed(2) : 0,
    },
    deliveries: items.slice(0, 50).map(e => ({
      id: e.id,
      order_id: e.order_id,
      total_payout: e.total_payout,
      base_pay: e.base_pay,
      tip: e.tip,
      distance_km: e.distance_km,
      duration_minutes: e.duration_minutes,
      earnings_per_hour: e.earnings_per_hour,
      is_stacked: e.is_stacked,
      earned_at: e.earned_at,
    })),
  });
}

// ════════════════════════════════════════════════════════════════════
// MAIN ROUTER
// ════════════════════════════════════════════════════════════════════
Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const action = body.action as string;
  if (!action) return json({ error: "action is required" }, 400);

  switch (action) {
    case "score_order":         return scoreOrder(body);
    case "calculate_payout":    return calculatePayout(body);
    case "check_stacking":      return checkStacking(body);
    case "update_zone_demand":  return updateZoneDemand();
    case "update_performance":  return updatePerformance(body);
    case "check_earnings_floor":return checkEarningsFloor(body);
    case "get_recommendations": return getRecommendations(body);
    case "start_session":       return startSession(body);
    case "end_session":         return endSession(body);
    case "get_driver_earnings": return getDriverEarnings(body);
    default: return json({ error: `Unknown action: ${action}` }, 400);
  }
});

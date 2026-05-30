// assign-driver-multi-pickup
// Finds nearest available driver and creates delivery_task + delivery_stops
// for the full multi-restaurant route: pickup A → pickup B → … → customer dropoff.
// Deploy: supabase functions deploy assign-driver-multi-pickup

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

function round2(n: number) { return Math.round(n * 100) / 100; }

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { order_group_id: string; driver_id?: string };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { order_group_id, driver_id: preferredDriverId } = body;
  if (!order_group_id) return json({ error: "order_group_id required" }, 400);

  // ── 1. Load order group ────────────────────────────────────────────────
  const { data: group } = await admin
    .from("order_groups")
    .select("*")
    .eq("id", order_group_id)
    .single();

  if (!group) return json({ error: "Order group not found" }, 404);
  if (group.payment_status !== "paid") {
    return json({ error: "Cannot assign driver before payment is confirmed" }, 400);
  }

  // ── 2. Load sub-orders in sequence order ──────────────────────────────
  const { data: subOrders } = await admin
    .from("orders")
    .select("id, restaurant_id, sequence_in_group")
    .eq("order_group_id", order_group_id)
    .order("sequence_in_group");

  if (!subOrders?.length) return json({ error: "No sub-orders found" }, 404);

  // ── 3. Load restaurant locations ──────────────────────────────────────
  const restaurantIds = subOrders.map((o) => o.restaurant_id);
  const { data: restaurants } = await admin
    .from("restaurants")
    .select("id, name, latitude, longitude, address")
    .in("id", restaurantIds);

  if (!restaurants?.length) return json({ error: "Restaurant data not found" }, 404);

  const restaurantMap = new Map(restaurants.map((r) => [r.id, r]));

  // ── 4. Calculate total route distance ─────────────────────────────────
  // Route: driver current pos → restaurant 1 → restaurant 2 → customer
  let totalDistanceKm = 0;
  const pickupPoints = subOrders.map((o) => restaurantMap.get(o.restaurant_id)).filter(Boolean);

  for (let i = 0; i < pickupPoints.length - 1; i++) {
    const a = pickupPoints[i]!;
    const b = pickupPoints[i + 1]!;
    if (a.latitude && b.latitude) {
      totalDistanceKm += haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
    }
  }
  // Last pickup → customer dropoff
  const lastPickup = pickupPoints[pickupPoints.length - 1];
  if (lastPickup?.latitude && group.delivery_latitude) {
    totalDistanceKm += haversineKm(
      lastPickup.latitude, lastPickup.longitude,
      group.delivery_latitude, group.delivery_longitude,
    );
  }
  totalDistanceKm = round2(totalDistanceKm);

  // ── 5. Calculate driver earnings ──────────────────────────────────────
  const basePay          = await getConfig("driverMinBasePay", 3.0);
  const ratePerKm        = await getConfig("driverRatePerKm", 0.93);
  const extraStopPay     = await getConfig("driver_extra_stop_pay", 1.50);
  const extraStops       = subOrders.length - 1;
  const distancePay      = round2(totalDistanceKm * ratePerKm);
  const extraPay         = round2(extraStops * extraStopPay);
  const driverEarning    = round2(Math.max(basePay, basePay + distancePay) + extraPay);
  const estimatedMinutes = Math.round(totalDistanceKm * 3 + extraStops * 5 + 10);

  // ── 6. Find nearest available driver (or use preferred) ───────────────
  let assignedDriverId: string | null = null;

  if (preferredDriverId) {
    const { data: pref } = await admin
      .from("drivers")
      .select("id, is_available")
      .eq("id", preferredDriverId)
      .single();
    if (pref?.is_available) assignedDriverId = pref.id;
  }

  if (!assignedDriverId) {
    const firstRestaurant = pickupPoints[0];
    const { data: availableDrivers } = await admin
      .from("drivers")
      .select("id, current_latitude, current_longitude")
      .eq("is_available", true)
      .eq("is_verified", true)
      .not("current_latitude", "is", null)
      .not("current_longitude", "is", null);

    if (availableDrivers?.length && firstRestaurant?.latitude) {
      // Sort by distance to first pickup
      const sorted = availableDrivers
        .map((d) => ({
          ...d,
          dist: haversineKm(
            d.current_latitude, d.current_longitude,
            firstRestaurant.latitude!, firstRestaurant.longitude!,
          ),
        }))
        .sort((a, b) => a.dist - b.dist);
      assignedDriverId = sorted[0].id;
    }
  }

  // ── 7. Create delivery_task ────────────────────────────────────────────
  const taskId = crypto.randomUUID();
  const { error: taskErr } = await admin.from("delivery_tasks").insert({
    id:                         taskId,
    order_group_id,
    driver_id:                  assignedDriverId,
    total_pickups:              subOrders.length,
    total_distance_km:          totalDistanceKm,
    estimated_duration_minutes: estimatedMinutes,
    base_pay:                   basePay,
    distance_pay:               distancePay,
    extra_stop_pay:             extraPay,
    driver_earning:             driverEarning,
    delivery_status:            assignedDriverId ? "assigned" : "pending",
  });
  if (taskErr) return json({ error: `Failed to create task: ${taskErr.message}` }, 500);

  // ── 8. Create delivery_stops (pickup per restaurant + one dropoff) ─────
  const stops = [];
  for (let i = 0; i < subOrders.length; i++) {
    const subOrder   = subOrders[i];
    const restaurant = restaurantMap.get(subOrder.restaurant_id);
    stops.push({
      delivery_task_id: taskId,
      order_id:         subOrder.id,
      stop_type:        "pickup",
      restaurant_id:    subOrder.restaurant_id,
      sequence_number:  i + 1,
      address:          restaurant?.address ?? null,
      latitude:         restaurant?.latitude ?? null,
      longitude:        restaurant?.longitude ?? null,
      status:           "pending",
    });
  }
  // Customer dropoff as final stop
  stops.push({
    delivery_task_id: taskId,
    order_id:         null,
    stop_type:        "dropoff",
    restaurant_id:    null,
    sequence_number:  subOrders.length + 1,
    address:          group.delivery_address,
    latitude:         group.delivery_latitude,
    longitude:        group.delivery_longitude,
    status:           "pending",
  });

  const { error: stopsErr } = await admin.from("delivery_stops").insert(stops);
  if (stopsErr) return json({ error: `Failed to create stops: ${stopsErr.message}` }, 500);

  // ── 9. Mark driver unavailable and link driver to sub-orders ──────────
  if (assignedDriverId) {
    await admin.from("drivers").update({ is_available: false }).eq("id", assignedDriverId);
    await admin.from("orders")
      .update({ driver_id: assignedDriverId, status: "confirmed" })
      .eq("order_group_id", order_group_id);

    // Notify driver
    const { data: driver } = await admin
      .from("drivers")
      .select("user_id")
      .eq("id", assignedDriverId)
      .single();
    if (driver?.user_id) {
      const notifTitle = "🛵 New Multi-Stop Delivery!";
      const notifBody  = `Pick up from ${subOrders.length} restaurant${subOrders.length > 1 ? "s" : ""} and deliver to one customer.`;

      // Insert into notifications DB table
      await admin.from("notifications").insert({
        user_id: driver.user_id,
        type:    "new_ride",
        title:   notifTitle,
        body:    notifBody,
        data:    { order_group_id, delivery_task_id: taskId },
      }).catch(() => null);

      // Also push via FCM to the driver's personal topic (driver_{drivers.id})
      fetch(`${supabaseUrl}/functions/v1/send-fcm-notification`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${supabaseKey}`,
          "apikey": supabaseKey,
        },
        body: JSON.stringify({
          topic: `driver_${assignedDriverId}`,
          title: notifTitle,
          body:  notifBody,
          data: {
            type:             "new_multi_delivery",
            order_group_id:   order_group_id,
            delivery_task_id: taskId,
          },
        }),
      }).catch(() => null);
    }

    // Notify customer
    await admin.from("notifications").insert({
      user_id: group.customer_id,
      type:    "order_placed",
      title:   "🚗 Driver Assigned!",
      body:    "A driver has been assigned to your multi-restaurant order.",
      data:    { order_group_id, delivery_task_id: taskId },
    }).catch(() => null);
  }

  return json({
    success:          true,
    delivery_task_id: taskId,
    driver_id:        assignedDriverId,
    driver_earning:   driverEarning,
    total_distance_km: totalDistanceKm,
    estimated_minutes: estimatedMinutes,
    stop_count:       stops.length,
  });
});

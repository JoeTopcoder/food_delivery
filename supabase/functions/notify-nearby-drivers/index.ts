// notify-nearby-drivers — push a "new order" ONLY to drivers who are currently
// active (is_available) and within ~3 km of the store. Called by the orders
// trigger when an order becomes 'ready'.
// Deploy: supabase functions deploy notify-nearby-drivers
// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h: (r: Request) => Response | Promise<Response>): void };
// @ts-ignore Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: Record<string, unknown>, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) * Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  let body: Record<string, unknown>;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const orderId = String(body.order_id ?? "");
  if (!orderId) return json({ error: "order_id required" }, 400);

  // Radius (km) — configurable, defaults to 3.
  let radiusKm = 3;
  try {
    const { data: cfg } = await admin.from("app_config").select("value").eq("key", "driver_notify_radius_km").maybeSingle();
    if (cfg?.value) radiusKm = Number(cfg.value) || 3;
  } catch { /* default */ }

  // The order + store, incl. details the driver's pop-up card shows.
  const { data: order } = await admin
    .from("orders")
    .select("id, restaurant_id, total_amount, delivery_fee, driver_tip, delivery_address")
    .eq("id", orderId)
    .maybeSingle();
  if (!order?.restaurant_id) return json({ error: "order/store not found" }, 404);
  const { data: store } = await admin
    .from("restaurants")
    .select("latitude, longitude, name, estimated_delivery_time")
    .eq("id", order.restaurant_id)
    .maybeSingle();
  const sLat = Number(store?.latitude), sLng = Number(store?.longitude);
  if (!Number.isFinite(sLat) || !Number.isFinite(sLng)) return json({ error: "store has no coordinates" }, 400);

  // Active drivers, and their most recent broadcast location (driver_locations).
  // Only locations fresh within the last 12 minutes count — a stale fix means
  // the driver isn't really out there right now.
  const freshCutoff = new Date(Date.now() - 12 * 60_000).toISOString();
  const { data: activeDrivers } = await admin
    .from("drivers")
    .select("id, user_id")
    .eq("is_available", true);
  const idToUser = new Map((activeDrivers ?? []).map((d) => [d.id, d.user_id]));
  if (idToUser.size === 0) {
    return json({ ok: true, radius_km: radiusKm, active_drivers: 0, nearby: 0, sent: 0 });
  }

  const { data: locs } = await admin
    .from("driver_locations")
    .select("driver_id, latitude, longitude, updated_at")
    .in("driver_id", [...idToUser.keys()])
    .gte("updated_at", freshCutoff);

  const nearby = (locs ?? [])
    .map((l) => ({
      userId: idToUser.get(l.driver_id),
      km: haversineKm(Number(l.latitude), Number(l.longitude), sLat, sLng),
    }))
    .filter((d) => d.userId && Number.isFinite(d.km) && d.km <= radiusKm);

  // Push to each nearby driver's personal topic (they subscribe to driver_<id>).
  let sent = 0;
  await Promise.all(nearby.map(async (d) => {
    try {
      await admin.functions.invoke("send-fcm-notification", {
        body: {
          topic: `driver_${d.userId}`,
          title: "New Order Nearby",
          body: `An order at ${store?.name ?? "a store"} is ready — open Orders to accept it.`,
          data: {
            type: "new_order",
            order_id: orderId,
            store_name: String(store?.name ?? "Store"),
            address: String(order.delivery_address ?? ""),
            total: String(order.total_amount ?? ""),
            delivery_fee: String(order.delivery_fee ?? "0"),
            tip: String(order.driver_tip ?? "0"),
            eta: String(store?.estimated_delivery_time ?? "40"),
            distance_km: d.km.toFixed(1),
          },
        },
      });
      sent++;
    } catch (_e) { /* one failure must not stop the rest */ }
  }));

  return json({ ok: true, radius_km: radiusKm, active_drivers: idToUser.size, nearby: nearby.length, sent });
});

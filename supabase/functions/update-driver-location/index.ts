// update-driver-location — Lightweight edge function for high-frequency location updates
// Handles: driver GPS position update + optional nearby order matching
// This is designed to be called every 10-30 seconds from the driver app.
// Deploy: supabase functions deploy update-driver-location

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
  const dLat = ((lat2 - lat1) * Math.PI) / 180;
  const dLon = ((lon2 - lon1) * Math.PI) / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((lat1 * Math.PI) / 180) *
      Math.cos((lat2 * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
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

  const driverId = body.driver_id as string;
  const latitude = body.latitude as number;
  const longitude = body.longitude as number;
  const includeNearby = body.include_nearby === true; // optional: return nearby unassigned orders

  if (!driverId || latitude == null || longitude == null) {
    return json({ error: "driver_id, latitude, longitude required" }, 400);
  }

  // Validate coordinates
  if (latitude < -90 || latitude > 90 || longitude < -180 || longitude > 180) {
    return json({ error: "Invalid coordinates" }, 400);
  }

  try {
    const now = new Date().toISOString();

    // ── 1. Update driver location ───────────────────────────────────────
    const { error: updateErr } = await admin
      .from("drivers")
      .update({
        current_lat: latitude,
        current_lng: longitude,
        updated_at: now,
      })
      .eq("id", driverId);

    if (updateErr) {
      return json({ error: "Failed to update location", details: updateErr.message }, 500);
    }

    const result: Record<string, unknown> = {
      success: true,
      updated_at: now,
    };

    // ── 2. Optionally return nearby unassigned orders ───────────────────
    if (includeNearby) {
      const { data: orders } = await admin
        .from("orders")
        .select("id, restaurant_id, delivery_latitude, delivery_longitude, total_amount, delivery_fee, ordered_at, status")
        .is("driver_id", null)
        .in("status", ["pending", "confirmed", "preparing", "ready"])
        .eq("is_pickup", false)
        .order("ordered_at", { ascending: false })
        .limit(20);

      if (orders && orders.length > 0) {
        // Get restaurant locations for each order
        const restaurantIds = [...new Set(orders.map((o: Record<string, unknown>) => o.restaurant_id))];
        const { data: restaurants } = await admin
          .from("restaurants")
          .select("id, name, latitude, longitude")
          .in("id", restaurantIds);

        const restMap = new Map(
          (restaurants ?? []).map((r: Record<string, unknown>) => [r.id, r])
        );

        // Calculate distance from driver to each restaurant
        const nearbyOrders = orders
          .map((o: Record<string, unknown>) => {
            const rest = restMap.get(o.restaurant_id) as Record<string, unknown> | undefined;
            const restLat = Number(rest?.latitude) || 0;
            const restLng = Number(rest?.longitude) || 0;
            const distanceKm = haversineKm(latitude, longitude, restLat, restLng);
            return {
              order_id: o.id,
              restaurant_name: rest?.name ?? "Unknown",
              distance_km: Math.round(distanceKm * 100) / 100,
              delivery_fee: o.delivery_fee,
              total_amount: o.total_amount,
              status: o.status,
            };
          })
          .filter((o: Record<string, unknown>) => (o.distance_km as number) <= 15) // Only within 15km
          .sort((a: Record<string, unknown>, b: Record<string, unknown>) =>
            (a.distance_km as number) - (b.distance_km as number)
          )
          .slice(0, 5); // Top 5 closest

        result.nearby_orders = nearbyOrders;
        result.nearby_count = nearbyOrders.length;
      } else {
        result.nearby_orders = [];
        result.nearby_count = 0;
      }
    }

    return json(result);
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

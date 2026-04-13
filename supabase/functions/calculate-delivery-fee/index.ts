// calculate-delivery-fee — Distance-based delivery fee calculation
// Uses haversine formula + DB-driven config for base fee, per-km rate, surge, max distance

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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const restaurantId = body.restaurant_id as string;
  const deliveryLat = body.delivery_latitude as number;
  const deliveryLng = body.delivery_longitude as number;

  if (!restaurantId || deliveryLat === undefined || deliveryLng === undefined) {
    return json({ error: "Missing restaurant_id, delivery_latitude, delivery_longitude" }, 400);
  }

  try {
    // Fetch restaurant location and custom delivery_fee override
    const { data: restaurant, error } = await admin
      .from("restaurants")
      .select("id, latitude, longitude, delivery_fee")
      .eq("id", restaurantId)
      .single();

    if (error || !restaurant) {
      return json({ error: "Restaurant not found" }, 404);
    }

    // Fetch config values
    const [baseFee, perKmFee, baseKm, maxKm, globalSurgeMultiplier, defaultFee] = await Promise.all([
      getConfig("delivery_base_fee", 50.0),
      getConfig("delivery_per_km_fee", 30.0),
      getConfig("delivery_base_km", 3.0),
      getConfig("delivery_max_km", 25.0),
      getConfig("delivery_surge_multiplier", 1.0),
      getConfig("default_delivery_fee", 50.0),
    ]);

    // Check surge_zones table for zone-specific multiplier at delivery location
    let surgeMultiplier = globalSurgeMultiplier;
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
          if (dist > z.radius_km && z.multiplier > surgeMultiplier) {
            surgeMultiplier = z.multiplier;
          }
        }
      }
    } catch { /* fall back to global config */ }

    // If restaurant has no coordinates, return flat fee (still apply surge)
    if (!restaurant.latitude || !restaurant.longitude) {
      const flatFee = Math.round((restaurant.delivery_fee ?? defaultFee) * surgeMultiplier * 100) / 100;
      return json({
        delivery_fee: flatFee,
        distance_km: null,
        calculation: "flat_fee",
        surge_multiplier: surgeMultiplier,
      });
    }

    const distanceKm = haversineKm(
      restaurant.latitude, restaurant.longitude,
      deliveryLat, deliveryLng
    );

    if (distanceKm > maxKm) {
      return json({
        error: `Delivery distance (${distanceKm.toFixed(1)} km) exceeds maximum of ${maxKm} km`,
        distance_km: Math.round(distanceKm * 10) / 10,
        max_km: maxKm,
      }, 400);
    }

    const extraKm = Math.max(0, distanceKm - baseKm);
    const calculatedFee = Math.round((baseFee + extraKm * perKmFee) * surgeMultiplier * 100) / 100;
    // Use higher of restaurant override or distance-based fee
    const restaurantOverride = restaurant.delivery_fee ?? 0;
    const finalFee = Math.max(restaurantOverride, calculatedFee);

    return json({
      delivery_fee: finalFee,
      distance_km: Math.round(distanceKm * 10) / 10,
      calculation: "distance_based",
      base_fee: baseFee,
      per_km_fee: perKmFee,
      base_km: baseKm,
      extra_km: Math.round(extraKm * 10) / 10,
      surge_multiplier: surgeMultiplier,
      restaurant_override: restaurantOverride,
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

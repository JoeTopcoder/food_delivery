// calculate-delivery-fee — Distance-based delivery fee calculation
// Uses haversine formula + DB-driven config for base fee, per-km rate, surge, max distance
// Returns driver_pay (driver_pay_percent of fee) and honours min_delivery_fee

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

function round2(n: number): number {
  return Math.round(n * 100) / 100;
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

// ── Cache helpers ────────────────────────────────────────────────────────────
// Coordinate precision for cache: ~11 m (4 decimal places)
function roundCoord(v: number): number { return Math.round(v * 10000) / 10000; }

async function getCached(restaurantId: string, lat: number, lng: number) {
  const rLat = roundCoord(lat);
  const rLng = roundCoord(lng);
  const { data } = await admin
    .from("delivery_fee_cache")
    .select("*")
    .eq("restaurant_id", restaurantId)
    .eq("delivery_lat", rLat)
    .eq("delivery_lng", rLng)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data;
}

async function setCache(row: Record<string, unknown>) {
  try {
    await admin.from("delivery_fee_cache").insert(row);
  } catch { /* non-fatal */ }
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
  const skipCache = body.skip_cache === true;

  if (!restaurantId || deliveryLat === undefined || deliveryLng === undefined) {
    return json({ error: "Missing restaurant_id, delivery_latitude, delivery_longitude" }, 400);
  }

  try {
    // ── Check cache first ────────────────────────────────────────────────────
    if (!skipCache) {
      const cached = await getCached(restaurantId, deliveryLat, deliveryLng);
      if (cached) {
        return json({
          delivery_fee: parseFloat(cached.delivery_fee),
          driver_pay: parseFloat(cached.driver_pay),
          distance_km: parseFloat(cached.distance_km),
          calculation: cached.calculation,
          surge_multiplier: parseFloat(cached.surge_multiplier),
          cached: true,
        });
      }
    }

    // Fetch restaurant location and custom delivery_fee override
    const { data: restaurant, error } = await admin
      .from("restaurants")
      .select("id, latitude, longitude, delivery_fee")
      .eq("id", restaurantId)
      .single();

    if (error || !restaurant) {
      return json({ error: "Restaurant not found" }, 404);
    }

    // Fetch config values (including new driver_pay_percent + min_delivery_fee)
    const [baseFee, perMileFee, perMileFeePeak, baseMiles, maxKm, globalSurgeMultiplier, defaultFee, driverPayPercent, minFee, peakStart, peakEnd, peakStart2, peakEnd2] = await Promise.all([
      getConfig("delivery_base_fee", 3.0),
      getConfig("delivery_per_mile_fee", 2.0),
      getConfig("delivery_per_mile_fee_peak", 2.5),
      getConfig("delivery_base_miles", 1.0),
      getConfig("delivery_max_km", 30.0),
      getConfig("delivery_surge_multiplier", 1.0),
      getConfig("default_delivery_fee", 5.0),
      getConfig("driver_pay_percent", 0.80),
      getConfig("min_delivery_fee", 3.0),
      getConfig("peak_hours_start", 11),
      getConfig("peak_hours_end", 14),
      getConfig("peak_hours_start_2", 18),
      getConfig("peak_hours_end_2", 21),
    ]);

    // Check if current hour is within a peak window
    const currentHour = new Date().getUTCHours(); // Edge functions run in UTC — adjust if needed
    const isPeak = (
      (currentHour >= peakStart && currentHour < peakEnd) ||
      (currentHour >= peakStart2 && currentHour < peakEnd2)
    );
    // $2.00/mile standard, $2.50/mile peak
    const activePerMileFee = isPeak ? perMileFeePeak : perMileFee;

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
          if (dist <= z.radius_km && z.multiplier > surgeMultiplier) {
            surgeMultiplier = z.multiplier;
          }
        }
      }
    } catch { /* fall back to global config */ }

    // If restaurant has no coordinates, return flat fee (still apply surge)
    if (!restaurant.latitude || !restaurant.longitude) {
      const rawFee = (restaurant.delivery_fee ?? defaultFee) * surgeMultiplier;
      const flatFee = round2(Math.max(rawFee, minFee));
      const driverPay = round2(flatFee * driverPayPercent);
      const platformFee = round2(flatFee - driverPay);

      await setCache({
        restaurant_id: restaurantId,
        delivery_lat: roundCoord(deliveryLat),
        delivery_lng: roundCoord(deliveryLng),
        distance_km: 0,
        delivery_fee: flatFee,
        driver_pay: driverPay,
        surge_multiplier: surgeMultiplier,
        calculation: "flat_fee",
      });

      return json({
        delivery_fee: flatFee,
        driver_pay: driverPay,
        platform_fee: platformFee,
        driver_pay_percent: driverPayPercent,
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

    // Distance-based: $2.00/mile (standard) or $2.50/mile (peak)
    const distanceMiles = distanceKm * 0.621371;
    const extraMiles = Math.max(0, distanceMiles - baseMiles);
    const rawCalculated = (baseFee + extraMiles * activePerMileFee) * surgeMultiplier;
    // Use higher of restaurant override or distance-based fee
    const restaurantOverride = restaurant.delivery_fee ?? 0;
    // Enforce minimum fee
    const finalFee = round2(Math.max(rawCalculated, restaurantOverride, minFee));
    const driverPay = round2(finalFee * driverPayPercent);
    const platformFee = round2(finalFee - driverPay);
    const distanceRounded = Math.round(distanceKm * 10) / 10;
    const milesRounded = round2(distanceMiles);

    // ── Write to cache ───────────────────────────────────────────────────────
    await setCache({
      restaurant_id: restaurantId,
      delivery_lat: roundCoord(deliveryLat),
      delivery_lng: roundCoord(deliveryLng),
      distance_km: distanceRounded,
      delivery_fee: finalFee,
      driver_pay: driverPay,
      surge_multiplier: surgeMultiplier,
      calculation: "distance_based",
    });

    return json({
      delivery_fee: finalFee,
      driver_pay: driverPay,
      platform_fee: platformFee,
      driver_pay_percent: driverPayPercent,
      distance_km: distanceRounded,
      distance_miles: milesRounded,
      calculation: "distance_based",
      base_fee: baseFee,
      per_mile_fee: activePerMileFee,
      base_miles: baseMiles,
      extra_miles: round2(extraMiles),
      surge_multiplier: surgeMultiplier,
      min_fee: minFee,
      restaurant_override: restaurantOverride,
      is_peak: isPeak,
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

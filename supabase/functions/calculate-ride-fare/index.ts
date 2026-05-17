import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

interface RouteInfo {
  distance_km: number;
  duration_minutes: number;
}

interface FareBreakdown {
  base_fare: number;
  distance_cost: number;
  time_cost: number;
  subtotal: number;
  surge_multiplier: number;
  surged_total: number;
  platform_fee: number;
  estimated_fare: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { pickup_lat, pickup_lng, destination_lat, destination_lng } =
      await req.json();

    if (
      !pickup_lat ||
      !pickup_lng ||
      !destination_lat ||
      !destination_lng
    ) {
      return new Response(
        JSON.stringify({
          error: "Missing coordinates",
        }),
        { status: 400, headers: corsHeaders }
      );
    }

    // TODO: Integrate with Google Maps or similar to get actual distance/duration
    // For now, using Haversine formula for rough distance estimation
    const routeInfo = calculateRouteEstimate(
      pickup_lat,
      pickup_lng,
      destination_lat,
      destination_lng
    );

    // Get pricing settings from database
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { data: settings, error: settingsError } = await supabase
      .from("ride_pricing_settings")
      .select("*")
      .eq("active", true)
      .limit(1)
      .single();

    if (settingsError || !settings) {
      console.error("Error fetching pricing settings:", settingsError);
      console.error("Settings data:", settings);
      return new Response(
        JSON.stringify({
          error: "Failed to fetch pricing settings from database",
          details: settingsError?.message || "No active pricing settings found",
          settingsError: settingsError,
        }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Calculate fare with surge pricing
    const fareBreakdown = calculateFare(
      routeInfo.distance_km,
      routeInfo.duration_minutes,
      settings
    );

    const KM_PER_MILE = 1.60934;
    const distance_miles = parseFloat((routeInfo.distance_km / KM_PER_MILE).toFixed(2));

    return new Response(
      JSON.stringify({
        // Flat keys the Flutter app reads directly
        distance_km: routeInfo.distance_km,
        distance_miles,
        estimated_duration_minutes: routeInfo.duration_minutes,
        estimated_fare: fareBreakdown.estimated_fare,
        platform_fee: fareBreakdown.platform_fee,
        currency: "JMD",
        // Full breakdown for debugging
        fare_breakdown: fareBreakdown,
      }),
      {
        headers: corsHeaders,
        status: 200,
      }
    );
  } catch (error) {
    console.error("Error calculating fare:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error.message,
      }),
      { status: 500, headers: corsHeaders }
    );
  }
});

/**
 * Calculate route estimate using Haversine formula
 * Returns estimated distance in km and duration in minutes
 */
function calculateRouteEstimate(
  pickup_lat: number,
  pickup_lng: number,
  dest_lat: number,
  dest_lng: number
): RouteInfo {
  const haversineDistance = (lat1: number, lon1: number, lat2: number, lon2: number) => {
    const R = 6371; // Earth's radius in km
    const dLat = ((lat2 - lat1) * Math.PI) / 180;
    const dLon = ((lon2 - lon1) * Math.PI) / 180;
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos((lat1 * Math.PI) / 180) *
        Math.cos((lat2 * Math.PI) / 180) *
        Math.sin(dLon / 2) *
        Math.sin(dLon / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  };

  const distance_km = haversineDistance(pickup_lat, pickup_lng, dest_lat, dest_lng);
  // Estimate: average speed 30 km/h in city = 2 minutes per km
  // Add 2 minutes base for pickups and starting
  const duration_minutes = Math.ceil(distance_km * 2) + 2;

  return { distance_km: parseFloat(distance_km.toFixed(2)), duration_minutes };
}

/**
 * Calculate fare based on distance, duration, and settings.
 * Rate: J$250 per mile. Minimum fare: J$500. Platform fee: 20%.
 */
function calculateFare(
  distance_km: number,
  duration_minutes: number,
  settings: any
): FareBreakdown {
  const KM_PER_MILE = 1.60934;
  const distance_miles = distance_km / KM_PER_MILE;

  // J$250/mile is the base rate. DB settings can override via per_km_rate
  // but we convert to per-mile so the unit is consistent.
  const per_mile_rate = settings.per_mile_rate || 250.0;
  const minimum_fare = settings.minimum_fare || 500.0;
  const platform_commission_percent = settings.platform_commission_percent || 20;
  const surge_multiplier = settings.surge_multiplier || 1.0;

  const base_fare = 0;
  const distance_cost = distance_miles * per_mile_rate;
  const time_cost = 0;
  let subtotal = distance_cost;
  subtotal = Math.max(subtotal, minimum_fare);

  const surged_total = subtotal * surge_multiplier;
  const platform_fee = (surged_total * platform_commission_percent) / 100;
  const estimated_fare = surged_total + platform_fee;

  return {
    base_fare: parseFloat(base_fare.toFixed(2)),
    distance_cost: parseFloat(distance_cost.toFixed(2)),
    time_cost: parseFloat(time_cost.toFixed(2)),
    subtotal: parseFloat(subtotal.toFixed(2)),
    surge_multiplier: parseFloat(surge_multiplier.toFixed(2)),
    surged_total: parseFloat(surged_total.toFixed(2)),
    platform_fee: parseFloat(platform_fee.toFixed(2)),
    estimated_fare: parseFloat(estimated_fare.toFixed(2)),
  };
}

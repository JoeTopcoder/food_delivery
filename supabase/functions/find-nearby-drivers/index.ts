import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

interface NearbyDriver {
  driver_id: string;
  user_id: string;
  vehicle_type: string;
  vehicle_number: string;
  current_lat: number;
  current_lng: number;
  distance_km: number;
  rating: number;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const { pickup_lat, pickup_lng, search_radius_km = 15, limit = 5 } =
      await req.json();

    if (!pickup_lat || !pickup_lng) {
      return new Response(
        JSON.stringify({ error: "Missing pickup coordinates" }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Initialize Supabase
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get drivers with current location
    // Filter for:
    // - Approved ride drivers
    // - Currently online
    // - Not currently on another ride
    const { data: drivers, error: driversError } = await supabase
      .from("drivers")
      .select(
        `
        id,
        user_id,
        vehicle_type,
        vehicle_number,
        current_lat,
        current_lng,
        rating
      `
      )
      .eq("is_ride_driver_approved", true)
      .eq("is_available_for_rides", true)
      .eq("is_online", true)
      .not("current_lat", "is", null)
      .not("current_lng", "is", null);

    if (driversError) {
      console.error("Error fetching drivers:", driversError);
      return new Response(
        JSON.stringify({ error: "Failed to fetch drivers" }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Filter drivers by distance and sort by distance
    const nearbyDrivers: NearbyDriver[] = drivers
      ?.map((driver: any) => ({
        driver_id: driver.id,
        user_id: driver.user_id,
        vehicle_type: driver.vehicle_type,
        vehicle_number: driver.vehicle_number,
        current_lat: driver.current_lat,
        current_lng: driver.current_lng,
        distance_km: calculateDistance(
          pickup_lat,
          pickup_lng,
          driver.current_lat,
          driver.current_lng
        ),
        rating: driver.rating || 0,
      }))
      .filter((driver: NearbyDriver) => driver.distance_km <= search_radius_km)
      .sort((a: NearbyDriver, b: NearbyDriver) => {
        // Sort by distance first, then by rating (descending)
        if (a.distance_km !== b.distance_km) {
          return a.distance_km - b.distance_km;
        }
        return b.rating - a.rating;
      })
      .slice(0, limit) || [];

    return new Response(
      JSON.stringify({
        drivers: nearbyDrivers,
        count: nearbyDrivers.length,
        search_radius_km,
      }),
      {
        headers: corsHeaders,
        status: 200,
      }
    );
  } catch (error) {
    console.error("Error finding nearby drivers:", error);
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
 * Calculate distance between two coordinates using Haversine formula
 */
function calculateDistance(
  lat1: number,
  lon1: number,
  lat2: number,
  lon2: number
): number {
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
  const distance = R * c;
  return parseFloat(distance.toFixed(2));
}

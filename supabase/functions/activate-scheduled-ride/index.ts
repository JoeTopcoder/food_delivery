import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Missing authorization" }), { status: 401, headers: corsHeaders });
    }

    const token = authHeader.replace("Bearer ", "");
    const { ride_id } = await req.json();

    if (!ride_id) {
      return new Response(JSON.stringify({ error: "ride_id required" }), { status: 400, headers: corsHeaders });
    }

    const jwtParts = token.split(".");
    const decodedPayload = JSON.parse(atob(jwtParts[1])) as { sub: string };
    const customer_id = decodedPayload.sub;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { data: ride, error: rideError } = await supabase
      .from("ride_requests")
      .select("*")
      .eq("id", ride_id)
      .eq("customer_id", customer_id)
      .single();

    if (rideError || !ride) {
      return new Response(JSON.stringify({ error: "Ride not found" }), { status: 404, headers: corsHeaders });
    }

    if (ride.ride_status !== "scheduled") {
      return new Response(JSON.stringify({ error: "Ride is not in scheduled status" }), { status: 400, headers: corsHeaders });
    }

    const { error: updateError } = await supabase
      .from("ride_requests")
      .update({ ride_status: "searching_driver", updated_at: new Date().toISOString() })
      .eq("id", ride_id);

    if (updateError) {
      return new Response(JSON.stringify({ error: "Failed to activate ride" }), { status: 500, headers: corsHeaders });
    }

    const { data: candidateDrivers } = await supabase
      .from("drivers")
      .select("id, current_lat, current_lng")
      .eq("is_ride_driver_approved", true)
      .eq("is_available_for_rides", true)
      .eq("is_online", true)
      .not("current_lat", "is", null)
      .not("current_lng", "is", null)
      .in("service_type", ["ride_sharing", "both"]);

    const DISPATCH_RADIUS_KM = 15;
    const MAX_DRIVERS = 5;
    const REQUEST_EXPIRY_SECONDS = 60;
    let driverRequestsSent = 0;

    if (candidateDrivers && candidateDrivers.length > 0) {
      const nearbyDrivers = candidateDrivers
        .map((d) => ({
          ...d,
          distance_km: haversineKm(ride.pickup_lat, ride.pickup_lng, d.current_lat, d.current_lng),
        }))
        .filter((d) => d.distance_km <= DISPATCH_RADIUS_KM)
        .sort((a, b) => a.distance_km - b.distance_km)
        .slice(0, MAX_DRIVERS);

      if (nearbyDrivers.length > 0) {
        const now = new Date();
        const expiresAt = new Date(now.getTime() + REQUEST_EXPIRY_SECONDS * 1000).toISOString();
        const rows = nearbyDrivers.map((d) => ({
          ride_id,
          driver_id: d.id,
          status: "pending",
          sent_at: now.toISOString(),
          expires_at: expiresAt,
        }));
        const { error: dispatchError } = await supabase.from("ride_driver_requests").insert(rows);
        if (!dispatchError) driverRequestsSent = nearbyDrivers.length;
      }
    }

    return new Response(
      JSON.stringify({ success: true, ride_id, status: "searching_driver", driver_requests_sent: driverRequestsSent }),
      { headers: corsHeaders, status: 200 }
    );
  } catch (error) {
    return new Response(
      JSON.stringify({ error: "Internal server error", details: error.message }),
      { status: 500, headers: corsHeaders }
    );
  }
});

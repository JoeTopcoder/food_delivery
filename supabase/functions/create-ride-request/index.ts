import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { Stripe } from "https://esm.sh/stripe@13.0.0";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2023-10-16",
});

interface CreateRideRequestPayload {
  pickup_address: string;
  pickup_lat: number;
  pickup_lng: number;
  destination_address: string;
  destination_lat: number;
  destination_lng: number;
  distance_km: number;
  estimated_duration_minutes: number;
  estimated_fare: number;
  platform_fee: number;
  payment_method: "card" | "cash" | "wallet";
  saved_card_id?: string;
  scheduled_for?: string;
}

function haversineKm(
  lat1: number,
  lng1: number,
  lat2: number,
  lng2: number
): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) *
      Math.cos(lat2 * Math.PI / 180) *
      Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Get auth token
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: corsHeaders }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const payload = await req.json() as CreateRideRequestPayload;

    // Decode JWT manually (no server re-validation)
    const jwtParts = token.split(".");
    const decodedPayload = JSON.parse(
      atob(jwtParts[1])
    ) as { sub: string; email: string };
    const customer_id = decodedPayload.sub;

    // Initialize Supabase
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get customer user — accept any non-admin, non-driver role
    const { data: customer, error: customerError } = await supabase
      .from("users")
      .select("id, email, role")
      .eq("id", customer_id)
      .single();

    if (customerError || !customer) {
      return new Response(
        JSON.stringify({ error: "User not found" }),
        { status: 403, headers: corsHeaders }
      );
    }

    // Block admin and driver-only accounts from booking rides as customers
    if (customer.role === "admin" || customer.role === "driver") {
      return new Response(
        JSON.stringify({ error: "This account cannot book rides as a customer" }),
        { status: 403, headers: corsHeaders }
      );
    }

    // Get pricing settings
    const { data: settings } = await supabase
      .from("ride_pricing_settings")
      .select("*")
      .eq("active", true)
      .limit(1)
      .single();

    // Determine if this is a scheduled ride (future-dated)
    const isScheduled = !!payload.scheduled_for &&
      new Date(payload.scheduled_for) > new Date();

    // Payment is pre-collected via Stripe Payment Sheet for immediate rides.
    // Scheduled rides defer payment to dispatch time.
    let payment_status = "pending";
    const payment_intent_id: string | null = null;

    if (!isScheduled && payload.payment_method === "card") {
      payment_status = "paid";
    }

    // Generate a 6-digit PIN for OTP verification when starting the ride
    const ride_pin = String(Math.floor(100000 + Math.random() * 900000));

    // Create ride request
    const { data: rideRequest, error: rideError } = await supabase
      .from("ride_requests")
      .insert({
        customer_id,
        pickup_address: payload.pickup_address,
        pickup_lat: payload.pickup_lat,
        pickup_lng: payload.pickup_lng,
        destination_address: payload.destination_address,
        destination_lat: payload.destination_lat,
        destination_lng: payload.destination_lng,
        distance_km: payload.distance_km,
        estimated_duration_minutes: payload.estimated_duration_minutes,
        estimated_fare: payload.estimated_fare,
        platform_fee: payload.platform_fee,
        driver_earning:
          payload.estimated_fare *
          (1 - (settings?.platform_commission_percent || 20) / 100),
        payment_status,
        payment_method: payload.payment_method,
        ride_status: isScheduled ? "scheduled" : "searching_driver",
        scheduled_for: payload.scheduled_for ?? null,
        ride_pin,
        requested_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (rideError || !rideRequest) {
      console.error("Error creating ride request:", rideError);
      return new Response(
        JSON.stringify({ error: "Failed to create ride request" }),
        { status: 500, headers: corsHeaders }
      );
    }

    // ── Driver dispatch ─────────────────────────────────────────────────────
    // Skip dispatch for scheduled rides — drivers are notified at activation time.
    if (isScheduled) {
      return new Response(
        JSON.stringify({
          ride_id: rideRequest.id,
          status: "scheduled",
          payment_status,
          scheduled_for: payload.scheduled_for,
          message: "Ride scheduled successfully.",
        }),
        { headers: corsHeaders, status: 201 }
      );
    }

    // Query all online, approved, ride-capable drivers who have a known location.
    const { data: candidateDrivers, error: driversError } = await supabase
      .from("drivers")
      .select("id, current_lat, current_lng")
      .eq("is_ride_driver_approved", true)
      .eq("is_available_for_rides", true)
      .eq("is_online", true)
      .not("current_lat", "is", null)
      .not("current_lng", "is", null)
      .in("service_type", ["ride_sharing", "both"]);

    if (driversError) {
      // Non-fatal: ride was created successfully; log and continue.
      console.error("Error fetching candidate drivers:", driversError);
    }

    const DISPATCH_RADIUS_KM = 15;
    const MAX_DRIVERS = 5;
    const REQUEST_EXPIRY_SECONDS = 60;

    let driverRequestsSent = 0;

    if (candidateDrivers && candidateDrivers.length > 0) {
      // Filter by Haversine distance and take the 5 closest.
      const nearbyDrivers = candidateDrivers
        .map((driver) => ({
          ...driver,
          distance_km: haversineKm(
            payload.pickup_lat,
            payload.pickup_lng,
            driver.current_lat,
            driver.current_lng
          ),
        }))
        .filter((d) => d.distance_km <= DISPATCH_RADIUS_KM)
        .sort((a, b) => a.distance_km - b.distance_km)
        .slice(0, MAX_DRIVERS);

      if (nearbyDrivers.length > 0) {
        const now = new Date();
        const expiresAt = new Date(
          now.getTime() + REQUEST_EXPIRY_SECONDS * 1000
        ).toISOString();

        const driverRequestRows = nearbyDrivers.map((driver) => ({
          ride_id: rideRequest.id,
          driver_id: driver.id,
          status: "pending",
          sent_at: now.toISOString(),
          expires_at: expiresAt,
        }));

        const { error: dispatchError } = await supabase
          .from("ride_driver_requests")
          .insert(driverRequestRows);

        if (dispatchError) {
          console.error("Error inserting driver requests:", dispatchError);
        } else {
          driverRequestsSent = nearbyDrivers.length;
        }
      }
    }
    // ── End driver dispatch ──────────────────────────────────────────────────

    return new Response(
      JSON.stringify({
        ride_id: rideRequest.id,
        status: "searching_driver",
        payment_status,
        payment_intent_id,
        driver_requests_sent: driverRequestsSent,
        message: "Ride request created, searching for drivers...",
      }),
      {
        headers: corsHeaders,
        status: 201,
      }
    );
  } catch (error) {
    console.error("Error in create_ride_request:", error);
    return new Response(
      JSON.stringify({
        error: "Internal server error",
        details: error.message,
      }),
      { status: 500, headers: corsHeaders }
    );
  }
});

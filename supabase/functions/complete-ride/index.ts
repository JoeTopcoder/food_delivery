import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { Stripe } from "https://esm.sh/stripe@13.0.0";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2023-10-16",
});

interface CompleteRidePayload {
  ride_id: string;
  final_distance_km?: number;
  final_duration_minutes?: number;
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
    const jwtParts = token.split(".");
    const decodedPayload = JSON.parse(
      atob(jwtParts[1])
    ) as { sub: string; email: string };
    const user_id = decodedPayload.sub;

    const payload = await req.json() as CompleteRidePayload;

    // Initialize Supabase
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Get ride
    const { data: ride, error: rideError } = await supabase
      .from("ride_requests")
      .select("*")
      .eq("id", payload.ride_id)
      .single();

    if (rideError || !ride) {
      return new Response(
        JSON.stringify({ error: "Ride not found" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // Check authorization: only assigned driver or admin can complete
    const { data: driver } = await supabase
      .from("drivers")
      .select("id, user_id")
      .eq("user_id", user_id)
      .single();

    const { data: user } = await supabase
      .from("users")
      .select("role")
      .eq("id", user_id)
      .single();

    const isDriver = ride.driver_id && driver?.id === ride.driver_id;
    const isAdmin = user?.role === "admin";

    if (!isDriver && !isAdmin) {
      return new Response(
        JSON.stringify({ error: "Only assigned driver or admin can complete ride" }),
        { status: 403, headers: corsHeaders }
      );
    }

    // Allow completion from ride_started or ride_paused (driver may complete without resuming)
    if (ride.ride_status !== "ride_started" && ride.ride_status !== "ride_paused") {
      return new Response(
        JSON.stringify({
          error: `Ride must be in 'ride_started' or 'ride_paused' status, current: ${ride.ride_status}`,
        }),
        { status: 400, headers: corsHeaders }
      );
    }

    // Get pricing settings
    const { data: settings } = await supabase
      .from("ride_pricing_settings")
      .select("*")
      .eq("active", true)
      .limit(1)
      .single();

    // Calculate final fare if final distance/duration provided
    let final_fare = ride.estimated_fare;
    if (
      payload.final_distance_km !== undefined &&
      payload.final_duration_minutes !== undefined
    ) {
      final_fare = calculateFinalFare(
        payload.final_distance_km,
        payload.final_duration_minutes,
        settings
      );
    }

    // Add accrued waiting fee if applicable
    if (ride.waiting_started_at && ride.waiting_fee_per_min) {
      const waitingStartedAt = new Date(ride.waiting_started_at);
      const now = new Date();
      const waitingMinutes = (now.getTime() - waitingStartedAt.getTime()) / 60000;
      const waitingFee = parseFloat((Math.max(0, waitingMinutes) * ride.waiting_fee_per_min).toFixed(2));
      final_fare = parseFloat((final_fare + waitingFee).toFixed(2));
    }

    const platform_fee = parseFloat(((final_fare * (settings?.platform_commission_percent || 20)) / 100).toFixed(2));
    const driver_earning = parseFloat((final_fare - platform_fee).toFixed(2));

    // If card payment, capture the authorized payment
    let payment_status = ride.payment_status;
    if (ride.payment_method === "card" && ride.payment_status === "authorized") {
      try {
        // Create a charge from the payment intent
        // In production, you would confirm the PaymentIntent with the final amount
        payment_status = "paid";
      } catch (stripeError) {
        console.error("Stripe charge error:", stripeError);
        return new Response(
          JSON.stringify({
            error: "Failed to capture payment",
            details: stripeError.message,
          }),
          { status: 400, headers: corsHeaders }
        );
      }
    } else if (ride.payment_method === "cash") {
      payment_status = "cash_pending";
    } else if (ride.payment_method === "wallet") {
      payment_status = "paid";
    }

    // Update ride to completed
    const { data: updatedRide, error: updateError } = await supabase
      .from("ride_requests")
      .update({
        ride_status: "ride_completed",
        final_fare,
        platform_fee,
        driver_earning,
        payment_status,
        completed_at: new Date().toISOString(),
      })
      .eq("id", payload.ride_id)
      .select()
      .single();

    if (updateError) {
      console.error("Error updating ride:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to complete ride" }),
        { status: 500, headers: corsHeaders }
      );
    }

    // TODO: Create driver earnings record or update daily earnings
    // This could be a separate function or table

    return new Response(
      JSON.stringify({
        message: "Ride completed successfully",
        ride: updatedRide,
        final_fare,
        driver_earning,
        platform_fee,
        payment_status,
      }),
      {
        headers: corsHeaders,
        status: 200,
      }
    );
  } catch (error) {
    console.error("Error completing ride:", error);
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
 * Calculate final fare based on actual distance and duration
 */
function calculateFinalFare(
  distance_km: number,
  duration_minutes: number,
  settings: any
): number {
  const base_fare = settings?.base_fare || 3.0;
  const per_km_rate = settings?.per_km_rate || 1.2;
  const per_minute_rate = settings?.per_minute_rate || 0.25;
  const minimum_fare = settings?.minimum_fare || 5.0;
  const surge_multiplier = settings?.surge_multiplier || 1.0;

  const distance_cost = distance_km * per_km_rate;
  const time_cost = duration_minutes * per_minute_rate;
  let subtotal = base_fare + distance_cost + time_cost;
  subtotal = Math.max(subtotal, minimum_fare);

  const surged_total = subtotal * surge_multiplier;
  return parseFloat(surged_total.toFixed(2));
}

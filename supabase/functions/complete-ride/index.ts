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

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

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

    if (ride.ride_status !== "ride_started" && ride.ride_status !== "ride_paused") {
      return new Response(
        JSON.stringify({
          error: `Ride must be in 'ride_started' or 'ride_paused' status, current: ${ride.ride_status}`,
        }),
        { status: 400, headers: corsHeaders }
      );
    }

    const { data: settings } = await supabase
      .from("ride_pricing_settings")
      .select("*")
      .eq("active", true)
      .limit(1)
      .single();

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

    if (ride.waiting_started_at && ride.waiting_fee_per_min) {
      const waitingStartedAt = new Date(ride.waiting_started_at);
      const now = new Date();
      const waitingMinutes = (now.getTime() - waitingStartedAt.getTime()) / 60000;
      const waitingFee = parseFloat((Math.max(0, waitingMinutes) * ride.waiting_fee_per_min).toFixed(2));
      final_fare = parseFloat((final_fare + waitingFee).toFixed(2));
    }

    const platform_fee = parseFloat(((final_fare * (settings?.platform_commission_percent || 20)) / 100).toFixed(2));
    const driver_earning = parseFloat((final_fare - platform_fee).toFixed(2));

    // ── Stripe capture ────────────────────────────────────────────────────────
    let payment_status = ride.payment_status;

    if (
      ride.payment_method === "card" &&
      ride.payment_status === "authorized" &&
      ride.stripe_payment_intent_id
    ) {
      try {
        // Always retrieve current status first — the PI may have already been
        // captured by an earlier flow (e.g. immediate-capture PaymentScreen).
        const pi = await stripe.paymentIntents.retrieve(ride.stripe_payment_intent_id);

        if (pi.status === "succeeded") {
          // PI already captured (immediate-capture flow).
          // If the final fare exceeds what was already charged (e.g. wait fee
          // accrued), create a supplemental off-session charge for the difference.
          const alreadyCapturedCents = (pi.amount_received as number) ?? (pi.amount as number) ?? 0;
          const finalFareCents = Math.round(final_fare * 100);

          if (finalFareCents > alreadyCapturedCents && pi.customer && pi.payment_method) {
            try {
              await stripe.paymentIntents.create({
                amount: finalFareCents - alreadyCapturedCents,
                currency: (pi.currency as string) ?? "usd",
                customer: pi.customer as string,
                payment_method: pi.payment_method as string,
                off_session: true,
                confirm: true,
                description: `Wait/additional fare — ride ${payload.ride_id}`,
                metadata: { type: "ride_adjustment", ride_id: payload.ride_id },
              });
            } catch (extraErr) {
              // Log but don't block ride completion if supplemental charge fails.
              console.warn("Supplemental charge failed:", (extraErr as Error).message);
            }
          }
          payment_status = "paid";
        } else if (pi.status === "requires_capture") {
          const authorizedAmount: number = ride.authorized_amount ?? ride.estimated_fare ?? 0;
          const finalFareCents = Math.round(final_fare * 100);
          const authorizedCents = Math.round(authorizedAmount * 100);

          // If the final fare exceeds the original authorization, attempt incremental
          // authorization to raise the cap before capturing.
          if (finalFareCents > authorizedCents) {
            try {
              await stripe.paymentIntents.incrementAuthorization(
                ride.stripe_payment_intent_id,
                { amount: finalFareCents }
              );
            } catch (incrErr) {
              // Card or PI doesn't support incremental auth.
              // Capture up to the originally authorized amount instead.
              console.warn("Incremental auth failed, capturing authorized amount:", (incrErr as Error).message);
              final_fare = parseFloat((authorizedCents / 100).toFixed(2));
            }
          }

          const captured = await stripe.paymentIntents.capture(
            ride.stripe_payment_intent_id,
            { amount_to_capture: Math.round(final_fare * 100) }
          );
          payment_status = captured.status === "succeeded" ? "paid" : "authorized";
        } else {
          // Cancelled, failed, or unknown — log and treat as paid to not block completion.
          console.warn("Unexpected PI status at ride completion:", pi.status);
          payment_status = "paid";
        }
      } catch (stripeError) {
        console.error("Stripe capture error:", stripeError);
        return new Response(
          JSON.stringify({
            error: "Failed to capture payment",
            details: (stripeError as Error).message,
          }),
          { status: 400, headers: corsHeaders }
        );
      }
    } else if (ride.payment_method === "cash") {
      payment_status = "cash_pending";
    } else if (ride.payment_method === "wallet") {
      payment_status = "paid";
    }
    // ── End Stripe capture ───────────────────────────────────────────────────

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
        details: (error as Error).message,
      }),
      { status: 500, headers: corsHeaders }
    );
  }
});

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

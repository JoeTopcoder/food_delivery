import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { Stripe } from "https://esm.sh/stripe@13.0.0";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY") ?? "", {
  apiVersion: "2023-10-16",
});

const VALID_TRANSITIONS: Record<string, string[]> = {
  requested: ["searching_driver", "cancelled"],
  searching_driver: ["driver_assigned", "cancelled"],
  driver_assigned: ["driver_arriving", "driver_arrived", "cancelled"],
  driver_arriving: ["driver_arrived", "cancelled"],
  driver_arrived: ["ride_started", "cancelled"],
  ride_started: ["ride_completed", "cancelled", "ride_paused"],
  ride_paused: ["ride_started", "cancelled"],
  ride_completed: [],
  cancelled: [],
  failed: [],
};

const WAITING_FEE_PER_MIN = 75.0;

interface UpdateRideStatusPayload {
  ride_id: string;
  new_status?: string;
  start_waiting?: boolean;
  driver_id?: string;
  latitude?: number;
  longitude?: number;
  pin?: string;
  pause_reason?: string;
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
    const decodedPayload = JSON.parse(atob(jwtParts[1])) as {
      sub: string;
      email: string;
    };
    const user_id = decodedPayload.sub;

    const payload = (await req.json()) as UpdateRideStatusPayload;

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
      return new Response(JSON.stringify({ error: "Ride not found" }), {
        status: 404,
        headers: corsHeaders,
      });
    }

    const { data: driver } = await supabase
      .from("drivers")
      .select("id")
      .eq("user_id", user_id)
      .single();

    const isCustomer = ride.customer_id === user_id;
    const isDriver =
      ride.driver_id != null && driver?.id === ride.driver_id;
    const isAnyDriver = driver != null;

    const { data: userRow } = await supabase
      .from("users")
      .select("role")
      .eq("id", user_id)
      .single();
    const isAdmin = userRow?.role === "admin";

    if (!isCustomer && !isDriver && !isAdmin && !isAnyDriver) {
      return new Response(
        JSON.stringify({ error: "Unauthorized to update this ride" }),
        { status: 403, headers: corsHeaders }
      );
    }

    // ── start_waiting ─────────────────────────────────────────────────────────
    if (payload.start_waiting === true) {
      if (!isDriver && !isAdmin) {
        return new Response(
          JSON.stringify({ error: "Only the assigned driver can start the waiting fee" }),
          { status: 403, headers: corsHeaders }
        );
      }

      const { error: waitErr } = await supabase
        .from("ride_requests")
        .update({
          waiting_started_at: new Date().toISOString(),
          waiting_fee_per_min: WAITING_FEE_PER_MIN,
        })
        .eq("id", payload.ride_id);

      if (waitErr) {
        return new Response(
          JSON.stringify({ error: "Failed to start waiting fee" }),
          { status: 500, headers: corsHeaders }
        );
      }

      return new Response(
        JSON.stringify({ message: "Waiting fee started", rate: WAITING_FEE_PER_MIN }),
        { status: 200, headers: corsHeaders }
      );
    }

    // ── Normal status transition ──────────────────────────────────────────────
    if (!payload.new_status) {
      return new Response(
        JSON.stringify({ error: "new_status is required" }),
        { status: 400, headers: corsHeaders }
      );
    }

    const validNextStatuses = VALID_TRANSITIONS[ride.ride_status] || [];
    if (!validNextStatuses.includes(payload.new_status)) {
      return new Response(
        JSON.stringify({
          error: `Invalid status transition from ${ride.ride_status} to ${payload.new_status}`,
        }),
        { status: 400, headers: corsHeaders }
      );
    }

    if (
      payload.new_status === "ride_started" &&
      ride.ride_status === "driver_arrived"
    ) {
      if (!payload.pin || payload.pin.trim() !== ride.ride_pin) {
        return new Response(
          JSON.stringify({
            error: "Invalid PIN. Ask the customer for their 6-digit code.",
          }),
          { status: 400, headers: corsHeaders }
        );
      }
    }

    const updateData: Record<string, unknown> = {
      ride_status: payload.new_status,
    };

    if (payload.new_status === "driver_arriving") {
      updateData.accepted_at = new Date().toISOString();
    } else if (payload.new_status === "driver_arrived") {
      updateData.driver_arrived_at = new Date().toISOString();
    } else if (payload.new_status === "ride_started") {
      updateData.started_at = new Date().toISOString();
      updateData.pause_reason = null;
    } else if (payload.new_status === "ride_paused") {
      updateData.pause_reason = payload.pause_reason ?? null;
      updateData.paused_at = new Date().toISOString();
    } else if (payload.new_status === "ride_completed") {
      updateData.completed_at = new Date().toISOString();
    } else if (payload.new_status === "cancelled") {
      if (isCustomer) {
        updateData.cancelled_by = "customer";

        const chargeableStatuses = [
          "driver_assigned",
          "driver_arriving",
          "driver_arrived",
          "ride_started",
        ];

        if (chargeableStatuses.includes(ride.ride_status)) {
          const baseFee: number =
            ride.driver_earning ??
            (ride.estimated_fare ? ride.estimated_fare * 0.8 : 0);

          let waitingExtra = 0;
          if (ride.waiting_started_at) {
            const waitingMs =
              Date.now() - new Date(ride.waiting_started_at).getTime();
            const waitingMins = waitingMs / 60000;
            const ratePerMin: number = ride.waiting_fee_per_min ?? WAITING_FEE_PER_MIN;
            waitingExtra = Math.max(0, waitingMins) * ratePerMin;
          }

          updateData.cancellation_fee = parseFloat(
            (baseFee + waitingExtra).toFixed(2)
          );
        }
      } else if (isDriver) {
        updateData.cancelled_by = "driver";
      } else if (isAdmin) {
        updateData.cancelled_by = "admin";
      }

      // ── Stripe payment handling for cancellation ──────────────────────────
      // Only applies to card payments that have an authorized Stripe PI.
      if (
        ride.payment_method === "card" &&
        ride.payment_status === "authorized" &&
        ride.stripe_payment_intent_id
      ) {
        const cancellationFee = (updateData.cancellation_fee as number) ?? 0;

        try {
          if (cancellationFee > 0) {
            // Partial capture — charge only the cancellation fee
            await stripe.paymentIntents.capture(ride.stripe_payment_intent_id, {
              amount_to_capture: Math.round(cancellationFee * 100),
            });
            updateData.payment_status = "paid";
          } else {
            // No charge — release the full authorization
            await stripe.paymentIntents.cancel(ride.stripe_payment_intent_id);
            updateData.payment_status = "cancelled";
          }
        } catch (stripeErr) {
          // Don't block the ride cancellation if Stripe call fails.
          // payment_status stays "authorized" for manual review.
          console.error("Stripe cancellation payment error:", stripeErr);
        }
      }

      // ── Wallet refund for cancellation ───────────────────────────────────
      if (ride.payment_method === "wallet" && ride.payment_status === "paid") {
        const cancellationFee = (updateData.cancellation_fee as number) ?? 0;
        const refundAmount = parseFloat(
          Math.max(0, (ride.estimated_fare ?? 0) - cancellationFee).toFixed(2)
        );
        if (refundAmount > 0) {
          const { error: refundErr } = await supabase.rpc("wallet_credit", {
            p_user_id:     ride.customer_id,
            p_amount:      refundAmount,
            p_description: cancellationFee > 0
              ? `Ride refund (cancellation fee $${cancellationFee.toFixed(2)} deducted)`
              : "Ride refund — cancelled before pickup",
          });
          if (refundErr) {
            console.error("Wallet refund error:", refundErr.message);
          } else {
            updateData.payment_status = "refunded";
          }
        } else {
          updateData.payment_status = "paid";
        }
      }
      // ── End wallet refund ─────────────────────────────────────────────────
    }

    const { data: updatedRide, error: updateError } = await supabase
      .from("ride_requests")
      .update(updateData)
      .eq("id", payload.ride_id)
      .select()
      .single();

    if (updateError) {
      console.error("Error updating ride:", updateError);
      return new Response(
        JSON.stringify({ error: "Failed to update ride" }),
        { status: 500, headers: corsHeaders }
      );
    }

    if (
      payload.latitude !== undefined &&
      payload.longitude !== undefined
    ) {
      await supabase.from("ride_locations").insert({
        ride_id: payload.ride_id,
        driver_id: ride.driver_id,
        lat: payload.latitude,
        lng: payload.longitude,
      });
    }

    return new Response(
      JSON.stringify({ message: "Ride status updated", ride: updatedRide }),
      { status: 200, headers: corsHeaders }
    );
  } catch (error) {
    console.error("Error updating ride status:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: (error as Error).message }),
      { status: 500, headers: corsHeaders }
    );
  }
});

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
  // PI already authorized via Payment Sheet (preferred path)
  stripe_payment_intent_id?: string;
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

const _adminClient = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
);

async function notifyUser(userId: string, title: string, body: string, data: Record<string, string>) {
  try {
    const { data: user } = await _adminClient.from("users").select("fcm_token").eq("id", userId).maybeSingle();
    if (!user?.fcm_token) return;
    await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-fcm-notification`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "Authorization": `Bearer ${Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")}` },
      body: JSON.stringify({ token: user.fcm_token, title, body, data }),
    });
  } catch { /* non-critical */ }
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
    const payload = await req.json() as CreateRideRequestPayload;

    const jwtParts = token.split(".");
    const decodedPayload = JSON.parse(
      atob(jwtParts[1])
    ) as { sub: string; email: string };
    const customer_id = decodedPayload.sub;

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

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

    if (customer.role === "admin" || customer.role === "driver") {
      return new Response(
        JSON.stringify({ error: "This account cannot book rides as a customer" }),
        { status: 403, headers: corsHeaders }
      );
    }

    const { data: settings } = await supabase
      .from("ride_pricing_settings")
      .select("*")
      .eq("active", true)
      .limit(1)
      .single();

    const isScheduled = !!payload.scheduled_for &&
      new Date(payload.scheduled_for) > new Date();

    // ── Payment handling ─────────────────────────────────────────────────────
    // Four paths:
    //   1. stripe_payment_intent_id provided → Payment Sheet already authorized.
    //   2. saved_card_id provided → create off-session PI.
    //   3. wallet → deduct from wallet, mark "paid".
    //   4. cash → no payment now; payment_status stays "pending".
    let payment_status = "pending";
    let stripe_payment_intent_id: string | null = payload.stripe_payment_intent_id ?? null;
    let authorized_amount: number | null = null;

    // Path 3 — wallet payment
    if (payload.payment_method === "wallet") {
      const { error: walletErr } = await supabase.rpc("wallet_deduct", {
        p_user_id:    customer_id,
        p_amount:     payload.estimated_fare,
        p_description: `Ride payment`,
      });
      if (walletErr) {
        const isInsufficient = (walletErr.message ?? "").toLowerCase().includes("insufficient");
        return new Response(
          JSON.stringify({ error: isInsufficient ? "Insufficient wallet balance" : walletErr.message }),
          { status: 402, headers: corsHeaders }
        );
      }
      payment_status = "paid";
    }

    if (!isScheduled && payload.payment_method === "card") {
      if (stripe_payment_intent_id) {
        // Path 1: PI already created via Payment Sheet — just record it.
        authorized_amount = payload.estimated_fare;
        payment_status = "authorized";
      } else if (payload.saved_card_id) {
        // Path 2: Off-session booking with a saved card.
        const { data: card } = await supabase
          .from("saved_cards")
          .select("stripe_payment_method_id, stripe_customer_id")
          .eq("id", payload.saved_card_id)
          .single();

        if (!card?.stripe_payment_method_id || !card?.stripe_customer_id) {
          return new Response(
            JSON.stringify({ error: "Invalid saved card — Stripe payment method not found" }),
            { status: 400, headers: corsHeaders }
          );
        }

        const bufferPct = (settings?.card_auth_buffer_percent as number) ?? 50;
        authorized_amount = parseFloat((payload.estimated_fare * (1 + bufferPct / 100)).toFixed(2));
        const authorizedCents = Math.round(authorized_amount * 100);

        try {
          const pi = await stripe.paymentIntents.create({
            amount: authorizedCents,
            currency: "jmd",
            customer: card.stripe_customer_id,
            payment_method: card.stripe_payment_method_id,
            capture_method: "manual",
            confirm: true,
            off_session: true,
            description: `Ride authorization — customer ${customer_id}`,
            metadata: { type: "ride", user_id: customer_id },
          });
          stripe_payment_intent_id = pi.id;
          payment_status = "authorized";
        } catch (stripeErr) {
          console.error("Stripe authorization failed:", stripeErr);
          return new Response(
            JSON.stringify({
              error: "Payment authorization failed",
              details: (stripeErr as Error).message,
            }),
            { status: 402, headers: corsHeaders }
          );
        }
      }
      // Path 3: no PI and no saved card → leave payment_status as "pending"
    }
    // ── End Stripe payment handling ───────────────────────────────────────────

    const ride_pin = String(Math.floor(100000 + Math.random() * 900000));

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
        saved_card_id: payload.saved_card_id ?? null,
        stripe_payment_intent_id,
        authorized_amount,
        ride_status: isScheduled ? "scheduled" : "searching_driver",
        scheduled_for: payload.scheduled_for ?? null,
        ride_pin,
        requested_at: new Date().toISOString(),
      })
      .select()
      .single();

    if (rideError || !rideRequest) {
      // If ride insert fails but we already authorized a Stripe PI, cancel it
      if (stripe_payment_intent_id) {
        await stripe.paymentIntents.cancel(stripe_payment_intent_id).catch(() => {});
      }
      console.error("Error creating ride request:", rideError);
      return new Response(
        JSON.stringify({ error: "Failed to create ride request" }),
        { status: 500, headers: corsHeaders }
      );
    }

    // Update PI metadata to include ride_id now that we have it
    if (stripe_payment_intent_id) {
      await stripe.paymentIntents.update(stripe_payment_intent_id, {
        metadata: { type: "ride", user_id: customer_id, ride_id: rideRequest.id },
      }).catch(() => {}); // non-critical
    }

    // ── Driver dispatch ─────────────────────────────────────────────────────
    if (isScheduled) {
      await notifyUser(customer_id, '🕐 Ride Scheduled!', `Your ride has been scheduled. We'll find you a driver closer to your pickup time.`, {
        type: 'ride_scheduled', ride_id: rideRequest.id,
      });
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
      console.error("Error fetching candidate drivers:", driversError);
    }

    const DISPATCH_RADIUS_KM = 15;
    const MAX_DRIVERS = 5;
    const REQUEST_EXPIRY_SECONDS = 60;

    let driverRequestsSent = 0;

    if (candidateDrivers && candidateDrivers.length > 0) {
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

    await notifyUser(customer_id, '🚗 Ride Requested!', 'We\'re searching for a nearby driver. You\'ll be notified when one accepts.', {
      type: 'ride_requested', ride_id: rideRequest.id,
    });

    return new Response(
      JSON.stringify({
        ride_id: rideRequest.id,
        status: "searching_driver",
        payment_status,
        stripe_payment_intent_id,
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
        details: (error as Error).message,
      }),
      { status: 500, headers: corsHeaders }
    );
  }
});

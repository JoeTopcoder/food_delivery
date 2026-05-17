import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { Stripe } from "https://esm.sh/stripe@13.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, {
  apiVersion: "2023-10-16",
});

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Verify token and get user
    const token = authHeader.replace("Bearer ", "");
    const {
      data: { user },
      error: authError,
    } = await supabase.auth.getUser(token);
    if (authError || !user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), {
        status: 401,
        headers: corsHeaders,
      });
    }

    const { ride_id } = await req.json();
    if (!ride_id) {
      return new Response(JSON.stringify({ error: "ride_id required" }), {
        status: 400,
        headers: corsHeaders,
      });
    }

    // Fetch ride
    const { data: ride } = await supabase
      .from("ride_requests")
      .select(
        "id, driver_id, customer_id, payment_method, saved_card_id, waiting_started_at, waiting_fee_per_min",
      )
      .eq("id", ride_id)
      .single();

    if (!ride) {
      return new Response(JSON.stringify({ error: "Ride not found" }), {
        status: 404,
        headers: corsHeaders,
      });
    }

    // Verify requester is the assigned driver
    const { data: driver } = await supabase
      .from("drivers")
      .select("id")
      .eq("user_id", user.id)
      .single();

    if (!driver || driver.id !== ride.driver_id) {
      return new Response(JSON.stringify({ error: "Forbidden" }), {
        status: 403,
        headers: corsHeaders,
      });
    }

    // No active pause charge
    if (!ride.waiting_started_at) {
      return new Response(
        JSON.stringify({ amount: 0, status: "no_charge" }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Calculate accrued fee
    const startedAt = new Date(ride.waiting_started_at);
    const now = new Date();
    const minutesElapsed = (now.getTime() - startedAt.getTime()) / 60000;
    const ratePerMin: number = ride.waiting_fee_per_min ?? 75.0;
    const pauseFeeJmd =
      Math.round(minutesElapsed * ratePerMin * 100) / 100;

    let chargeStatus = "charge_failed";
    let stripePaymentIntentId: string | null = null;

    if (pauseFeeJmd >= 1) {
      if (ride.payment_method === "card" && ride.saved_card_id) {
        // Look up the saved card for off-session charge
        const { data: card } = await supabase
          .from("saved_cards")
          .select("stripe_payment_method_id, stripe_customer_id")
          .eq("id", ride.saved_card_id)
          .single();

        if (card?.stripe_payment_method_id && card?.stripe_customer_id) {
          try {
            const pi = await stripe.paymentIntents.create({
              amount: Math.round(pauseFeeJmd * 100), // JMD → cents
              currency: "jmd",
              customer: card.stripe_customer_id,
              payment_method: card.stripe_payment_method_id,
              confirm: true,
              off_session: true,
              description: `Pause/wait fee – ride ${ride_id}`,
              metadata: { ride_id, type: "pause_fee" },
            });
            chargeStatus =
              pi.status === "succeeded" ? "charged" : "pending";
            stripePaymentIntentId = pi.id;
          } catch (_err) {
            chargeStatus = "charge_failed";
          }
        } else {
          chargeStatus = "charge_failed";
        }
      } else if (ride.payment_method === "wallet") {
        const { data: wallet } = await supabase
          .from("wallets")
          .select("id, balance")
          .eq("user_id", ride.customer_id)
          .single();

        if (wallet && (wallet.balance ?? 0) >= pauseFeeJmd) {
          await supabase
            .from("wallets")
            .update({ balance: wallet.balance - pauseFeeJmd })
            .eq("id", wallet.id);
          chargeStatus = "charged";
        } else {
          chargeStatus = "insufficient_funds";
        }
      } else {
        chargeStatus = "charge_failed";
      }
    } else {
      chargeStatus = "no_charge";
    }

    // Clear waiting fee so complete_ride_rpc does not double-count it
    await supabase
      .from("ride_requests")
      .update({ waiting_started_at: null, waiting_fee_per_min: null })
      .eq("id", ride_id);

    return new Response(
      JSON.stringify({
        amount: pauseFeeJmd,
        payment_method: ride.payment_method,
        status: chargeStatus,
        stripe_payment_intent_id: stripePaymentIntentId,
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      },
    );
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : "Internal error";
    return new Response(JSON.stringify({ error: msg }), {
      status: 500,
      headers: corsHeaders,
    });
  }
});

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@13.0.0";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });

// Service-role client, used only to verify the caller's JWT. Same pattern as
// place-order, which is self-contained rather than importing stripe-shared.
const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);

serve(async (req) => {
  try {
    // The token has to be VERIFIED, not merely present. This previously
    // checked only that the header started with "Bearer ", which the
    // anon key satisfies — and the anon key ships in every app build, so
    // anyone holding it could create Stripe customers and PaymentIntents
    // against the live account.
    const authHeader = req.headers.get("Authorization") ?? "";
    const token = authHeader.toLowerCase().startsWith("bearer ")
      ? authHeader.slice(7)
      : "";
    if (!token) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }
    const { data: authUser, error: authErr } = await admin.auth.getUser(token);
    if (authErr || !authUser?.user) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    const { amount, currency, name } = await req.json();

    if (!amount || amount < 50) {
      return new Response(JSON.stringify({ error: "Invalid amount" }), { status: 400 });
    }

    // The email comes from the verified token, never from the body. The
    // response hands back a customer id and an ephemeral key, and an
    // ephemeral key lets the mobile SDK list and attach payment methods for
    // that customer — so trusting a body-supplied email meant anyone could
    // ask for another person's saved cards by typing their address.
    const email = authUser.user.email ?? "";
    if (!email) {
      return new Response(
        JSON.stringify({ error: "Account has no email address" }),
        { status: 400 },
      );
    }

    // Find or create Stripe customer
    let customer;
    const customers = await stripe.customers.list({ email, limit: 1 });
    if (customers.data.length > 0) {
      customer = customers.data[0];
    } else {
      customer = await stripe.customers.create({ email, name });
    }

    // Create ephemeral key for mobile
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customer.id },
      { apiVersion: "2023-10-16" }
    );

    // The Stripe account accepts JMD directly, so the amount passes through
    // and the customer is charged exactly the price they were shown.
    //
    // This replaces a hardcoded 155:1 conversion that divided the JMD amount
    // and charged USD. That was safe but drifted with the real rate, and it
    // disagreed with place-order, which sent the same JMD amount
    // as "usd" with no conversion at all — a ~155x overcharge on the
    // saved-card path. One currency everywhere removes the discrepancy.
    const chargeCurrency = String(currency ?? "jmd").toLowerCase();
    const chargeAmount = Math.round(amount);

    // Create PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: chargeAmount, // in the smallest unit of chargeCurrency
      currency: chargeCurrency,
      customer: customer.id,
      automatic_payment_methods: { enabled: true },
      metadata: {
        // Presented and charged are the same figure now. Kept so that intents
        // created before this change — which were converted at a fixed rate —
        // and new ones can still be read the same way in reconciliation.
        email,
        presented_currency: chargeCurrency,
        presented_amount: String(chargeAmount),
      },
    });

    return new Response(
      JSON.stringify({
        clientSecret: paymentIntent.client_secret,
        customerId: customer.id,
        ephemeralKey: ephemeralKey.secret,
      }),
      { status: 200 }
    );
  } catch (err) {
    console.error("Stripe error:", err);
    return new Response(
      JSON.stringify({ error: err.message || "Internal error" }),
      { status: 500 }
    );
  }
});

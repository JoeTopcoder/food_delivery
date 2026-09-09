import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import Stripe from "https://esm.sh/stripe@13.0.0";

const stripe = new Stripe(Deno.env.get("STRIPE_SECRET_KEY")!, { apiVersion: "2023-10-16" });

serve(async (req) => {
  try {
    // Auth check
    const authHeader = req.headers.get("Authorization");
    if (!authHeader || !authHeader.startsWith("Bearer ")) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401 });
    }

    const { amount, currency, email, name } = await req.json();

    if (!amount || amount < 50) {
      return new Response(JSON.stringify({ error: "Invalid amount" }), { status: 400 });
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

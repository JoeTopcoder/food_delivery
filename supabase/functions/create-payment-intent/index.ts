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

    // The platform prices in JMD but this Stripe account settles in USD, so the
    // amount is converted at the boundary. Without this a J$2,790 order would
    // be charged as US$2,790 — roughly 155x — against live cards.
    //
    // Remove this conversion when payments move to NCB and the processor
    // actually settles in JMD; at that point the amount passes through
    // unchanged and `currency` becomes "jmd".
    const FX_JMD_PER_USD = 155;
    const requested = String(currency ?? "usd").toLowerCase();
    const chargeCurrency = requested === "jmd" ? "usd" : requested;
    const chargeAmount = requested === "jmd"
      ? Math.round(amount / FX_JMD_PER_USD)
      : Math.round(amount);

    // Create PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount: chargeAmount, // in the smallest unit of chargeCurrency
      currency: chargeCurrency,
      customer: customer.id,
      automatic_payment_methods: { enabled: true },
      metadata: {
        email,
        // Recorded so a JMD-priced order can be reconciled against a USD
        // capture without guesswork.
        presented_currency: requested,
        presented_amount: String(Math.round(amount)),
        fx_jmd_per_usd: requested === "jmd" ? String(FX_JMD_PER_USD) : "",
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

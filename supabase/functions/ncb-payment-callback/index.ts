// NCB Payment Callback Edge Function
// Handles both GET (redirect from payment page) and POST (webhook from NCB)
// Updates payments and orders tables with the result

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

function html(status: string, message: string) {
  return new Response(
    `<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width,initial-scale=1" />
    <title>FoodDriver Payment</title>
    <style>
      body { font-family: Arial, sans-serif; background: #f6f7fb; color: #111827; display:flex; align-items:center; justify-content:center; min-height:100vh; margin:0; }
      .card { width:min(92vw,420px); background:white; border-radius:16px; padding:24px; box-shadow:0 16px 48px rgba(17,24,39,.12); }
      .badge { display:inline-block; padding:6px 10px; border-radius:999px; font-size:12px; font-weight:700; background:${status === "success" ? "#dcfce7" : "#fee2e2"}; color:${status === "success" ? "#166534" : "#991b1b"}; }
      h1 { margin:12px 0 8px; font-size:22px; }
      p { margin:0; line-height:1.5; color:#4b5563; }
    </style>
  </head>
  <body>
    <div class="card">
      <span class="badge">${status === "success" ? "Payment complete" : "Payment failed"}</span>
      <h1>${status === "success" ? "Your payment was verified" : "Your payment could not be verified"}</h1>
      <p>${message}</p>
    </div>
  </body>
</html>`,
    { headers: { "Content-Type": "text/html; charset=utf-8" } },
  );
}

Deno.serve(async (request) => {
  // Handle both GET (browser redirect) and POST (webhook)
  const url = new URL(request.url);
  let orderId = "";
  let transactionId = "";
  let status = "failed";
  let message = "Payment was not completed.";
  let cardLast4 = "";
  let cardBrand = "";

  if (request.method === "GET") {
    // Browser redirect from payment page (query params)
    orderId = url.searchParams.get("order_id") ?? "";
    transactionId = url.searchParams.get("transaction_id") ?? "";
    status = (url.searchParams.get("status") ?? "failed").toLowerCase();
    message = url.searchParams.get("message") ?? "Payment was not completed.";
    cardLast4 = url.searchParams.get("card_last4") ?? "";
    cardBrand = url.searchParams.get("card_brand") ?? "";
  } else if (request.method === "POST") {
    // Webhook callback from NCB
    try {
      const body = await request.json() as Record<string, unknown>;
      orderId = String(body.order_id ?? body.orderId ?? "").trim();
      transactionId = String(body.transaction_id ?? body.transactionId ?? body.reference ?? "").trim();
      status = String(body.status ?? "failed").toLowerCase();
      message = String(body.message ?? "Payment was not completed.");
      cardLast4 = String(body.card_last4 ?? body.cardLast4 ?? "").trim();
      cardBrand = String(body.card_brand ?? body.cardBrand ?? "").trim();
    } catch {
      return html("failed", "Invalid callback data.");
    }
  } else if (request.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  if (!orderId) {
    return html("failed", "Missing order reference.");
  }

  // Verify order exists
  const { data: order } = await adminClient
    .from("orders")
    .select("id, total_amount")
    .eq("id", orderId)
    .maybeSingle();

  if (!order) {
    return html("failed", "Order could not be found.");
  }

  const verified = status === "success" && transactionId.length > 0;

  // Update payments table
  await adminClient
    .from("payments")
    .update({
      transaction_id: transactionId || null,
      status: verified ? "completed" : "failed",
      error_message: verified ? null : message,
      updated_at: new Date().toISOString(),
    })
    .eq("order_id", orderId);

  // Update orders table
  await adminClient
    .from("orders")
    .update({
      payment_status: verified ? "completed" : "failed",
      updated_at: new Date().toISOString(),
    })
    .eq("id", orderId);

  // Save card for future use if payment succeeded and card info provided
  if (verified && cardLast4.length >= 2) {
    // Get user_id from the order
    const { data: orderUser } = await adminClient
      .from("orders")
      .select("user_id")
      .eq("id", orderId)
      .maybeSingle();

    if (orderUser?.user_id) {
      const userId = orderUser.user_id;
      const brand = (cardBrand || "visa").toLowerCase();

      // Check if card already saved
      const { data: existing } = await adminClient
        .from("saved_cards")
        .select("id")
        .eq("user_id", userId)
        .eq("last_four", cardLast4)
        .eq("card_brand", brand)
        .maybeSingle();

      if (!existing) {
        // Get payment record for customer details
        const { data: payment } = await adminClient
          .from("payments")
          .select("id")
          .eq("order_id", orderId)
          .maybeSingle();

        // Get user info for cardholder details
        const { data: user } = await adminClient
          .from("users")
          .select("name, email, phone")
          .eq("id", userId)
          .maybeSingle();

        // Check if user has any saved cards (first card = default)
        const { data: existingCards } = await adminClient
          .from("saved_cards")
          .select("id")
          .eq("user_id", userId);

        const isFirst = !existingCards || existingCards.length === 0;

        await adminClient.from("saved_cards").insert({
          user_id: userId,
          card_brand: brand,
          last_four: cardLast4,
          cardholder_name: user?.name ?? "Card Holder",
          email: user?.email ?? "",
          phone: user?.phone ?? "",
          is_default: isFirst,
        });
      }
    }
  }

  if (verified) {
    return html("success", "You can return to the app now.");
  }

  return html("failed", message);
});

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import md5 from "https://esm.sh/blueimp-md5@2.19.0";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const wipayApiKey = Deno.env.get("WIPAY_API_KEY") ?? "";

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
    {
      headers: {
        "Content-Type": "text/html; charset=utf-8",
      },
    },
  );
}

Deno.serve(async (request) => {
  const url = new URL(request.url);
  const params = url.searchParams;

  const orderId = params.get("order_id") ?? "";
  const transactionId = params.get("transaction_id") ?? "";
  const status = (params.get("status") ?? "failed").toLowerCase();
  const message = params.get("message") ?? "Payment was not completed.";
  const responseHash = params.get("hash") ?? "";

  if (!orderId) {
    return html("failed", "Missing order reference.");
  }

  const { data: order } = await adminClient
    .from("orders")
    .select("id, total_amount")
    .eq("id", orderId)
    .maybeSingle();

  if (!order) {
    return html("failed", "Order could not be found.");
  }

  const originalTotal = Number(order.total_amount ?? 0).toFixed(2);
  const verified =
    status === "success" &&
    transactionId.length > 0 &&
    responseHash.length > 0 &&
    md5(`${transactionId}${originalTotal}${wipayApiKey}`) === responseHash;

  await adminClient
    .from("payments")
    .update({
      transaction_id: transactionId || null,
      status: verified ? "completed" : "failed",
      error_message: verified ? null : message,
      updated_at: new Date().toISOString(),
    })
    .eq("order_id", orderId);

  await adminClient
    .from("orders")
    .update({
      payment_status: verified ? "completed" : "failed",
      updated_at: new Date().toISOString(),
    })
    .eq("id", orderId);

  if (verified) {
    return html("success", "You can return to the app now.");
  }

  return html("failed", message);
});
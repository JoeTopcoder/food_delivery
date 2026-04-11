// NCB Payment Initiation Edge Function
// Supports both test and real NCB integration using NCB_TEST_MODE env variable

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const NCB_API_KEY = Deno.env.get("NCB_API_KEY") ?? "test_ncb_api_key";
const NCB_API_URL = Deno.env.get("NCB_API_URL") ?? "https://sandbox.ncb.com/api/payments";
const NCB_TEST_MODE = Deno.env.get("NCB_TEST_MODE") ?? "true";
const callbackUrl = Deno.env.get("NCB_CALLBACK_URL") ?? `${supabaseUrl}/functions/v1/ncb-payment-callback`;

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // GET: Serve test card payment form
  if (request.method === "GET") {
    const url = new URL(request.url);
    const orderId = url.searchParams.get("order_id") ?? "";
    const ref = url.searchParams.get("ref") ?? "";
    const amt = url.searchParams.get("amount") ?? "0.00";
    const cb = url.searchParams.get("callback") ?? callbackUrl;

    if (!orderId) {
      return new Response("Missing order_id", { status: 400 });
    }

    const successUrl = `${cb}?order_id=${encodeURIComponent(orderId)}&transaction_id=${encodeURIComponent(ref)}&status=success&message=Payment+successful`;
    const failUrl = `${cb}?order_id=${encodeURIComponent(orderId)}&transaction_id=${encodeURIComponent(ref)}&status=failed&message=Payment+cancelled`;

    return new Response(
      `<!doctype html>
<html>
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1"/>
  <title>NCB Test Payment</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    body{font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;background:#f0f2f5;min-height:100vh;display:flex;align-items:center;justify-content:center;padding:16px}
    .card{background:#fff;border-radius:16px;box-shadow:0 8px 32px rgba(0,0,0,.1);width:min(400px,100%);overflow:hidden}
    .header{background:linear-gradient(135deg,#1a5c2e,#2d8e47);color:#fff;padding:24px;text-align:center}
    .header h1{font-size:20px;margin-bottom:4px}
    .header .amount{font-size:32px;font-weight:700;margin-top:8px}
    .header .badge{display:inline-block;background:rgba(255,255,255,.2);padding:4px 12px;border-radius:20px;font-size:12px;margin-top:8px}
    .body{padding:24px}
    .field{margin-bottom:16px}
    .field label{display:block;font-size:13px;font-weight:600;color:#555;margin-bottom:6px}
    .field input{width:100%;padding:12px;border:1.5px solid #ddd;border-radius:10px;font-size:16px;outline:none;transition:border .2s}
    .field input:focus{border-color:#2d8e47}
    .row{display:flex;gap:12px}
    .row .field{flex:1}
    .btn{width:100%;padding:14px;border:none;border-radius:12px;font-size:16px;font-weight:600;cursor:pointer;transition:opacity .2s}
    .btn:active{opacity:.8}
    .btn-pay{background:#2d8e47;color:#fff;margin-bottom:10px}
    .btn-cancel{background:#f5f5f5;color:#666}
    .secure{text-align:center;margin-top:16px;font-size:12px;color:#999}
    .secure span{color:#2d8e47}
  </style>
</head>
<body>
  <div class="card">
    <div class="header">
      <h1>NCB Payment Gateway</h1>
      <div class="badge">TEST MODE</div>
      <div class="amount">J$${amt}</div>
    </div>
    <div class="body">
      <div class="field">
        <label>Card Number</label>
        <input id="cardNum" type="text" inputmode="numeric" placeholder="4111 1111 1111 1111" maxlength="19" value="4111 1111 1111 1111"/>
      </div>
      <div class="row">
        <div class="field">
          <label>Expiry</label>
          <input type="text" placeholder="MM/YY" maxlength="5" value="12/28"/>
        </div>
        <div class="field">
          <label>CVV</label>
          <input type="text" inputmode="numeric" placeholder="123" maxlength="4" value="123"/>
        </div>
      </div>
      <div class="field">
        <label>Cardholder Name</label>
        <input type="text" placeholder="Full name on card" value="Test User"/>
      </div>
      <button class="btn btn-pay" onclick="pay()">Pay J$${amt}</button>
      <button class="btn btn-cancel" onclick="cancel()">Cancel</button>
      <div class="secure">🔒 Secured by <span>NCB</span> · Test Environment</div>
    </div>
  </div>
  <script>
    function pay(){
      var cn=document.getElementById('cardNum').value.replace(/\\s/g,'');
      if(cn.length<13){alert('Enter a valid card number');return;}
      document.querySelector('.btn-pay').textContent='Processing...';
      document.querySelector('.btn-pay').disabled=true;
      setTimeout(function(){window.location.href="${successUrl}";},1500);
    }
    function cancel(){window.location.href="${failUrl}";}
  </script>
</body>
</html>`,
      { headers: { "Content-Type": "text/html; charset=utf-8" } },
    );
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  // Verify authorization
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing authorization header." }, 401);
  }

  const userClient = createClient(supabaseUrl, supabaseAnonKey, {
    global: { headers: { Authorization: authHeader } },
  });
  const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    return json({ error: "Unauthorized" }, 401);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const orderId = String(body.orderId ?? "").trim();
  const amount = Number(body.amount ?? 0);
  const email = String(body.email ?? "").trim();
  const phone = String(body.phone ?? "").trim();
  const name = String(body.name ?? "").trim();

  if (!orderId || !amount || !email || !name) {
    return json({ error: "Missing required payment fields (orderId, amount, email, name)." }, 400);
  }

  // Validate order exists and belongs to user
  const { data: order, error: orderError } = await adminClient
    .from("orders")
    .select("id, user_id, total_amount, payment_status")
    .eq("id", orderId)
    .single();

  if (orderError || !order) {
    return json({ error: "Order not found." }, 404);
  }

  if (order.user_id !== userData.user.id) {
    return json({ error: "You do not own this order." }, 403);
  }

  const requestAmount = Number(order.total_amount ?? amount).toFixed(2);

  // Build payment payload for NCB
  const paymentPayload = {
    amount: requestAmount,
    currency: "JMD",
    customer: { name, email, phone },
    description: `FoodDriver Order ${orderId}`,
    order_id: orderId,
    callback_url: callbackUrl,
  };

  // TEST MODE: Return a simulated payment page URL
  if (NCB_TEST_MODE === "true") {
    const testRef = `NCB-TEST-${orderId.slice(0, 8)}-${Date.now()}`;

    // Create pending payment record
    await adminClient.from("payments").upsert(
      {
        order_id: orderId,
        user_id: userData.user.id,
        amount: Number(requestAmount),
        method: "card",
        status: "pending",
        transaction_id: testRef,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "order_id" },
    );

    // In test mode, show a test card entry form that then redirects to callback
    const testPaymentUrl = `${supabaseUrl}/functions/v1/ncb-initiate-payment?order_id=${encodeURIComponent(orderId)}&ref=${encodeURIComponent(testRef)}&amount=${encodeURIComponent(requestAmount)}&callback=${encodeURIComponent(callbackUrl)}`;

    return json({
      status: "success",
      payment_url: testPaymentUrl,
      reference: testRef,
      callbackUrl,
    });
  }

  // REAL MODE: Call NCB API
  try {
    const ncbRes = await fetch(NCB_API_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${NCB_API_KEY}`,
      },
      body: JSON.stringify(paymentPayload),
    });
    const ncbData = await ncbRes.json() as Record<string, unknown>;

    const paymentUrl = String(ncbData.payment_url ?? ncbData.url ?? "");
    const reference = String(ncbData.reference ?? ncbData.id ?? "");

    if (!paymentUrl) {
      return json({ error: "NCB did not return a payment URL." }, 502);
    }

    // Create pending payment record
    await adminClient.from("payments").upsert(
      {
        order_id: orderId,
        user_id: userData.user.id,
        amount: Number(requestAmount),
        method: "card",
        status: "pending",
        transaction_id: reference,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "order_id" },
    );

    return json({
      status: "success",
      payment_url: paymentUrl,
      reference,
      callbackUrl,
    });
  } catch (err) {
    return json({ error: "NCB API error", details: `${err}` }, 500);
  }
});

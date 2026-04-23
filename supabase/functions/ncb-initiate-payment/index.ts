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
    const cardholderName = url.searchParams.get("name") ?? "";
    const isVerify = orderId.startsWith("verify-card-");
    const mode = url.searchParams.get("mode") ?? "";

    if (!orderId) {
      return new Response("Missing order_id", { status: 400 });
    }

    // ── Saved card confirmation page ────────────────────────────
    if (mode === "saved_card") {
      const cardLast4 = url.searchParams.get("card_last4") ?? "****";
      const cardBrand = (url.searchParams.get("card_brand") ?? "visa").toUpperCase();
      const cardName = url.searchParams.get("card_name") ?? "";

      const successUrl = `${cb}?order_id=${encodeURIComponent(orderId)}&transaction_id=${encodeURIComponent(ref)}&status=success&message=Payment+successful&card_last4=${encodeURIComponent(cardLast4)}&card_brand=${encodeURIComponent(cardBrand.toLowerCase())}&cardholder_name=${encodeURIComponent(cardName)}`;
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
    .card-info{background:#f8f9fa;border-radius:12px;padding:16px;margin-bottom:20px;display:flex;align-items:center;gap:12px}
    .card-icon{width:48px;height:32px;background:#1a1f71;border-radius:6px;display:flex;align-items:center;justify-content:center;color:#fff;font-size:11px;font-weight:800;letter-spacing:1px}
    .card-details{flex:1}
    .card-details .masked{font-size:16px;font-weight:600;color:#333;letter-spacing:1px}
    .card-details .name{font-size:12px;color:#888;margin-top:2px}
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
      <h1>Confirm Payment</h1>
      <div class="badge">TEST MODE</div>
      <div class="amount">J$${amt}</div>
    </div>
    <div class="body">
      <div class="card-info">
        <div class="card-icon">${cardBrand}</div>
        <div class="card-details">
          <div class="masked">•••• •••• •••• ${cardLast4}</div>
          <div class="name">${cardName}</div>
        </div>
      </div>
      <button class="btn btn-pay" id="payBtn" onclick="pay()">Pay J$${amt}</button>
      <button class="btn btn-cancel" onclick="cancel()">Cancel</button>
      <div class="secure">🔒 Secured by <span>NCB</span> · Test Environment</div>
    </div>
  </div>
  <script>
    function pay(){
      var btn=document.getElementById('payBtn');
      btn.textContent='Processing...';
      btn.disabled=true;
      setTimeout(function(){window.location.href="${successUrl}";},1200);
    }
    function cancel(){window.location.href="${failUrl}";}
  </script>
</body>
</html>`,
        { headers: { "Content-Type": "text/html; charset=utf-8" } },
      );
    }

    // For card verification, hide the amount — user must check their bank statement
    const displayAmount = isVerify ? "***" : `J$${amt}`;
    const headerTitle = isVerify ? "Card Verification" : "NCB Payment Gateway";
    const payBtnText = isVerify ? "Authorize Card" : `Pay J$${amt}`;

    // Card details passed from the app (for pre-filling the form)
    const prefillCardNum = url.searchParams.get("cn") ?? "";
    const prefillExpiry = url.searchParams.get("ce") ?? "";
    const prefillCvv = url.searchParams.get("cc") ?? "";
    const hasAllCardDetails = prefillCardNum.length >= 13 && prefillExpiry.length >= 4 && prefillCvv.length >= 3;

    // Format card number for display (add spaces every 4 digits)
    const formattedCardNum = prefillCardNum.replace(/(\d{4})(?=\d)/g, "$1 ");

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
      <h1>${headerTitle}</h1>
      <div class="badge">TEST MODE</div>
      <div class="amount">${displayAmount}</div>
    </div>
    <div class="body">
      <div class="field">
        <label>Card Number</label>
        <input id="cardNum" type="text" inputmode="numeric" placeholder="4111 1111 1111 1111" maxlength="19" value="${formattedCardNum}" ${hasAllCardDetails ? "readonly" : ""} oninput="formatCard(this)"/>
      </div>
      <div class="row">
        <div class="field">
          <label>Expiry</label>
          <input id="expiry" type="text" placeholder="MM/YY" maxlength="5" value="${prefillExpiry}" ${hasAllCardDetails ? "readonly" : ""} oninput="formatExpiry(this)"/>
        </div>
        <div class="field">
          <label>CVV</label>
          <input id="cvvField" type="text" inputmode="numeric" placeholder="123" maxlength="4" value="${prefillCvv}" ${hasAllCardDetails ? "readonly" : ""}/>
        </div>
      </div>
      <div class="field">
        <label>Cardholder Name</label>
        <input id="cardName" type="text" placeholder="Full name on card" value="${cardholderName}" ${hasAllCardDetails ? "readonly" : ""} style="text-transform:uppercase"/>
      </div>
      <button class="btn btn-pay" id="payBtn" onclick="pay()">${payBtnText}</button>
      <button class="btn btn-cancel" onclick="cancel()">Cancel</button>
      <div class="secure">🔒 Secured by <span>NCB</span> · Test Environment</div>
    </div>
  </div>
  <script>
    function formatCard(el){
      var v=el.value.replace(/\\D/g,'').substring(0,16);
      el.value=v.replace(/(\\d{4})(?=\\d)/g,'$1 ');
    }
    function formatExpiry(el){
      var v=el.value.replace(/\\D/g,'').substring(0,4);
      if(v.length>=3) v=v.substring(0,2)+'/'+v.substring(2);
      el.value=v;
    }
    function pay(){
      var cn=document.getElementById('cardNum').value.replace(/\\s/g,'');
      if(cn.length<13){alert('Enter a valid card number');return;}
      var last4=cn.substring(cn.length-4);
      var brand='visa';
      if(cn.startsWith('5')||cn.startsWith('2'))brand='mastercard';
      else if(cn.startsWith('3'))brand='keycard';
      var cname=document.getElementById('cardName').value.trim();
      var btn=document.getElementById('payBtn');
      btn.textContent='Processing...';
      btn.disabled=true;
      setTimeout(function(){window.location.href="${successUrl}&card_last4="+last4+"&card_brand="+brand+"&cardholder_name="+encodeURIComponent(cname);},1500);
    }
    function cancel(){window.location.href="${failUrl}";}
    ${hasAllCardDetails ? "window.addEventListener('load',function(){pay();});" : ""}
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

const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey);

const _token = authHeader.replace(/^Bearer\s+/i, "");
let _uid: string;
try {
  const _p = JSON.parse(atob(_token.split(".")[1]));
  _uid = _p.sub as string;
  if (!_uid) throw new Error();
} catch { return json({ error: "Invalid token." }, 401); }
const { data: _ur, error: _ue } = await adminClient.from("users").select("id").eq("id", _uid).maybeSingle();
if (_ue || !_ur) return json({ error: "Unauthorized" }, 401);
const userData = { user: { id: _uid } };

let body: any;
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
  const txnType = String(body.type ?? "order").trim(); // order | verify_card | wallet_topup
  const savedCardId = String(body.savedCardId ?? "").trim();
  const cvv = String(body.cvv ?? "").trim();
  const cardNumber = String(body.cardNumber ?? "").trim();
  const cardExpiry = String(body.cardExpiry ?? "").trim();
  const cardCvv = String(body.cardCvv ?? "").trim();

  if (!orderId || !amount || !email || !name) {
    return json({ error: "Missing required payment fields (orderId, amount, email, name)." }, 400);
  }

  const isNonOrder = txnType === "verify_card" || txnType === "wallet_topup";

  // For card verification / wallet top-up, skip order validation
  let requestAmount = amount.toFixed(2);

  if (!isNonOrder) {
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

    requestAmount = Number(order.total_amount ?? amount).toFixed(2);
  } else if (txnType === "verify_card") {
    // Card verification: create a record in card_verifications with cardholder details
    await adminClient.from("card_verifications").insert({
      id: orderId,
      user_id: userData.user.id,
      amount: Number(requestAmount),
      status: "pending",
      cardholder_name: name || null,
      email: email || null,
      phone: phone || null,
    });
  }

  // Build payment payload for NCB
  const description = txnType === "verify_card"
    ? `Card Verification $${requestAmount}`
    : txnType === "wallet_topup"
    ? `Wallet Top-up $${requestAmount}`
    : `MealHub Order ${orderId}`;

  const paymentPayload = {
    amount: requestAmount,
    currency: "JMD",
    customer: { name, email, phone },
    description,
    order_id: orderId,
    callback_url: callbackUrl,
  };

  // TEST MODE: Return a simulated payment page URL
  if (NCB_TEST_MODE === "true") {
    const testRef = `NCB-TEST-${orderId.slice(0, 8)}-${Date.now()}`;

    // ── Saved card payment (skip card entry form) ──────────────────
    if (savedCardId && cvv) {
      // Look up saved card to get last4 and brand
      const { data: savedCard } = await adminClient
        .from("saved_cards")
        .select("last_four, card_brand, cardholder_name, status")
        .eq("id", savedCardId)
        .maybeSingle();

      if (!savedCard || savedCard.status !== "verified") {
        return json({ error: "Saved card not found or not verified." }, 400);
      }

      // Create pending payment record for orders
      if (!isNonOrder) {
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
      }

      const cardLast4 = savedCard.last_four;
      const cardBrand = savedCard.card_brand;
      const cardName = savedCard.cardholder_name || name;

      // In test mode, show a simple confirmation page instead of card entry
      const confirmSuccessUrl = `${callbackUrl}?order_id=${encodeURIComponent(orderId)}&transaction_id=${encodeURIComponent(testRef)}&status=success&message=Payment+successful&card_last4=${encodeURIComponent(cardLast4)}&card_brand=${encodeURIComponent(cardBrand)}&cardholder_name=${encodeURIComponent(cardName)}`;
      const confirmFailUrl = `${callbackUrl}?order_id=${encodeURIComponent(orderId)}&transaction_id=${encodeURIComponent(testRef)}&status=failed&message=Payment+cancelled`;

      const savedCardPageUrl = `${supabaseUrl}/functions/v1/ncb-initiate-payment?mode=saved_card&order_id=${encodeURIComponent(orderId)}&ref=${encodeURIComponent(testRef)}&amount=${encodeURIComponent(requestAmount)}&callback=${encodeURIComponent(callbackUrl)}&card_last4=${encodeURIComponent(cardLast4)}&card_brand=${encodeURIComponent(cardBrand)}&card_name=${encodeURIComponent(cardName)}`;

      return json({
        status: "success",
        payment_url: savedCardPageUrl,
        reference: testRef,
        callbackUrl,
      });
    }

    // Create pending payment record (only for real orders)
    if (!isNonOrder) {
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
    } else if (txnType === "verify_card") {
      await adminClient.from("card_verifications").update({
        transaction_id: testRef,
        updated_at: new Date().toISOString(),
      }).eq("id", orderId);
    }

    // In test mode, show a test card entry form that then redirects to callback
    const testPaymentUrl = `${supabaseUrl}/functions/v1/ncb-initiate-payment?order_id=${encodeURIComponent(orderId)}&ref=${encodeURIComponent(testRef)}&amount=${encodeURIComponent(requestAmount)}&callback=${encodeURIComponent(callbackUrl)}&name=${encodeURIComponent(name)}${cardNumber ? `&cn=${encodeURIComponent(cardNumber)}&ce=${encodeURIComponent(cardExpiry)}&cc=${encodeURIComponent(cardCvv)}` : ""}`;

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

    // Create pending payment record (only for real orders)
    if (!isNonOrder) {
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
    } else if (txnType === "verify_card") {
      await adminClient.from("card_verifications").update({
        transaction_id: reference,
        updated_at: new Date().toISOString(),
      }).eq("id", orderId);
    }

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

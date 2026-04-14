import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const wipayApiKey = Deno.env.get("WIPAY_API_KEY") ?? "";
const wipayAccountNumber = Deno.env.get("WIPAY_ACCOUNT_NUMBER") ?? "";
const wipayCountryCode = Deno.env.get("WIPAY_COUNTRY_CODE") ?? "TT";
const wipayCurrency = Deno.env.get("WIPAY_CURRENCY") ?? "TTD";
const wipayEnvironment = Deno.env.get("WIPAY_ENVIRONMENT") ?? "live";
const wipayFeeStructure = Deno.env.get("WIPAY_FEE_STRUCTURE") ?? "customer_pay";
const wipayOrigin = Deno.env.get("WIPAY_ORIGIN") ?? "MealHub";
const callbackUrl = Deno.env.get("WIPAY_CALLBACK_URL") ?? `${supabaseUrl}/functions/v1/wipay-payment-callback`;
const countryHost =
  wipayEnvironment === "sandbox"
    ? `${wipayCountryCode.toLowerCase()}sb`
    : wipayCountryCode.toLowerCase();

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!wipayApiKey || !wipayAccountNumber) {
    return json({ error: "WiPay secrets are not configured on the server." }, 500);
  }

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

  const body = await request.json();
  const orderId = String(body.orderId ?? "").trim();
  const amount = Number(body.amount ?? 0);
  const email = String(body.email ?? "").trim();
  const phone = String(body.phone ?? "").trim();
  const name = String(body.name ?? "").trim();
  const billingAddress = String(body.billingAddress ?? "").trim();

  if (!orderId || !amount || !email || !phone || !name) {
    return json({ error: "Missing required payment fields." }, 400);
  }

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

  const formData = new URLSearchParams();
  formData.set("account_number", wipayAccountNumber);
  formData.set("country_code", wipayCountryCode);
  formData.set("currency", wipayCurrency);
  formData.set("environment", wipayEnvironment);
  formData.set("fee_structure", wipayFeeStructure);
  formData.set("method", "credit_card_co");
  formData.set("order_id", orderId);
  formData.set("origin", wipayOrigin);
  formData.set("response_url", callbackUrl);
  formData.set("total", requestAmount);
  formData.set("email", email);
  formData.set("name", name);
  formData.set("phone", phone);
  formData.set(
    "data",
    JSON.stringify({
      order_id: orderId,
      user_id: userData.user.id,
    }),
  );

  if (billingAddress) {
    formData.set("addr1", billingAddress.slice(0, 50));
  }

  const endpoint = `https://${countryHost}.wipayfinancial.com/plugins/payments/request`;
  const wipayResponse = await fetch(endpoint, {
    method: "POST",
    headers: {
      Accept: "application/json",
      "Content-Type": "application/x-www-form-urlencoded",
    },
    body: formData,
  });

  const result = await wipayResponse.json();
  if (!wipayResponse.ok || !result?.url || !result?.transaction_id) {
    return json({ error: result?.message ?? "WiPay session creation failed." }, 400);
  }

  await adminClient.from("payments").upsert(
    {
      order_id: orderId,
      user_id: userData.user.id,
      amount,
      method: "card",
      status: "pending",
      transaction_id: String(result.transaction_id),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "order_id" },
  );

  return json({
    checkoutUrl: String(result.url),
    transactionId: String(result.transaction_id),
    callbackUrl,
  });
});
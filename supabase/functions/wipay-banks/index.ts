// @ts-nocheck

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const wipayWapiKey = Deno.env.get("WIPAY_WAPI_KEY") ?? "";
const wipayCountryCode = Deno.env.get("WIPAY_COUNTRY_CODE") ?? "JM";
const wipayEnvironment = Deno.env.get("WIPAY_ENVIRONMENT") ?? "live";
const wipayAccountNumber = Deno.env.get("WIPAY_ACCOUNT_NUMBER") ?? "";

const baseUrl =
  wipayEnvironment === "sandbox"
    ? `https://${wipayCountryCode.toLowerCase()}sb.wipayfinancial.com`
    : `https://${wipayCountryCode.toLowerCase()}.wipayfinancial.com`;

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (!wipayWapiKey) {
    return json({ error: "WiPay WAPI Key is not configured." }, 500);
  }

  const results: Record<string, unknown> = {};

  // Probe transfer/send endpoints (WiPay Me / send money)
  const probeEndpoints = [
    { url: "/wapi/transfers", method: "GET" },
    { url: "/wapi/transfers", method: "POST" },
    { url: "/wapi/send", method: "GET" },
    { url: "/wapi/send", method: "POST" },
    { url: "/wapi/wipay-me", method: "GET" },
    { url: "/wapi/wipay-me", method: "POST" },
    { url: "/wapi/payout", method: "GET" },
    { url: "/wapi/payout", method: "POST" },
    { url: "/wapi/payouts", method: "GET" },
    { url: "/wapi/payouts", method: "POST" },
    { url: "/wapi/disburse", method: "GET" },
    { url: "/wapi/disburse", method: "POST" },
    { url: "/wapi/disbursements", method: "GET" },
    { url: "/wapi/disbursements", method: "POST" },
    { url: "/wapi/balance", method: "GET" },
    { url: "/wapi/account", method: "GET" },
    { url: "/wapi/profile", method: "GET" },
    { url: "/wapi/withdrawals/types", method: "GET" },
    { url: "/wapi/withdrawals/methods", method: "GET" },
  ];

  for (const ep of probeEndpoints) {
    try {
      const opts: RequestInit = {
        method: ep.method,
        headers: { Accept: "application/json", "Content-Type": "application/json", "X-WAPI-Key": wipayWapiKey },
      };
      if (ep.method === "POST") {
        opts.body = JSON.stringify({
          email: "scottjoelwork@gmail.com",
          amount: 100,
          currency: "JMD",
          order_id: `probe-${Date.now()}`,
          note: "test",
        });
      }
      const r = await fetch(`${baseUrl}${ep.url}`, opts);
      let body;
      try { body = await r.json(); } catch { body = await r.text(); }
      results[`${ep.method}_${ep.url}`] = { status: r.status, body };
    } catch (e) {
      results[`${ep.method}_${ep.url}`] = { error: (e as Error).message };
    }
  }

  return json(results);
});

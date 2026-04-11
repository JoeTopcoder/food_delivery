// NCB Payout Processing Edge Function
// Supports both test and real NCB integration using NCB_TEST_MODE env variable

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

const payoutCorsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const NCB_API_KEY = Deno.env.get("NCB_API_KEY") ?? "test_ncb_api_key";
const NCB_PAYOUT_URL = Deno.env.get("NCB_PAYOUT_URL") ?? "https://sandbox.ncb.com/api/payouts";
const NCB_TEST_MODE = Deno.env.get("NCB_TEST_MODE") ?? "true";

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...payoutCorsHeaders, "Content-Type": "application/json" },
  });
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: payoutCorsHeaders });
  }

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown> = {};
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  // Build payout payload
  const payoutPayload = {
    amount: body.amount ?? 1000,
    currency: body.currency ?? "JMD",
    recipient: {
      name: body.name ?? "Test User",
      bank_account: body.bank_account ?? "0001234567",
      bank_name: body.bank_name ?? "National Commercial Bank",
    },
    description: body.description ?? "Test payout",
  };

  // TEST MODE: Return fake payout reference
  if (NCB_TEST_MODE === "true") {
    return json({
      status: "success",
      payout_reference: `NCB-TEST-PAYOUT-${Date.now()}`,
      debug: {
        sent: payoutPayload,
        test_mode: true,
      },
    });
  }

  // REAL MODE: Make real HTTP request to NCB API
  try {
    const ncbRes = await fetch(NCB_PAYOUT_URL, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${NCB_API_KEY}`,
      },
      body: JSON.stringify(payoutPayload),
    });
    const ncbData = await ncbRes.json() as Record<string, unknown>;

    return json({
      status: (ncbData.status as string) ?? "unknown",
      payout_reference: (ncbData.payout_reference ?? ncbData.reference ?? ncbData.id ?? null) as string | null,
      debug: {
        sent: payoutPayload,
        test_mode: false,
        ncb_raw: ncbData,
      },
    });
  } catch (err) {
    return json({ error: "NCB API error", details: `${err}` }, 500);
  }
});

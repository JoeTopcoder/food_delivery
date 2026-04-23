// @ts-nocheck
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const wipayWapiKey = Deno.env.get("WIPAY_WAPI_KEY") ?? "";
const wipayCountryCode = Deno.env.get("WIPAY_COUNTRY_CODE") ?? "JM";
const wipayCurrency = Deno.env.get("WIPAY_CURRENCY") ?? "JMD";
const wipayEnvironment = Deno.env.get("WIPAY_ENVIRONMENT") ?? "live";

const baseUrl =
  wipayEnvironment === "sandbox"
    ? `https://${wipayCountryCode.toLowerCase()}sb.wipayfinancial.com`
    : `https://${wipayCountryCode.toLowerCase()}.wipayfinancial.com`;

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

  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  if (!wipayWapiKey) {
    return json(
      { error: "WiPay WAPI Key is not configured. Use 'Mark Complete' for manual payouts." },
      500
    );
  }

  // ── Verify caller is an admin ─────────────────────────────────────────────
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return json({ error: "Missing authorization header." }, 401);
  }

const token = authHeader.replace(/^Bearer\s+/i, "");
let _userId: string;
try {
  const payloadB64 = token.split(".")[1];
  const payload = JSON.parse(atob(payloadB64));
  _userId = payload.sub as string;
  if (!_userId) throw new Error("No sub");
} catch {
  return json({ error: "Invalid token." }, 401);
}
const { data: _userRow2, error: _userErr2 } = await adminClient
  .from("users").select("id").eq("id", _userId).maybeSingle();
if (_userErr2 || !_userRow2) return json({ error: "Unauthorized" }, 401);
const userData = { user: { id: _userId } };
  const { data: callerUser } = await adminClient
    .from("users")
    .select("role")
    .eq("id", userData.user.id)
    .single();

  if (!callerUser || callerUser.role !== "admin") {
    return json({ error: "Only admins can process payouts." }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const payoutId = String(body.payoutId ?? "").trim();
  if (!payoutId) {
    return json({ error: "Missing payoutId" }, 400);
  }

  // ── Fetch payout request ──────────────────────────────────────────────────
  const { data: payout, error: payoutError } = await adminClient
    .from("payout_requests")
    .select("*")
    .eq("id", payoutId)
    .single();

  if (payoutError || !payout) {
    return json({ error: "Payout request not found." }, 404);
  }

  if (payout.status !== "approved") {
    return json(
      { error: `Payout must be approved first. Current status: ${payout.status}` },
      400
    );
  }

  // ── Resolve requester details (required by WiPay) ───────────────────────
  let requesterEmail = "";
  let requesterPhone = "";
  let requesterName = "";
  if (payout.requester_type === "driver" && payout.driver_id) {
    const { data: driver } = await adminClient
      .from("drivers")
      .select("user_id")
      .eq("id", payout.driver_id)
      .single();
    if (driver?.user_id) {
      const { data: user } = await adminClient
        .from("users")
        .select("email, phone, name")
        .eq("id", driver.user_id)
        .single();
      requesterEmail = user?.email ?? "";
      requesterPhone = user?.phone ?? "";
      requesterName = user?.name ?? "";
    }
  } else if (payout.requester_type === "restaurant" && payout.restaurant_id) {
    const { data: rest } = await adminClient
      .from("restaurants")
      .select("email, phone, name, owner_id")
      .eq("id", payout.restaurant_id)
      .single();
    requesterEmail = rest?.email ?? "";
    requesterPhone = rest?.phone ?? "";
    requesterName = rest?.name ?? "";
    // Fallback: if restaurant has no email/phone, get from owner
    if (!requesterEmail || !requesterPhone) {
      const { data: owner } = await adminClient
        .from("users")
        .select("email, phone, name")
        .eq("id", rest?.owner_id)
        .single();
      if (!requesterEmail) requesterEmail = owner?.email ?? "";
      if (!requesterPhone) requesterPhone = owner?.phone ?? "";
      if (!requesterName) requesterName = owner?.name ?? "";
    }
  }

  // Split name into first/last
  const nameParts = (requesterName || "N/A").trim().split(/\s+/);
  const firstName = nameParts[0] || "N/A";
  const lastName = nameParts.length > 1 ? nameParts.slice(1).join(" ") : firstName;

  if (!requesterEmail) {
    return json({ error: "Could not resolve email for the payout requester." }, 400);
  }
  if (!requesterPhone) {
    return json({ error: "Could not resolve phone for the payout requester." }, 400);
  }

  // Normalize phone to E.164 format
  let phone = requesterPhone.replace(/[\s\-\(\)]/g, "");
  if (!phone.startsWith("+")) {
    // Assume Jamaica (+1876) if country code is JM, otherwise prepend +
    if (wipayCountryCode === "JM") {
      if (phone.startsWith("876")) {
        phone = "+1" + phone;
      } else if (phone.startsWith("1876")) {
        phone = "+" + phone;
      } else {
        phone = "+1876" + phone;
      }
    } else {
      phone = "+" + phone;
    }
  }

  // ── Normalize bank name for WiPay ──────────────────────────────────────
  const bankNameMap: Record<string, string> = {
    "ncb": "National Commercial Bank",
    "scotiabank": "Scotiabank Jamaica",
    "scotia": "Scotiabank Jamaica",
    "jmmb": "JMMB Bank",
    "sagicor": "Sagicor Bank Jamaica",
    "cibc": "CIBC FirstCaribbean",
    "firstcaribbean": "CIBC FirstCaribbean",
    "cibc firstcaribbean": "CIBC FirstCaribbean",
    "bns": "Bank of Nova Scotia Jamaica",
    "jn": "JN Bank",
    "jn bank": "JN Bank",
    "vm": "VM Building Society",
    "vmbs": "VM Building Society",
    "first global": "First Global Bank",
    "fgb": "First Global Bank",
    "mayberry": "Mayberry Investments",
  };
  const rawBankName = (payout.bank_name ?? "").trim();
  const normalizedBankName =
    bankNameMap[rawBankName.toLowerCase()] ?? rawBankName;

  // Normalize branch to Title Case (WiPay requires exact casing)
  const rawBranch = (payout.bank_branch ?? "").trim();
  const normalizedBranch = rawBranch
    .split(/\s+/)
    .map((w: string) => w.charAt(0).toUpperCase() + w.slice(1).toLowerCase())
    .join(" ");

  // ── Mark as processing ────────────────────────────────────────────────────
  await adminClient.from("payout_requests").update({
    status: "processing",
    updated_at: new Date().toISOString(),
  }).eq("id", payoutId);

  // ── Call WiPay WAPI Withdrawals endpoint (sub_banked) ───────────────────
  const endpoint = `${baseUrl}/wapi/withdrawals`;

  const withdrawalBody: Record<string, unknown> = {
    withdrawal_type: "sub_banked",
    currency: wipayCurrency,
    amount: Number(payout.amount),
    first_name: firstName,
    last_name: lastName,
    email: requesterEmail,
    phone: phone,
    bank: normalizedBankName,
    bank_name: normalizedBankName,
    bank_account: payout.bank_account_number ?? "",
    bank_account_number: payout.bank_account_number ?? "",
    account_holder: payout.bank_account_holder ?? "",
    account_type: payout.bank_account_type ?? "savings",
    bank_account_type: payout.bank_account_type ?? "savings",
    order_id: payoutId,
  };
  // Only include bank_branch if provided
  if (normalizedBranch) {
    withdrawalBody.bank_branch = normalizedBranch;
  }

  try {
    const wipayResponse = await fetch(endpoint, {
      method: "POST",
      headers: {
        Accept: "application/json",
        "Content-Type": "application/json",
        "X-WAPI-Key": wipayWapiKey,
      },
      body: JSON.stringify(withdrawalBody),
    });

    const result = await wipayResponse.json();

    if (!wipayResponse.ok || result?.error) {
      // Revert to approved so admin can retry or use Mark Complete
      await adminClient.from("payout_requests").update({
        status: "approved",
        admin_notes: `WiPay error (reverted to approved): ${result?.message ?? result?.error ?? "Unknown error"}`,
        updated_at: new Date().toISOString(),
      }).eq("id", payoutId);

      return json(
        {
          error: result?.message ?? result?.error ?? "WiPay payout failed. Status reverted to approved.",
          debug_sent: withdrawalBody,
          debug_response: result,
        },
        400
      );
    }

    const transactionId = String(
      result?.data?.transaction_id ?? result?.data?.reference ?? ""
    );

    // ── Mark completed & update total_paid_out ──────────────────────────────
    await adminClient.from("payout_requests").update({
      status: "completed",
      wipay_transaction_id: transactionId,
      processed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", payoutId);

    // Update the entity's total_paid_out
    const amount = Number(payout.amount);
    if (payout.requester_type === "driver" && payout.driver_id) {
      const { data: driver } = await adminClient
        .from("drivers")
        .select("total_paid_out")
        .eq("id", payout.driver_id)
        .single();
      const currentPaid = Number(driver?.total_paid_out ?? 0);
      await adminClient
        .from("drivers")
        .update({
          total_paid_out: currentPaid + amount,
          updated_at: new Date().toISOString(),
        })
        .eq("id", payout.driver_id);
    } else if (
      payout.requester_type === "restaurant" &&
      payout.restaurant_id
    ) {
      const { data: rest } = await adminClient
        .from("restaurants")
        .select("total_paid_out")
        .eq("id", payout.restaurant_id)
        .single();
      const currentPaid = Number(rest?.total_paid_out ?? 0);
      await adminClient
        .from("restaurants")
        .update({
          total_paid_out: currentPaid + amount,
          updated_at: new Date().toISOString(),
        })
        .eq("id", payout.restaurant_id);
    }

    return json({
      success: true,
      transactionId,
      message: "Payout processed successfully",
    });
  } catch (err) {
    // Network / unexpected error — revert to approved so admin can retry
    await adminClient.from("payout_requests").update({
      status: "approved",
      admin_notes: `Error (reverted to approved): ${(err as Error).message}`,
      updated_at: new Date().toISOString(),
    }).eq("id", payoutId);

    return json({ error: `${(err as Error).message}. Status reverted to approved.` }, 500);
  }
});

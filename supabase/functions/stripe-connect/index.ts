// @ts-nocheck
// stripe-connect/index.ts  (v2)
// Actions: create_account | update_kyc | add_bank | add_card | status
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
const corsHeaders = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type" };
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const STRIPE_SECRET_KEY = Deno.env.get("STRIPE_SECRET_KEY") ?? "";
const STRIPE_CONNECT_COUNTRY = Deno.env.get("STRIPE_CONNECT_COUNTRY") ?? "US";
function json(body, status = 200) { return new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, "Content-Type": "application/json" } }); }
async function stripePost(endpoint, params) { const res = await fetch(`https://api.stripe.com/v1${endpoint}`, { method: "POST", headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}`, "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams(params).toString() }); return res.json(); }
async function stripeGet(endpoint) { const res = await fetch(`https://api.stripe.com/v1${endpoint}`, { headers: { Authorization: `Bearer ${STRIPE_SECRET_KEY}` } }); return res.json(); }
function stripeErr(r) { const e = r.error; if (!e) return null; return String(e.message ?? "Stripe error"); }
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (!STRIPE_SECRET_KEY) return json({ error: "Stripe not configured" }, 500);
  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing Authorization" }, 401);
const adminClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);
const _token = authHeader.replace(/^Bearer\s+/i, "");
let _uid: string;
try {
  const _p = JSON.parse(atob(_token.split(".")[1]));
  _uid = _p.sub as string;
  if (!_uid) throw new Error();
} catch { return json({ error: "Invalid token." }, 401); }
const { data: _ur, error: _ue } = await adminClient.from("users").select("id, email").eq("id", _uid).maybeSingle();
if (_ue || !_ur) return json({ error: "Unauthorized" }, 401);
const user = { id: _uid, email: _ur.email ?? "" };
  const body = await req.json().catch(() => ({}));
  const action = body.action ?? "status";
  const { data: driver, error: driverErr } = await adminClient.from("drivers").select("id, stripe_account_id, payouts_enabled, charges_enabled, stripe_account_status").eq("user_id", user.id).single();
  if (driverErr || !driver) return json({ error: "Driver record not found" }, 404);

  if (action === "status") {
    const methods = driver.stripe_account_id ? (await adminClient.from("driver_payout_methods").select("*").eq("driver_id", driver.id).order("created_at", { ascending: false })).data ?? [] : [];
    return json({ stripe_account_id: driver.stripe_account_id, stripe_account_status: driver.stripe_account_status, payouts_enabled: driver.payouts_enabled, charges_enabled: driver.charges_enabled, payout_methods: methods });
  }

  if (action === "create_account") {
    if (driver.stripe_account_id) return json({ success: true, stripe_account_id: driver.stripe_account_id, already_exists: true });
    const clientIp = req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "127.0.0.1";
    const { data: profile } = await adminClient.from("user_profiles").select("full_name, email").eq("user_id", user.id).single();
    const acct = await stripePost("/accounts", { type: "custom", country: STRIPE_CONNECT_COUNTRY, email: profile?.email ?? user.email ?? "", "capabilities[transfers][requested]": "true", "capabilities[card_payments][requested]": "true", business_type: "individual", "tos_acceptance[date]": String(Math.floor(Date.now() / 1000)), "tos_acceptance[ip]": clientIp });
    const err = stripeErr(acct);
    if (err) { console.error("[stripe-connect] create_account:", err); return json({ error: err }, 502); }
    await adminClient.from("drivers").update({ stripe_account_id: acct.id, stripe_account_status: "pending", updated_at: new Date().toISOString() }).eq("id", driver.id);
    return json({ success: true, stripe_account_id: acct.id });
  }

  if (!driver.stripe_account_id) return json({ error: "Run create_account first" }, 400);
  const stripeAccountId = driver.stripe_account_id;

  if (action === "update_kyc") {
    const { first_name, last_name, dob_day, dob_month, dob_year, ssn_last4, address_line1, address_city, address_state, address_postal, address_country = STRIPE_CONNECT_COUNTRY } = body;
    if (!first_name || !last_name) return json({ error: "first_name and last_name required" }, 400);
    const p = { "individual[first_name]": first_name, "individual[last_name]": last_name };
    if (dob_day && dob_month && dob_year) { p["individual[dob][day]"] = String(dob_day); p["individual[dob][month]"] = String(dob_month); p["individual[dob][year]"] = String(dob_year); }
    if (ssn_last4) p["individual[ssn_last_4]"] = ssn_last4;
    if (address_line1) { p["individual[address][line1]"] = address_line1; p["individual[address][city]"] = address_city ?? ""; p["individual[address][state]"] = address_state ?? ""; p["individual[address][postal_code]"] = address_postal ?? ""; p["individual[address][country]"] = address_country; }
    const result = await stripePost(`/accounts/${stripeAccountId}`, p);
    const err = stripeErr(result);
    if (err) return json({ error: err }, 502);
    const ad = await stripeGet(`/accounts/${stripeAccountId}`);
    const payoutsEnabled = ad.payouts_enabled === true;
    const chargesEnabled = ad.charges_enabled === true;
    const newStatus = payoutsEnabled ? "active" : (ad.requirements?.disabled_reason ? "restricted" : "pending");
    const reqs = ad.requirements ?? {};
    const pending = [...new Set([...(reqs.currently_due ?? []), ...(reqs.eventually_due ?? [])])];
    await adminClient.from("drivers").update({ kyc_first_name: first_name, kyc_last_name: last_name, kyc_dob_day: dob_day ? Number(dob_day) : null, kyc_dob_month: dob_month ? Number(dob_month) : null, kyc_dob_year: dob_year ? Number(dob_year) : null, kyc_ssn_last4: ssn_last4 ?? null, kyc_address_line1: address_line1 ?? null, kyc_address_city: address_city ?? null, kyc_address_state: address_state ?? null, kyc_address_postal: address_postal ?? null, kyc_address_country: address_country, kyc_submitted_at: new Date().toISOString(), payouts_enabled: payoutsEnabled, charges_enabled: chargesEnabled, stripe_account_status: newStatus, updated_at: new Date().toISOString() }).eq("id", driver.id);
    return json({ success: true, payouts_enabled: payoutsEnabled, charges_enabled: chargesEnabled, stripe_account_status: newStatus, pending_requirements: pending });
  }

  if (action === "add_bank") {
    const { account_number, routing_number, account_holder_name, account_holder_type = "individual", currency = "usd" } = body;
    if (!account_number || !routing_number || !account_holder_name) return json({ error: "account_number, routing_number, account_holder_name required" }, 400);
    const ea = await stripePost(`/accounts/${stripeAccountId}/external_accounts`, { "external_account[object]": "bank_account", "external_account[country]": STRIPE_CONNECT_COUNTRY, "external_account[currency]": currency, "external_account[account_number]": account_number, "external_account[routing_number]": routing_number, "external_account[account_holder_name]": account_holder_name, "external_account[account_holder_type]": account_holder_type, default_for_currency: "true" });
    const err = stripeErr(ea);
    if (err) return json({ error: err }, 502);
    await adminClient.from("driver_payout_methods").delete().eq("driver_id", driver.id).eq("type", "bank_account");
    await adminClient.from("driver_payout_methods").insert({ driver_id: driver.id, stripe_external_account_id: ea.id, type: "bank_account", last4: ea.last4 ?? "????", bank_name: ea.bank_name ?? null, currency: ea.currency ?? "usd", is_default: true });
    return json({ success: true, external_account_id: ea.id, last4: ea.last4, bank_name: ea.bank_name });
  }

  if (action === "add_card") {
    const { token } = body;
    if (!token || !token.startsWith("tok_")) return json({ error: "Valid Stripe token required (tok_…)" }, 400);
    const ea = await stripePost(`/accounts/${stripeAccountId}/external_accounts`, { external_account: token, default_for_currency: "true" });
    const err = stripeErr(ea);
    if (err) { if (err.toLowerCase().includes("debit")) return json({ error: "Only Visa/Mastercard debit cards accepted." }, 422); return json({ error: err }, 502); }
    await adminClient.from("driver_payout_methods").delete().eq("driver_id", driver.id).eq("type", "card");
    await adminClient.from("driver_payout_methods").insert({ driver_id: driver.id, stripe_external_account_id: ea.id, type: "card", last4: ea.last4 ?? "????", brand: ea.brand ?? null, currency: ea.currency ?? "usd", is_default: true });
    await adminClient.from("drivers").update({ stripe_debit_card_added: true, payouts_enabled: true, stripe_account_status: "active", updated_at: new Date().toISOString() }).eq("id", driver.id);
    return json({ success: true, external_account_id: ea.id, last4: ea.last4, brand: ea.brand });
  }

  return json({ error: `Unknown action: ${action}` }, 400);
});

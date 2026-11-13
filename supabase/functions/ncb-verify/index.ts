// NCB Genius Checkout — verify a session when the customer returns to the app.
// The webhook is authoritative, but we also verify on redirect so the UI can
// confirm immediately. Server-to-server GET; never trust redirect URL params.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const GC_API_KEY = Deno.env.get("NCB_GC_API_KEY") ?? "";
const GC_BASE = (Deno.env.get("NCB_GC_BASE_URL") ?? "https://app.geniuscheckout.com").replace(/\/+$/, "");

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    if (!GC_API_KEY) return json({ error: "NCB not configured" }, 503);
    const body = await req.json();
    const orderId = (body.order_id ?? "").toString();
    let sessionId = (body.session_id ?? "").toString();

    if (!sessionId && orderId) {
      const { data: o } = await admin.from("orders").select("ncb_session_id").eq("id", orderId).maybeSingle();
      sessionId = (o?.ncb_session_id ?? "").toString();
    }
    if (!sessionId) return json({ error: "session_id or order_id required" }, 400);

    const res = await fetch(`${GC_BASE}/api/v1/checkout-sessions/${sessionId}`, {
      headers: { "Authorization": `Bearer ${GC_API_KEY}` },
    });
    const data = await res.json().catch(() => ({}));
    if (!res.ok) return json({ error: data?.error ?? "verify failed", status: res.status }, 502);

    const status = data.status as string;             // open|completed|failed|expired|cancelled
    const txn = data.transaction ?? {};
    const oid = orderId || sessionId;

    if (status === "completed") {
      const now = new Date().toISOString();
      await admin.from("payments").upsert({
        order_id: orderId || null,
        amount: Number(data.amount ?? 0) / 100,
        method: "card", status: "completed", gateway: "ncb_genius_checkout",
        transaction_id: (txn.id ?? "").toString(),
        idempotency_key: (txn.id ?? sessionId).toString(),
        currency: (data.currency ?? "JMD").toString(), paid_at: now, updated_at: now,
      }, { onConflict: "order_id", ignoreDuplicates: false });

      if (orderId) {
        await admin.from("orders").update({
          payment_status: "completed",
          ncb_transaction_id: (txn.id ?? "").toString(),
          ncb_token_id: (txn.token_id ?? "").toString() || null,
          updated_at: now,
        }).eq("id", orderId).neq("payment_status", "completed");
      }
    }

    return json({ paid: status === "completed", status, order_id: oid, session_id: sessionId });
  } catch (e) {
    return json({ error: "Server error", details: `${e}` }, 500);
  }
});

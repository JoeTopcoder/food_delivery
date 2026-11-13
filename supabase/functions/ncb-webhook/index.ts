// NCB Genius Checkout webhook — the AUTHORITATIVE payment confirmation.
// Verifies the HMAC-SHA256 signature, rejects replays, is idempotent on
// event_id, and marks the order paid exactly like stripe-webhook does.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const admin = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
const SECRET      = Deno.env.get("NCB_GC_WEBHOOK_SECRET") ?? "";
const SECRET_PREV = Deno.env.get("NCB_GC_WEBHOOK_SECRET_PREV") ?? "";

const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { "Content-Type": "application/json" } });

async function hmacHex(secret: string, msg: string): Promise<string> {
  const key = await crypto.subtle.importKey(
    "raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const sig = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(msg));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function constEq(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0; for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

Deno.serve(async (req) => {
  try {
    const raw = await req.text();
    const sig = req.headers.get("X-GC-Signature") ?? "";
    const ts  = req.headers.get("X-GC-Timestamp") ?? "";
    const eventId = req.headers.get("X-GC-Event-ID") ?? "";

    // Reject stale events (replay protection): timestamp within 5 minutes.
    const skew = Math.abs(Date.now() / 1000 - Number(ts));
    if (!ts || Number.isNaN(skew) || skew > 300) return json({ error: "stale" }, 400);

    // Verify signature against current, then previous secret (rotation window).
    if (SECRET) {
      const msg = `${ts}.${raw}`;
      const okCur  = constEq(sig, await hmacHex(SECRET, msg));
      const okPrev = SECRET_PREV ? constEq(sig, await hmacHex(SECRET_PREV, msg)) : false;
      if (!okCur && !okPrev) return json({ error: "bad signature" }, 401);
    }

    const evt = JSON.parse(raw);
    const type = evt.event_type as string;
    const p = (evt.payload_redacted ?? {}) as Record<string, unknown>;
    const orderId = ((p.metadata as Record<string, unknown>)?.order_id ?? "").toString();
    const evId = (evt.event_id ?? eventId ?? "").toString();
    const now = new Date().toISOString();

    // Idempotency: skip if we've already processed this event id.
    if (evId) {
      const { data: seen } = await admin.from("payments").select("id").eq("idempotency_key", evId).maybeSingle();
      if (seen) return json({ ok: true, duplicate: true });
    }

    if (!orderId) return json({ ok: true, ignored: "no order_id" });

    if (type === "payment.completed" || type === "payment.captured") {
      const { data: order } = await admin.from("orders")
        .select("id, payment_status").eq("id", orderId).maybeSingle();
      if (!order) return json({ ok: true, ignored: "order gone" });

      await admin.from("payments").upsert({
        order_id: orderId,
        user_id: null,
        amount: Number(p.amount ?? 0) / 100,
        method: "card",
        status: "completed",
        gateway: "ncb_genius_checkout",
        transaction_id: (p.transaction_id ?? "").toString(),
        currency: (p.currency ?? "JMD").toString(),
        idempotency_key: evId || (p.transaction_id ?? "").toString(),
        paid_at: now,
        updated_at: now,
      }, { onConflict: "order_id", ignoreDuplicates: false });

      // Mark the order paid (idempotent). Leaves status as-is so the restaurant
      // still Accepts it; the payment_status→completed transition fires the
      // restaurant new-order notification trigger.
      await admin.from("orders").update({
        payment_status: "completed",
        ncb_transaction_id: (p.transaction_id ?? "").toString(),
        ncb_token_id: (p.token_id ?? "").toString() || null,
        updated_at: now,
      }).eq("id", orderId).neq("payment_status", "completed");

      return json({ ok: true });
    }

    if (type === "payment.failed" || type === "checkout.session.expired" || type === "checkout.cancelled") {
      // Do not delete the order (customer may retry); just record the failure.
      await admin.from("orders").update({ payment_status: "failed", updated_at: now })
        .eq("id", orderId).eq("payment_status", "pending");
      return json({ ok: true, outcome: "failed/cancelled" });
    }

    if (type === "payment.refunded") {
      await admin.from("payments").update({
        refund_amount: Number(p.amount ?? 0) / 100, refund_reason: "ncb refund", updated_at: now,
      }).eq("order_id", orderId);
      return json({ ok: true, outcome: "refunded" });
    }

    return json({ ok: true, ignored: type });
  } catch (e) {
    return json({ error: "Server error", details: `${e}` }, 500);
  }
});

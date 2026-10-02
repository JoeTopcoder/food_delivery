// send-new-order-alert — Emails the business (restaurant owner + admins + an
// optional configurable alert address) whenever a customer places an order.
// This is the "you got a new order" notification; the customer-facing receipt
// is handled separately by send-receipt-email.
//
// Recipients (de-duplicated, non-null):
//   • the ordered restaurant's owner (users.email via restaurants.owner_id)
//   • the restaurant's own contact email (restaurants.email)
//   • every admin user (users where role = 'admin')
//   • app_config.order_alert_email, if set (a single business inbox)
//
// Set RESEND_API_KEY + RESEND_FROM_EMAIL secrets (shared with other emails).
// Deploy: supabase functions deploy send-new-order-alert --no-verify-jwt

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
import { sendEmail } from "../_shared/resend.ts";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function orderDisplayId(orderId: string): string {
  return orderId.substring(0, 8).toUpperCase();
}

function escapeHtml(str: string): string {
  return String(str ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function formatTime(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleString("en-US", {
    weekday: "short", month: "short", day: "numeric",
    hour: "2-digit", minute: "2-digit", timeZone: "America/Jamaica",
  });
}

interface OrderItem {
  item_name: string;
  quantity: number;
  subtotal: number;
}

function buildHtml(args: {
  receiptNumber: string; restName: string; customerName: string;
  items: OrderItem[]; total: number; currency: string; address: string;
  paymentMethod: string; placedAt: string; instructions: string;
}): string {
  const { receiptNumber, restName, customerName, items, total, currency, address, paymentMethod, placedAt, instructions } = args;
  const rows = items.map((it) =>
    `<tr>
       <td style="padding:6px 0;color:#1e293b;">${it.quantity}× ${escapeHtml(it.item_name)}</td>
       <td style="padding:6px 0;text-align:right;color:#1e293b;">${currency}${Number(it.subtotal ?? 0).toFixed(2)}</td>
     </tr>`
  ).join("");

  return `<!doctype html><html><body style="margin:0;background:#f1f5f9;font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;">
  <div style="max-width:560px;margin:0 auto;padding:24px;">
    <div style="background:#2563eb;color:#fff;padding:20px 24px;border-radius:12px 12px 0 0;">
      <div style="font-size:13px;letter-spacing:.5px;opacity:.9;">NEW ORDER</div>
      <div style="font-size:22px;font-weight:800;">#${receiptNumber}</div>
    </div>
    <div style="background:#fff;padding:24px;border-radius:0 0 12px 12px;">
      <p style="margin:0 0 4px;color:#64748b;font-size:13px;">${escapeHtml(restName)} · ${escapeHtml(formatTime(placedAt))}</p>
      <p style="margin:0 0 16px;color:#1e293b;"><strong>Customer:</strong> ${escapeHtml(customerName)}</p>
      <table style="width:100%;border-collapse:collapse;border-top:1px solid #e2e8f0;">${rows}</table>
      <table style="width:100%;border-collapse:collapse;border-top:2px solid #e2e8f0;margin-top:8px;">
        <tr><td style="padding:10px 0;font-weight:800;color:#1e293b;">Total</td>
            <td style="padding:10px 0;text-align:right;font-weight:800;color:#1e293b;">${currency}${total.toFixed(2)}</td></tr>
      </table>
      <p style="margin:12px 0 2px;color:#1e293b;"><strong>Payment:</strong> ${escapeHtml(paymentMethod)}</p>
      <p style="margin:2px 0;color:#1e293b;"><strong>Deliver to:</strong> ${escapeHtml(address || "—")}</p>
      ${instructions ? `<p style="margin:2px 0;color:#b45309;"><strong>Note:</strong> ${escapeHtml(instructions)}</p>` : ""}
      <p style="margin:20px 0 0;color:#94a3b8;font-size:12px;">Open the HotBite app to accept and prepare this order.</p>
    </div>
  </div></body></html>`;
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }
  const orderId = body.order_id as string;
  if (!orderId) return json({ error: "order_id is required" }, 400);

  try {
    const { data: order, error: orderErr } = await admin
      .from("orders")
      .select(`*, order_items ( item_name, quantity, subtotal )`)
      .eq("id", orderId)
      .single();
    if (orderErr || !order) return json({ error: "Order not found" }, 404);

    const { data: customer } = await admin
      .from("users").select("name").eq("id", order.user_id).single();

    const { data: restaurant } = await admin
      .from("restaurants")
      .select("name, public_name, store_type, email, owner_id")
      .eq("id", order.restaurant_id)
      .single();

    // ── Recipients ───────────────────────────────────────────────────────
    const recipients = new Set<string>();
    if (restaurant?.email) recipients.add(String(restaurant.email).trim());
    if (restaurant?.owner_id) {
      const { data: owner } = await admin.from("users").select("email").eq("id", restaurant.owner_id).maybeSingle();
      if (owner?.email) recipients.add(String(owner.email).trim());
    }
    const { data: admins } = await admin.from("users").select("email").eq("role", "admin");
    for (const a of admins ?? []) if (a?.email) recipients.add(String(a.email).trim());
    const { data: cfg } = await admin.from("app_config").select("value").eq("key", "order_alert_email").maybeSingle();
    const alertEmail = cfg?.value ? String(cfg.value).replace(/"/g, "").trim() : "";
    if (alertEmail) recipients.add(alertEmail);

    const to = [...recipients].filter((e) => e && e.includes("@"));
    if (to.length === 0) return json({ error: "No recipients configured" }, 404);

    const { data: symCfg } = await admin.from("app_config").select("value").eq("key", "currency_symbol").maybeSingle();
    const currency = symCfg?.value ? String(symCfg.value).replace(/"/g, "").trim() : "$";

    const st = (restaurant?.store_type as string) || "";
    const isGrocery = st === "grocery" || st === "both";
    const restName = isGrocery
      ? ((restaurant?.public_name as string || "").trim() || "HotBite Groceries")
      : (restaurant?.name || "HotBite");
    const receiptNumber = orderDisplayId(orderId);

    const html = buildHtml({
      receiptNumber,
      restName,
      customerName: customer?.name || "Customer",
      items: (order.order_items || []) as OrderItem[],
      total: Number(order.total_amount ?? 0),
      currency,
      address: order.delivery_address as string || "",
      paymentMethod: (order.payment_method as string || "—").toUpperCase(),
      placedAt: order.created_at as string || new Date().toISOString(),
      instructions: order.special_instructions as string || "",
    });

    const result = await sendEmail({
      to,
      subject: `🧾 New order #${receiptNumber} — ${currency}${Number(order.total_amount ?? 0).toFixed(2)} at ${restName}`,
      html,
    });

    if (!result.ok) {
      console.error("new-order-alert Resend error:", result.error);
      return json({ error: "Failed to send", details: result.error }, 500);
    }
    return json({ success: true, email_id: result.id, sent_to: to });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

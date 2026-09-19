// send-receipt-email — Send a beautiful HTML receipt to the customer's email
// Uses Resend API for reliable email delivery.
// Set RESEND_API_KEY secret: npx supabase secrets set RESEND_API_KEY=re_xxxxx
// Deploy: supabase functions deploy send-receipt-email --no-verify-jwt

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

function formatCurrency(amount: number): string {
  return `$${amount.toFixed(2)}`;
}

function formatDate(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleString("en-US", {
    weekday: "short",
    year: "numeric",
    month: "short",
    day: "numeric",
    timeZone: "America/Jamaica",
  });
}

function formatTime(dateStr: string): string {
  const d = new Date(dateStr);
  return d.toLocaleString("en-US", {
    hour: "2-digit",
    minute: "2-digit",
    timeZone: "America/Jamaica",
  });
}

/// Canonical order id shown to everyone — app order history, driver screens,
/// admin and this email receipt — so the same order reads identically in every
/// place: "#AA311238" (first 8 of the order UUID, upper-cased).
function orderDisplayId(orderId: string): string {
  return `#${orderId.substring(0, 8).toUpperCase()}`;
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

interface OrderItem {
  item_name: string;
  price: number;
  quantity: number;
  subtotal: number;
  order_item_sides?: Array<{ side_name: string; side_price: number }>;
}

function buildReceiptHtml(order: Record<string, unknown>, items: OrderItem[], restaurant: Record<string, unknown>, customerName: string): string {
  const receiptNumber = orderDisplayId(order.id as string);
  const orderDate = formatDate(order.ordered_at as string);
  const orderTime = formatTime(order.ordered_at as string);
  // White-label: grocery partner stores are anonymised to customers — show the
  // public brand / alias and hide the store address. Food stores show the real
  // name and address.
  const storeType = restaurant.store_type as string || "";
  const isGrocery = storeType === "grocery" || storeType === "both";
  const publicName = (restaurant.public_name as string || "").trim();
  const restName = escapeHtml(
    isGrocery
      ? (publicName || "Quickdash Groceries")
      : (restaurant.name as string || "Restaurant"),
  );
  const restAddress = isGrocery
    ? ""
    : escapeHtml(restaurant.address as string || "");
  const deliveryAddress = escapeHtml(order.delivery_address as string || "");
  const isPickup = order.is_pickup === true;
  const paymentMethod = (order.payment_method as string || "cash").replace("_", " ");

  const subtotal = Number(order.subtotal) || 0;
  const deliveryFee = Number(order.delivery_fee) || 0;
  const taxAmount = Number(order.tax_amount) || 0;
  const discount = Number(order.discount) || 0;
  const driverTip = Number(order.driver_tip) || 0;
  const totalAmount = Number(order.total_amount) || 0;
  // Service fee isn't stored as its own column — derive it from the residual so
  // the receipt breakdown reconciles to the charged total.
  const serviceFee = Math.max(
    0,
    totalAmount - subtotal - deliveryFee - taxAmount + discount - driverTip,
  );

  const itemRows = items.map((item) => {
    const sides = (item.order_item_sides || [])
      .map((s) => `<div style="color:#888;font-size:12px;padding-left:12px;">+ ${escapeHtml(s.side_name)} ${formatCurrency(s.side_price)}</div>`)
      .join("");
    return `
      <tr>
        <td style="padding:10px 0;border-bottom:1px solid #f0f0f0;">
          <div style="font-weight:600;color:#1a1a2e;">${escapeHtml(item.item_name)}</div>
          ${sides}
        </td>
        <td style="padding:10px 0;border-bottom:1px solid #f0f0f0;text-align:center;color:#666;">${item.quantity}</td>
        <td style="padding:10px 0;border-bottom:1px solid #f0f0f0;text-align:right;font-weight:500;">${formatCurrency(item.subtotal)}</td>
      </tr>`;
  }).join("");

  const discountRow = discount > 0
    ? `<tr><td style="padding:6px 0;color:#22c55e;">Discount</td><td style="text-align:right;color:#22c55e;font-weight:500;">-${formatCurrency(discount)}</td></tr>`
    : "";

  const tipRow = driverTip > 0
    ? `<tr><td style="padding:6px 0;color:#666;">Driver Tip</td><td style="text-align:right;">${formatCurrency(driverTip)}</td></tr>`
    : "";

  return `
<!DOCTYPE html>
<html>
<head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background-color:#f5f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <div style="max-width:560px;margin:0 auto;padding:24px 16px;">

    <!-- Header -->
    <div style="background:#FF6B35;background:linear-gradient(135deg,#FF6B35 0%,#FF8C42 100%);border-radius:16px 16px 0 0;padding:32px 24px 28px;text-align:center;">
      <img src="https://yharweliruemjexmuuxn.supabase.co/storage/v1/object/public/banners/quickdash-logo.png"
           width="64" height="64" alt="QuickDash"
           style="display:block;margin:0 auto 12px;width:64px;height:64px;border-radius:16px;background:#ffffff;" />
      <div style="font-size:26px;line-height:32px;font-weight:800;color:#ffffff;letter-spacing:-0.5px;">QuickDash</div>
      <div style="color:rgba(255,255,255,0.9);font-size:14px;line-height:20px;margin-top:6px;">Order Receipt</div>
    </div>

    <!-- Body -->
    <div style="background:#fff;padding:28px 24px;border-radius:0 0 16px 16px;box-shadow:0 2px 12px rgba(0,0,0,0.06);">

      <!-- Receipt info (table for email-client reliability) -->
      <table style="width:100%;border-collapse:collapse;margin-bottom:20px;">
        <tr>
          <td style="vertical-align:top;padding:0;">
            <div style="font-size:12px;color:#999;text-transform:uppercase;letter-spacing:0.5px;">Receipt</div>
            <div style="font-weight:700;color:#1a1a2e;font-size:15px;margin-top:2px;">${escapeHtml(receiptNumber)}</div>
          </td>
          <td style="vertical-align:top;padding:0;text-align:right;">
            <div style="font-size:12px;color:#999;text-transform:uppercase;letter-spacing:0.5px;">Date</div>
            <div style="color:#1a1a2e;font-size:13px;margin-top:2px;">${orderDate}</div>
            <div style="color:#999;font-size:12px;margin-top:2px;">${orderTime}</div>
          </td>
        </tr>
      </table>

      <!-- Restaurant -->
      <div style="background:#f8f9fa;border-radius:10px;padding:14px 16px;margin-bottom:20px;">
        <div style="font-size:12px;color:#999;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">${isPickup ? "Pickup From" : "Ordered From"}</div>
        <div style="font-weight:700;color:#1a1a2e;font-size:15px;">${restName}</div>
        ${restAddress ? `<div style="color:#666;font-size:13px;margin-top:2px;">${restAddress}</div>` : ""}
      </div>

      ${!isPickup ? `
      <!-- Delivery address -->
      <div style="background:#f8f9fa;border-radius:10px;padding:14px 16px;margin-bottom:20px;">
        <div style="font-size:12px;color:#999;text-transform:uppercase;letter-spacing:0.5px;margin-bottom:4px;">Delivered To</div>
        <div style="color:#1a1a2e;font-size:14px;">${deliveryAddress}</div>
      </div>
      ` : ""}

      <!-- Items table -->
      <table style="width:100%;border-collapse:collapse;margin-bottom:20px;">
        <thead>
          <tr style="border-bottom:2px solid #e8e8e8;">
            <th style="text-align:left;padding:8px 0;font-size:12px;color:#999;text-transform:uppercase;letter-spacing:0.5px;">Item</th>
            <th style="text-align:center;padding:8px 0;font-size:12px;color:#999;text-transform:uppercase;letter-spacing:0.5px;">Qty</th>
            <th style="text-align:right;padding:8px 0;font-size:12px;color:#999;text-transform:uppercase;letter-spacing:0.5px;">Amount</th>
          </tr>
        </thead>
        <tbody>
          ${itemRows}
        </tbody>
      </table>

      <!-- Totals -->
      <table style="width:100%;border-collapse:collapse;">
        <tr><td style="padding:6px 0;color:#666;">Subtotal</td><td style="text-align:right;">${formatCurrency(subtotal)}</td></tr>
        <tr><td style="padding:6px 0;color:#666;">${isPickup ? "Pickup Fee" : "Delivery Fee"}</td><td style="text-align:right;">${formatCurrency(deliveryFee)}</td></tr>
        ${serviceFee > 0.01 ? `<tr><td style="padding:6px 0;color:#666;">Service Fee</td><td style="text-align:right;">${formatCurrency(serviceFee)}</td></tr>` : ""}
        ${taxAmount > 0 ? `<tr><td style="padding:6px 0;color:#666;">Tax</td><td style="text-align:right;">${formatCurrency(taxAmount)}</td></tr>` : ""}
        ${discountRow}
        ${tipRow}
        <tr style="border-top:2px solid #1a1a2e;">
          <td style="padding:12px 0;font-weight:800;font-size:17px;color:#1a1a2e;">Total</td>
          <td style="text-align:right;padding:12px 0;font-weight:800;font-size:17px;color:#1a1a2e;">${formatCurrency(totalAmount)}</td>
        </tr>
      </table>

      <!-- Payment method -->
      <div style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:10px;padding:12px 16px;margin-top:16px;text-align:center;">
        <span style="color:#16a34a;font-weight:600;font-size:13px;">Paid via ${escapeHtml(paymentMethod.charAt(0).toUpperCase() + paymentMethod.slice(1))}</span>
      </div>

      ${order.delivery_otp ? `
      <div style="background:#fef3c7;border:1px solid #fde68a;border-radius:10px;padding:12px 16px;margin-top:12px;text-align:center;">
        <div style="font-size:11px;color:#92400e;text-transform:uppercase;letter-spacing:0.5px;">Delivery Verification Code</div>
        <div style="font-size:24px;font-weight:800;letter-spacing:6px;color:#92400e;margin-top:4px;">${order.delivery_otp}</div>
      </div>` : ""}

      ${order.pickup_code ? `
      <div style="background:#fef3c7;border:1px solid #fde68a;border-radius:10px;padding:12px 16px;margin-top:12px;text-align:center;">
        <div style="font-size:11px;color:#92400e;text-transform:uppercase;letter-spacing:0.5px;">Pickup Code</div>
        <div style="font-size:24px;font-weight:800;letter-spacing:6px;color:#92400e;margin-top:4px;">${order.pickup_code}</div>
      </div>` : ""}
    </div>

    <!-- Footer -->
    <div style="text-align:center;padding:24px 0;color:#999;font-size:12px;">
      <div>Thank you for ordering with QuickDash!</div>
      <div style="margin-top:4px;">If you have questions, contact support@quickdash.app</div>
    </div>
  </div>
</body>
</html>`;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const orderId = body.order_id as string;
  if (!orderId) {
    return json({ error: "order_id is required" }, 400);
  }

  try {
    // ── 1. Fetch order with items ────────────────────────────────────────
    const { data: order, error: orderErr } = await admin
      .from("orders")
      .select(`
        *,
        order_items (
          id,
          item_name,
          price,
          quantity,
          subtotal,
          order_item_sides ( side_name, side_price )
        )
      `)
      .eq("id", orderId)
      .single();

    if (orderErr || !order) {
      return json({ error: "Order not found" }, 404);
    }

    // ── 2. Fetch customer email ──────────────────────────────────────────
    const { data: customer } = await admin
      .from("users")
      .select("email, name")
      .eq("id", order.user_id)
      .single();

    if (!customer?.email) {
      return json({ error: "Customer email not found" }, 404);
    }

    // ── 3. Fetch restaurant info ─────────────────────────────────────────
    const { data: restaurant } = await admin
      .from("restaurants")
      .select("name, address, phone, store_type, public_name")
      .eq("id", order.restaurant_id)
      .single();

    // ── 4. Build HTML receipt ────────────────────────────────────────────
    const customerName = customer.name || "Customer";
    const items = (order.order_items || []) as OrderItem[];
    const html = buildReceiptHtml(order, items, restaurant || {}, customerName);

    // Canonical order id, matching the app order history, driver and admin.
    const receiptNumber = orderDisplayId(orderId);
    // White-label grocery stores in the subject line too.
    const st = restaurant?.store_type as string || "";
    const isGroceryStore = st === "grocery" || st === "both";
    const restName = isGroceryStore
      ? ((restaurant?.public_name as string || "").trim() || "Quickdash Groceries")
      : (restaurant?.name || "QuickDash");

    // ── 5. Send via Resend ───────────────────────────────────────────────
    const emailResult = await sendEmail({
      to: [customer.email],
      subject: `Your QuickDash Receipt — ${receiptNumber} from ${restName}`,
      html,
    });

    if (!emailResult.ok) {
      console.error("Resend error:", emailResult.error);
      return json({ error: "Failed to send email", details: emailResult.error }, 500);
    }

    // ── 6. Mark receipt as sent on the order ─────────────────────────────
    await admin
      .from("orders")
      .update({ receipt_emailed_at: new Date().toISOString() })
      .eq("id", orderId);

    return json({
      success: true,
      email_id: emailResult.id,
      sent_to: customer.email,
      receipt_number: receiptNumber,
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

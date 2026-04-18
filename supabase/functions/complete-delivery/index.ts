// complete-delivery — Server-side delivery completion
// Handles: status update, driver stats recalculation, cash float, customer notification,
// referral earnings, signup bonus check — all in one round-trip from the driver app.
// Deploy: supabase functions deploy complete-delivery

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

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

async function getConfig(key: string, fallback: number): Promise<number> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  return data ? parseFloat(data.value) : fallback;
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
    const now = new Date().toISOString();

    // ── 1. Update order status to delivered ─────────────────────────────
    const { data: order, error: updateErr } = await admin
      .from("orders")
      .update({
        status: "delivered",
        completed_at: now,
        delivered_at: now,
        updated_at: now,
      })
      .eq("id", orderId)
      .neq("status", "delivered") // Prevent double-completion
      .select("id, user_id, driver_id, payment_method, total_amount, delivery_fee, driver_tip")
      .single();

    if (updateErr || !order) {
      return json({ error: "Order not found or already delivered", details: updateErr?.message }, 400);
    }

    const driverId = order.driver_id as string | null;
    const customerId = order.user_id as string | null;

    // ── 2. Notify customer (fire-and-forget) ────────────────────────────
    if (customerId) {
      admin
        .from("users")
        .select("fcm_token")
        .eq("id", customerId)
        .maybeSingle()
        .then(({ data: userRow }) => {
          const token = userRow?.fcm_token;
          if (token) {
            admin.functions.invoke("send-fcm-notification", {
              body: {
                token,
                title: "Order Delivered! 🎉",
                body: `Order #${orderId.substring(0, 8).toUpperCase()} delivered! Rate your experience`,
                data: {
                  type: "order_status",
                  order_id: orderId,
                  status: "delivered",
                  user_id: customerId,
                },
              },
            }).catch(() => {});
          }
        })
        .catch(() => {});
    }

    // ── 3. Recalculate driver stats ─────────────────────────────────────
    let driverStats: Record<string, unknown> = {};

    if (driverId) {
      const driverPayPercent = await getConfig("driver_pay_percent", 0.80);
      const bonusPerOrder = await getConfig("driver_bonus_per_order", 0);

      // Fetch all delivered orders for this driver
      const { data: deliveries } = await admin
        .from("orders")
        .select("id, driver_rating, driver_tip, delivery_fee, payment_method, total_amount")
        .eq("driver_id", driverId)
        .eq("status", "delivered");

      const deliveryList = (deliveries ?? []) as Array<Record<string, unknown>>;
      const completedCount = deliveryList.length;

      // Cancelled count
      const { data: cancelledData } = await admin
        .from("orders")
        .select("id")
        .eq("driver_id", driverId)
        .eq("status", "cancelled");
      const cancelledCount = (cancelledData ?? []).length;

      // Average rating
      const rated = deliveryList.filter((d) => d.driver_rating != null);
      let avgRating: number | null = null;
      if (rated.length > 0) {
        const sum = rated.reduce((s, d) => s + Number(d.driver_rating), 0);
        avgRating = Math.round((sum / rated.length) * 100) / 100;
      }

      // Total tips
      const totalTips = deliveryList.reduce(
        (s, d) => s + (Number(d.driver_tip) || 0),
        0
      );

      // Total driver pay (driverPayPercent of each delivery fee + tips + bonus)
      const totalDriverPay = deliveryList.reduce(
        (s, d) => s + (Number(d.delivery_fee) || 5) * driverPayPercent,
        0
      );
      const totalBonus = bonusPerOrder > 0 ? completedCount * bonusPerOrder : 0;
      const totalEarnings = Math.round((totalDriverPay + totalTips + totalBonus) * 100) / 100;

      // Total paid out (all non-rejected/failed payouts)
      const { data: payoutRows } = await admin
        .from("payout_requests")
        .select("amount")
        .eq("driver_id", driverId)
        .not("status", "in", "(rejected,failed)");
      const totalPaidOut = (payoutRows ?? []).reduce(
        (s: number, r: Record<string, unknown>) => s + (Number(r.amount) || 0),
        0
      );

      const updateData: Record<string, unknown> = {
        completed_deliveries: completedCount,
        cancelled_deliveries: cancelledCount,
        total_earnings: totalEarnings,
        total_paid_out: totalPaidOut,
        updated_at: now,
      };
      if (avgRating !== null) {
        updateData.rating = avgRating;
      }

      await admin
        .from("drivers")
        .update(updateData)
        .eq("id", driverId);

      // ── 4. Cash float for cash orders ───────────────────────────────
      if (order.payment_method === "cash") {
        const totalAmount = Number(order.total_amount) || 0;
        const deliveryFee = Number(order.delivery_fee) || 0;
        const tip = Number(order.driver_tip) || 0;
        const driverKeeps = deliveryFee * driverPayPercent + tip;
        const floatAmount = totalAmount - driverKeeps;

        if (floatAmount > 0) {
          // Try atomic increment via RPC, fall back to manual
          try {
            await admin.rpc("increment_cash_float", {
              p_driver_id: driverId,
              p_amount: floatAmount,
            });
          } catch {
            const { data: driverRow } = await admin
              .from("drivers")
              .select("cash_float")
              .eq("id", driverId)
              .single();
            const currentFloat = Number(driverRow?.cash_float) || 0;
            await admin
              .from("drivers")
              .update({ cash_float: currentFloat + floatAmount, updated_at: now })
              .eq("id", driverId);
          }
        }
      }

      driverStats = {
        completed_deliveries: completedCount,
        cancelled_deliveries: cancelledCount,
        total_earnings: totalEarnings,
        total_paid_out: totalPaidOut,
        rating: avgRating,
      };
    }

    // ── 5. Process referral earnings (fire-and-forget) ──────────────────
    if (customerId) {
      // Process per-order referral earnings
      admin.functions.invoke("process-referral-earnings", {
        body: { order_id: orderId, customer_id: customerId },
      }).catch(() => {});

      // Check for signup bonus on first delivery
      admin
        .from("orders")
        .select("id")
        .eq("user_id", customerId)
        .eq("status", "delivered")
        .limit(2)
        .then(({ data: delivered }) => {
          if (delivered && delivered.length === 1) {
            admin.functions.invoke("process-referral-earnings", {
              body: { customer_id: customerId, signup_bonus: true },
            }).catch(() => {});
          }
        })
        .catch(() => {});
    }

    // ── 6. Notify admins (fire-and-forget) ──────────────────────────────
    admin.functions.invoke("send-fcm-notification", {
      body: {
        topic: "admins",
        title: "Order Delivered ✅",
        body: `Order #${orderId.substring(0, 8).toUpperCase()} has been delivered`,
        data: {
          type: "order_status",
          order_id: orderId,
          status: "delivered",
        },
      },
    }).catch(() => {});

    return json({
      success: true,
      order_id: orderId,
      status: "delivered",
      driver_stats: driverStats,
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

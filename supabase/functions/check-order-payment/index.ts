import { serve } from "https://deno.land/std@0.224.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.47.0";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const admin = createClient(
  Deno.env.get("SUPABASE_URL") || "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method not allowed" }),
      { status: 405, headers: corsHeaders }
    );
  }

  try {
    const body = await req.json();
    const { order_id } = body;

    if (!order_id) {
      return new Response(
        JSON.stringify({ error: "Missing order_id" }),
        { status: 400, headers: corsHeaders }
      );
    }

    // ── Fetch order payment status ───────────────────────────────────────
    const { data: order, error: orderErr } = await admin
      .from("orders")
      .select("id, payment_status, order_status")
      .eq("id", order_id)
      .single();

    if (orderErr || !order) {
      return new Response(
        JSON.stringify({ error: "Order not found" }),
        { status: 404, headers: corsHeaders }
      );
    }

    // ── Fetch payment details ────────────────────────────────────────────
    const { data: payment, error: payErr } = await admin
      .from("payments")
      .select("id, status, transaction_id, verified_at")
      .eq("order_id", order_id)
      .single();

    if (payErr && payErr.code !== "PGRST116") {
      // PGRST116 = no rows
      console.error("Payment fetch error:", payErr);
    }

    // Return combined status
    return new Response(
      JSON.stringify({
        order_id,
        payment_status: order.payment_status, // pending_payment, paid
        order_status: order.order_status, // draft, placed, confirmed, etc
        payment: payment ? {
          id: payment.id,
          status: payment.status,
          transaction_id: payment.transaction_id,
          verified_at: payment.verified_at,
        } : null,
        // Convenience: true if order is actually paid per backend
        is_paid: order.payment_status === "paid" && order.order_status === "placed",
      }),
      { status: 200, headers: corsHeaders }
    );
  } catch (e) {
    console.error("check-order-payment error:", e);
    return new Response(
      JSON.stringify({ error: e.message }),
      { status: 500, headers: corsHeaders }
    );
  }
});

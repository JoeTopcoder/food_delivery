// @ts-nocheck - Deno Edge Function (URL imports resolved at deploy time)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

/**
 * Generate a receipt / invoice for a delivered order.
 * POST { order_id: string }
 * Returns: receipt object with line items, totals, and receipt_number
 * Deploy: npx supabase functions deploy generate-receipt --no-verify-jwt --project-ref yharweliruemjexmuuxn
 */

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, serviceRoleKey);

    const { order_id } = await req.json();
    if (!order_id) {
      return new Response(
        JSON.stringify({ error: "order_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch order with items
    const { data: order, error: orderError } = await supabase
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
      .eq("id", order_id)
      .single();

    if (orderError || !order) {
      return new Response(
        JSON.stringify({ error: "Order not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Fetch restaurant name
    const { data: restaurant } = await supabase
      .from("restaurants")
      .select("name, address, phone")
      .eq("id", order.restaurant_id)
      .single();

    // Build receipt
    const receipt = {
      receipt_number: order.receipt_number || `RCP-${order_id.substring(0, 8).toUpperCase()}`,
      order_id: order.id,
      order_date: order.ordered_at,
      customer_id: order.user_id,
      restaurant: {
        name: restaurant?.name || "Unknown Restaurant",
        address: restaurant?.address || "",
        phone: restaurant?.phone || "",
      },
      delivery_address: order.delivery_address,
      payment_method: order.payment_method,
      payment_status: order.payment_status,
      items: (order.order_items || []).map((item: any) => ({
        name: item.item_name,
        price: item.price,
        quantity: item.quantity,
        subtotal: item.subtotal,
        sides: (item.order_item_sides || []).map((s: any) => ({
          name: s.side_name,
          price: s.side_price,
        })),
      })),
      subtotal: order.subtotal,
      delivery_fee: order.delivery_fee,
      tax_amount: order.tax_amount || 0,
      discount: order.discount || 0,
      driver_tip: order.driver_tip || 0,
      post_delivery_tip: order.post_delivery_tip || 0,
      total_amount: order.total_amount,
      is_scheduled: order.is_scheduled || false,
      scheduled_for: order.scheduled_for,
      contactless_delivery: order.contactless_delivery,
      currency: "JMD",
    };

    return new Response(
      JSON.stringify(receipt),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

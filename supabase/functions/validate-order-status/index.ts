// validate-order-status — Enforce valid order status transitions
// Prevents invalid state changes (e.g. pending → delivered)
// Records who made the transition and when

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

// Valid transitions: from → [allowed to states]
const VALID_TRANSITIONS: Record<string, string[]> = {
  pending:    ["confirmed", "cancelled"],
  confirmed:  ["preparing", "cancelled"],
  preparing:  ["ready", "cancelled"],
  ready:      ["picked_up", "cancelled"],
  picked_up:  ["on_the_way"],
  on_the_way: ["delivered"],
  delivered:  [],
  cancelled:  [],
};

// Which role can make which transitions
const ROLE_PERMISSIONS: Record<string, string[]> = {
  restaurant: ["confirmed", "preparing", "ready", "cancelled"],
  driver:     ["picked_up", "on_the_way", "delivered"],
  admin:      ["confirmed", "preparing", "ready", "picked_up", "on_the_way", "delivered", "cancelled"],
  user:       ["cancelled"],  // Users can only cancel
};

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
  const newStatus = body.new_status as string;
  const actorId = body.actor_id as string;
  const actorRole = body.actor_role as string;

  if (!orderId || !newStatus || !actorId || !actorRole) {
    return json({ error: "Missing order_id, new_status, actor_id, actor_role" }, 400);
  }

  try {
    // Fetch current order
    const { data: order, error } = await admin
      .from("orders")
      .select("id, status, user_id, restaurant_id, driver_id")
      .eq("id", orderId)
      .single();

    if (error || !order) {
      return json({ error: "Order not found" }, 404);
    }

    const currentStatus = order.status as string;

    // Check if transition is valid
    const allowed = VALID_TRANSITIONS[currentStatus];
    if (!allowed || !allowed.includes(newStatus)) {
      return json({
        error: `Invalid transition: ${currentStatus} → ${newStatus}`,
        current_status: currentStatus,
        allowed_transitions: allowed ?? [],
      }, 400);
    }

    // Check role permission
    const roleAllowed = ROLE_PERMISSIONS[actorRole];
    if (!roleAllowed || !roleAllowed.includes(newStatus)) {
      return json({
        error: `Role '${actorRole}' cannot set status to '${newStatus}'`,
      }, 403);
    }

    // Verify actor owns the right entity
    if (actorRole === "user" && order.user_id !== actorId) {
      return json({ error: "Not your order" }, 403);
    }
    if (actorRole === "driver" && order.driver_id !== actorId) {
      return json({ error: "Not your assigned delivery" }, 403);
    }

    // Build update payload
    const updatePayload: Record<string, unknown> = { status: newStatus };
    const now = new Date().toISOString();

    if (newStatus === "confirmed") updatePayload.confirmed_at = now;
    if (newStatus === "picked_up") updatePayload.picked_up_at = now;
    if (newStatus === "delivered") updatePayload.delivered_at = now;
    if (newStatus === "cancelled") updatePayload.cancelled_at = now;

    // Apply update
    const { data: updated, error: updateErr } = await admin
      .from("orders")
      .update(updatePayload)
      .eq("id", orderId)
      .eq("status", currentStatus)   // Optimistic lock — prevents race conditions
      .select("id, status")
      .single();

    if (updateErr || !updated) {
      return json({
        error: "Status update failed — order may have been updated by another process",
      }, 409);
    }

    return json({
      success: true,
      order_id: orderId,
      previous_status: currentStatus,
      new_status: newStatus,
      updated_by: actorId,
      updated_at: now,
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

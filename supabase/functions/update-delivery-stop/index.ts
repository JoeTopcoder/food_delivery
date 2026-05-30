// update-delivery-stop
// Driver marks a stop as arrived or completed.
// Enforces: cannot mark dropoff completed until all pickup stops are completed.
// Deploy: supabase functions deploy update-delivery-stop

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin       = createClient(supabaseUrl, supabaseKey);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}

interface UpdateStopRequest {
  stop_id: string;
  action:  "arrived" | "completed";
  driver_id: string;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: UpdateStopRequest;
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { stop_id, action, driver_id } = body;
  if (!stop_id || !action || !driver_id) {
    return json({ error: "stop_id, action, and driver_id are required" }, 400);
  }

  // ── 1. Load stop + verify driver owns the task ────────────────────────
  const { data: stop } = await admin
    .from("delivery_stops")
    .select("*, delivery_tasks(driver_id, order_group_id, id)")
    .eq("id", stop_id)
    .single();

  if (!stop) return json({ error: "Stop not found" }, 404);

  const task = (stop as any).delivery_tasks;
  if (!task) return json({ error: "Delivery task not found" }, 404);
  if (task.driver_id !== driver_id) {
    return json({ error: "This stop is not assigned to you" }, 403);
  }

  // ── 2. Enforce pickup-before-dropoff rule ─────────────────────────────
  if (stop.stop_type === "dropoff" && action === "completed") {
    const { data: allStops } = await admin
      .from("delivery_stops")
      .select("id, stop_type, status")
      .eq("delivery_task_id", stop.delivery_task_id);

    const incompletePickups = allStops?.filter(
      (s) => s.stop_type === "pickup" && s.status !== "completed"
    ) ?? [];

    if (incompletePickups.length > 0) {
      return json({
        error: "You must complete all pickup stops before marking the delivery as complete.",
      }, 400);
    }
  }

  // ── 3. Update the stop status ─────────────────────────────────────────
  const now = new Date().toISOString();
  const updateData: Record<string, unknown> = { status: action === "arrived" ? "arrived" : "completed" };
  if (action === "arrived")   updateData.arrived_at   = now;
  if (action === "completed") updateData.completed_at = now;

  const { error: updateErr } = await admin
    .from("delivery_stops")
    .update(updateData)
    .eq("id", stop_id);

  if (updateErr) return json({ error: updateErr.message }, 500);

  // ── 4. Transition task to in_progress on first driver action ─────────
  const { data: taskStatus } = await admin
    .from("delivery_tasks")
    .select("delivery_status")
    .eq("id", stop.delivery_task_id)
    .single();
  if (taskStatus?.delivery_status === "assigned") {
    await admin.from("delivery_tasks")
      .update({ delivery_status: "in_progress", updated_at: now })
      .eq("id", stop.delivery_task_id);
  }

  // ── 5. Mirror status to the linked sub-order ──────────────────────────
  if (stop.order_id) {
    if (stop.stop_type === "pickup" && action === "arrived") {
      await admin.from("orders").update({ status: "ready", updated_at: now }).eq("id", stop.order_id);
    }
    if (stop.stop_type === "pickup" && action === "completed") {
      await admin.from("orders").update({ status: "picked_up", updated_at: now }).eq("id", stop.order_id);
    }
  }

  // ── 6. If dropoff completed → finalize everything ─────────────────────
  if (stop.stop_type === "dropoff" && action === "completed") {
    const groupId = task.order_group_id;

    // Update all sub-orders to delivered
    await admin.from("orders")
      .update({ status: "delivered", completed_at: now, updated_at: now })
      .eq("order_group_id", groupId);

    // Update order group status
    await admin.from("order_groups")
      .update({ status: "delivered", updated_at: now })
      .eq("id", groupId);

    // Update delivery task
    await admin.from("delivery_tasks")
      .update({ delivery_status: "completed", updated_at: now })
      .eq("id", task.id);

    // Mark driver available and increment completed_deliveries (safe read-modify-write)
    const { data: driverRow } = await admin
      .from("drivers")
      .select("completed_deliveries")
      .eq("id", driver_id)
      .single();
    const currentDeliveries = (driverRow?.completed_deliveries ?? 0) as number;
    await admin.from("drivers")
      .update({ is_available: true, completed_deliveries: currentDeliveries + 1 })
      .eq("id", driver_id);

    // Notify customer
    const { data: group } = await admin
      .from("order_groups")
      .select("customer_id")
      .eq("id", groupId)
      .single();

    if (group?.customer_id) {
      await admin.from("notifications").insert({
        user_id: group.customer_id,
        type:    "delivered",
        title:   "✅ Order Delivered!",
        body:    "All your items have been delivered. Enjoy your meal!",
        data:    { order_group_id: groupId },
      }).catch(() => null);

      // Push via FCM — send to the customer's topic (topic is the correct param)
      fetch(`${supabaseUrl}/functions/v1/send-fcm-notification`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${supabaseKey}`,
          "apikey": supabaseKey,
        },
        body: JSON.stringify({
          topic: `customer_${group.customer_id}`,
          title: "✅ Order Delivered!",
          body: "All your items have been delivered. Enjoy your meal!",
          data: { type: "delivered", order_group_id: groupId, user_id: group.customer_id },
        }),
      }).catch(() => null);
    }
  }

  // ── 6. Load updated stop list to return to driver app ─────────────────
  const { data: updatedStops } = await admin
    .from("delivery_stops")
    .select("id, stop_type, restaurant_id, sequence_number, status, address, latitude, longitude")
    .eq("delivery_task_id", stop.delivery_task_id)
    .order("sequence_number");

  return json({
    success:    true,
    stop_id,
    new_status: updateData.status,
    all_stops:  updatedStops ?? [],
  });
});

// update-package-status: driver advances delivery through the status machine.
// Deployed with --no-verify-jwt
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function userId(authHeader: string | null): string | null {
  if (!authHeader) return null;
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1]));
    return payload.sub as string ?? null;
  } catch { return null; }
}

// Valid transitions: from → allowed next statuses
const ALLOWED: Record<string, string[]> = {
  pending_verification:        ["verified", "cancelled"],
  verified:                    ["awaiting_payment", "cancelled"],
  awaiting_payment:            ["searching_driver", "cancelled"],
  searching_driver:            ["driver_assigned", "cancelled"],
  driver_assigned:             ["driver_arriving_warehouse", "cancelled"],
  driver_arriving_warehouse:   ["driver_at_warehouse"],
  driver_at_warehouse:         ["package_picked_up"],
  package_picked_up:           ["in_transit"],
  in_transit:                  ["arriving_destination"],
  arriving_destination:        ["delivered"],
  delivered:                   [],
  cancelled:                   [],
  failed:                      [],
};

// Statuses that only admins/system can set
const SYSTEM_ONLY = new Set(["verified", "awaiting_payment", "searching_driver", "driver_assigned"]);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const uid = userId(req.headers.get("Authorization"));
  if (!uid) return json({ error: "Unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  let body: { delivery_request_id: string; new_status: string; note?: string };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }

  const { delivery_request_id, new_status, note } = body;
  if (!delivery_request_id || !new_status) {
    return json({ error: "delivery_request_id and new_status required" }, 400);
  }

  // Fetch delivery request
  const { data: req_, error: reqErr } = await supabase
    .from("package_delivery_requests")
    .select("*, drivers!package_delivery_requests_driver_id_fkey(user_id)")
    .eq("id", delivery_request_id)
    .single();

  if (reqErr || !req_) return json({ error: "Delivery request not found" }, 404);

  const current = req_.delivery_status as string;
  const allowed = ALLOWED[current] ?? [];

  if (!allowed.includes(new_status)) {
    return json({
      error: `Invalid transition: ${current} → ${new_status}`,
      allowed_transitions: allowed,
    }, 422);
  }

  // Determine if user is admin
  const { data: userRow } = await supabase
    .from("users")
    .select("role")
    .eq("id", uid)
    .single();
  const isAdmin = userRow?.role === "admin";

  // Determine if user is the assigned driver
  const driverUserId = (req_.drivers as { user_id: string } | null)?.user_id;
  const isDriver = driverUserId === uid;

  // Customer can only cancel
  const isCustomer = req_.customer_id === uid;

  if (SYSTEM_ONLY.has(new_status) && !isAdmin) {
    return json({ error: "Only admins can set this status" }, 403);
  }

  if (new_status === "cancelled") {
    if (!isCustomer && !isAdmin && !isDriver) {
      return json({ error: "Not authorized to cancel this delivery" }, 403);
    }
  } else if (!isAdmin && !isDriver) {
    return json({ error: "Not authorized to update this delivery" }, 403);
  }

  const updates: Record<string, unknown> = {
    delivery_status: new_status,
    updated_at: new Date().toISOString(),
  };

  if (new_status === "package_picked_up") updates.picked_up_at = new Date().toISOString();
  if (new_status === "delivered") updates.delivered_at = new Date().toISOString();
  if (new_status === "cancelled") {
    updates.cancellation_reason = note ?? null;
    updates.cancelled_by = isCustomer ? "customer" : isDriver ? "driver" : "admin";
  }

  const { data: updated, error: updateErr } = await supabase
    .from("package_delivery_requests")
    .update(updates)
    .eq("id", delivery_request_id)
    .select()
    .single();

  if (updateErr) return json({ error: "Update failed", details: updateErr.message }, 500);

  // Keep package_records in sync
  let pkgStatus: string | null = null;
  if (new_status === "package_picked_up") pkgStatus = "picked_up";
  if (new_status === "delivered") pkgStatus = "delivered";
  if (new_status === "cancelled") pkgStatus = "at_warehouse";

  if (pkgStatus) {
    await supabase
      .from("package_records")
      .update({ package_status: pkgStatus, updated_at: new Date().toISOString() })
      .eq("id", req_.package_record_id);
  }

  return json({ delivery_request: updated });
});

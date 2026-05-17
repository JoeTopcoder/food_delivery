// accept-package-delivery: driver accepts a searching_driver request.
// Uses service role to bypass RLS (driver_id is NULL at accept time).
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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const uid = userId(req.headers.get("Authorization"));
  if (!uid) return json({ error: "Unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  let body: { delivery_request_id: string };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }

  const { delivery_request_id } = body;
  if (!delivery_request_id) {
    return json({ error: "delivery_request_id required" }, 400);
  }

  // Resolve driver record for this user
  const { data: driverRow, error: driverErr } = await supabase
    .from("drivers")
    .select("id")
    .eq("user_id", uid)
    .single();

  if (driverErr || !driverRow) {
    return json({ error: "Driver profile not found" }, 404);
  }
  const driverId = driverRow.id as string;

  // Fetch the delivery request — must be searching_driver and unassigned
  const { data: deliveryReq, error: reqErr } = await supabase
    .from("package_delivery_requests")
    .select("id, delivery_status, driver_id")
    .eq("id", delivery_request_id)
    .single();

  if (reqErr || !deliveryReq) {
    return json({ error: "Delivery request not found" }, 404);
  }
  if (deliveryReq.delivery_status !== "searching_driver") {
    return json({
      error: `Request is no longer available (status: ${deliveryReq.delivery_status})`,
    }, 409);
  }
  if (deliveryReq.driver_id) {
    return json({ error: "Request already accepted by another driver" }, 409);
  }

  const now = new Date().toISOString();

  // Atomic accept: assign driver + advance to driver_assigned
  const { data: updated, error: updateErr } = await supabase
    .from("package_delivery_requests")
    .update({
      driver_id: driverId,
      delivery_status: "driver_assigned",
      accepted_at: now,
      updated_at: now,
    })
    .eq("id", delivery_request_id)
    .eq("delivery_status", "searching_driver") // guard against race
    .is("driver_id", null)
    .select()
    .single();

  if (updateErr || !updated) {
    return json({ error: "Could not accept — request may have just been taken" }, 409);
  }

  return json({ delivery_request: updated }, 200);
});

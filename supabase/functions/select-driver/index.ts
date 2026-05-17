// Customer selects a specific driver from the list of offers.
// Sets the chosen driver_request to 'accepted' (triggers DB assignment trigger),
// expires all other pending/offered requests for the same ride.

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(h: (r: Request) => Response | Promise<Response>): void; };

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing authorization header" }, 401);

  const token = authHeader.replace(/^Bearer\s+/i, "");
  let customerId: string;
  try {
    const payload = JSON.parse(atob(token.split(".")[1]));
    customerId = payload.sub as string;
    if (!customerId) throw new Error("no sub");
  } catch {
    return json({ error: "Invalid token" }, 401);
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
  );

  let body: { ride_id: string; driver_request_id: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const { ride_id, driver_request_id } = body;
  if (!ride_id || !driver_request_id) {
    return json({ error: "ride_id and driver_request_id are required" }, 400);
  }

  // Verify the ride belongs to this customer and is still searching
  const { data: ride, error: rideErr } = await supabase
    .from("ride_requests")
    .select("id, customer_id, ride_status, driver_id")
    .eq("id", ride_id)
    .single();

  if (rideErr || !ride) return json({ error: "Ride not found" }, 404);
  if (ride.customer_id !== customerId) return json({ error: "Not your ride" }, 403);
  if (ride.ride_status !== "searching_driver") {
    return json({ error: "Ride is no longer searching", ride_status: ride.ride_status }, 409);
  }

  // Verify the driver_request belongs to this ride and is in 'offered' state
  const { data: driverReq, error: drErr } = await supabase
    .from("ride_driver_requests")
    .select("id, ride_id, driver_id, status")
    .eq("id", driver_request_id)
    .eq("ride_id", ride_id)
    .single();

  if (drErr || !driverReq) return json({ error: "Driver request not found" }, 404);
  if (driverReq.status !== "offered" && driverReq.status !== "accepted") {
    return json({ error: "Driver is no longer available", status: driverReq.status }, 409);
  }

  const now = new Date().toISOString();

  // 1. Set selected request to 'accepted' — fires the DB trigger which assigns the driver
  const { error: acceptErr } = await supabase
    .from("ride_driver_requests")
    .update({ status: "accepted", responded_at: now })
    .eq("id", driver_request_id);

  if (acceptErr) return json({ error: "Failed to confirm driver" }, 500);

  // 2. Expire all other pending/offered requests for this ride
  await supabase
    .from("ride_driver_requests")
    .update({ status: "expired" })
    .eq("ride_id", ride_id)
    .neq("id", driver_request_id)
    .in("status", ["pending", "offered"]);

  // 3. The DB trigger should have assigned the driver. Fetch updated ride.
  const { data: updatedRide } = await supabase
    .from("ride_requests")
    .select("id, ride_status, driver_id")
    .eq("id", ride_id)
    .single();

  return json({
    success: true,
    ride_id,
    driver_id: driverReq.driver_id,
    ride_status: updatedRide?.ride_status ?? "driver_assigned",
  });
});

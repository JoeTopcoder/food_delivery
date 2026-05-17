// confirm-package-pickup: validates barcode/QR scan at warehouse before pickup.
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

  let body: {
    delivery_request_id: string;
    scanned_barcode: string;
    scan_image_url?: string;
  };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }

  const { delivery_request_id, scanned_barcode, scan_image_url } = body;
  if (!delivery_request_id || !scanned_barcode) {
    return json({ error: "delivery_request_id and scanned_barcode required" }, 400);
  }

  // Load delivery request + package record
  const { data: deliveryReq, error: reqErr } = await supabase
    .from("package_delivery_requests")
    .select("*, package_records(barcode_data, tracking_number), drivers!package_delivery_requests_driver_id_fkey(id, user_id)")
    .eq("id", delivery_request_id)
    .single();

  if (reqErr || !deliveryReq) return json({ error: "Delivery request not found" }, 404);

  // Verify caller is the assigned driver
  const driver = deliveryReq.drivers as { id: string; user_id: string } | null;
  if (!driver || driver.user_id !== uid) {
    return json({ error: "Only the assigned driver can confirm pickup" }, 403);
  }

  if (deliveryReq.delivery_status !== "driver_at_warehouse") {
    return json({
      error: `Cannot confirm pickup in status: ${deliveryReq.delivery_status}. Driver must be at warehouse.`,
    }, 422);
  }

  // Validate barcode
  const pkg = deliveryReq.package_records as { barcode_data: string | null; tracking_number: string };
  const expectedBarcode = pkg.barcode_data ?? pkg.tracking_number;
  const isValid = scanned_barcode.trim().toUpperCase() === expectedBarcode.trim().toUpperCase();

  // Record scan (valid or invalid)
  await supabase
    .from("package_scans")
    .insert({
      delivery_request_id,
      driver_id: driver.id,
      scan_type: "pickup_scan",
      barcode_data: scanned_barcode,
      is_valid: isValid,
      scan_image_url: scan_image_url ?? null,
    });

  if (!isValid) {
    return json({
      error: "Barcode mismatch. Ensure you are scanning the correct package.",
      expected_hint: expectedBarcode.slice(0, 3) + "***",
      is_valid: false,
    }, 422);
  }

  // Advance status to package_picked_up
  const now = new Date().toISOString();
  const { data: updated, error: updateErr } = await supabase
    .from("package_delivery_requests")
    .update({
      delivery_status: "package_picked_up",
      picked_up_at: now,
      updated_at: now,
    })
    .eq("id", delivery_request_id)
    .select()
    .single();

  if (updateErr) return json({ error: "Failed to update status", details: updateErr.message }, 500);

  // Sync package record
  await supabase
    .from("package_records")
    .update({ package_status: "picked_up", updated_at: now })
    .eq("id", deliveryReq.package_record_id);

  return json({ is_valid: true, delivery_request: updated });
});

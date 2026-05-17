// complete-package-delivery: confirms delivery, captures payment, updates all records.
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
    scanned_barcode?: string;
    scan_image_url?: string;
    rating?: number;
    review?: string;
  };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }

  const { delivery_request_id, scanned_barcode, scan_image_url, rating, review } = body;
  if (!delivery_request_id) {
    return json({ error: "delivery_request_id required" }, 400);
  }

  // Load delivery request
  const { data: deliveryReq, error: reqErr } = await supabase
    .from("package_delivery_requests")
    .select("*, package_records(barcode_data, tracking_number), drivers!package_delivery_requests_driver_id_fkey(id, user_id)")
    .eq("id", delivery_request_id)
    .single();

  if (reqErr || !deliveryReq) return json({ error: "Delivery request not found" }, 404);

  const driver = deliveryReq.drivers as { id: string; user_id: string } | null;

  // Caller must be the assigned driver or admin
  const { data: userRow } = await supabase.from("users").select("role").eq("id", uid).single();
  const isAdmin = userRow?.role === "admin";
  const isDriver = driver?.user_id === uid;

  if (!isDriver && !isAdmin) {
    return json({ error: "Only the assigned driver can complete delivery" }, 403);
  }

  const allowedFromStatuses = ["arriving_destination", "in_transit", "package_picked_up"];
  if (!allowedFromStatuses.includes(deliveryReq.delivery_status)) {
    return json({
      error: `Cannot complete delivery in status: ${deliveryReq.delivery_status}`,
    }, 422);
  }

  // Optional dropoff scan
  if (scanned_barcode && driver) {
    const pkg = deliveryReq.package_records as { barcode_data: string | null; tracking_number: string };
    const expectedBarcode = pkg.barcode_data ?? pkg.tracking_number;
    const isValid = scanned_barcode.trim().toUpperCase() === expectedBarcode.trim().toUpperCase();

    await supabase
      .from("package_scans")
      .insert({
        delivery_request_id,
        driver_id: driver.id,
        scan_type: "dropoff_scan",
        barcode_data: scanned_barcode,
        is_valid: isValid,
        scan_image_url: scan_image_url ?? null,
      });
  }

  const now = new Date().toISOString();

  // Mark delivered
  const { data: updated, error: updateErr } = await supabase
    .from("package_delivery_requests")
    .update({
      delivery_status: "delivered",
      payment_status: deliveryReq.payment_method === "cash" ? "paid" : deliveryReq.payment_status,
      delivered_at: now,
      updated_at: now,
    })
    .eq("id", delivery_request_id)
    .select()
    .single();

  if (updateErr) return json({ error: "Failed to complete delivery", details: updateErr.message }, 500);

  // Sync package record
  await supabase
    .from("package_records")
    .update({ package_status: "delivered", updated_at: now })
    .eq("id", deliveryReq.package_record_id);

  // Capture Stripe payment intent if card payment
  if (
    deliveryReq.payment_method === "card" &&
    deliveryReq.stripe_payment_intent_id &&
    deliveryReq.payment_status === "authorized"
  ) {
    const stripeKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (stripeKey) {
      try {
        await fetch(
          `https://api.stripe.com/v1/payment_intents/${deliveryReq.stripe_payment_intent_id}/capture`,
          {
            method: "POST",
            headers: {
              Authorization: `Bearer ${stripeKey}`,
              "Content-Type": "application/x-www-form-urlencoded",
            },
          },
        );
        await supabase
          .from("package_delivery_requests")
          .update({ payment_status: "paid", updated_at: now })
          .eq("id", delivery_request_id);
      } catch (_) { /* non-fatal — finance team reconciles */ }
    }
  }

  return json({
    success: true,
    delivery_request: updated,
    earnings: deliveryReq.driver_earning,
  });
});

// create-package-delivery: creates a package_delivery_request after payment auth.
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

function haversineKm(lat1: number, lng1: number, lat2: number, lng2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLng = (lng2 - lng1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLng / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
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
    package_record_id: string;
    shipping_company_id: string;
    payment_method: "card" | "cash" | "wallet";
    saved_card_id?: string;
    stripe_payment_intent_id?: string;
    delivery_fee: number;
    platform_fee: number;
    driver_earning: number;
  };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }

  const {
    package_record_id,
    shipping_company_id,
    payment_method,
    saved_card_id,
    stripe_payment_intent_id,
    delivery_fee,
    platform_fee,
    driver_earning,
  } = body;

  if (!package_record_id || !shipping_company_id || !payment_method) {
    return json({ error: "package_record_id, shipping_company_id, payment_method required" }, 400);
  }

  // Verify package exists and is available
  const { data: pkg, error: pkgErr } = await supabase
    .from("package_records")
    .select("*, shipping_companies(warehouse_address, warehouse_lat, warehouse_lng)")
    .eq("id", package_record_id)
    .single();

  if (pkgErr || !pkg) return json({ error: "Package not found" }, 404);
  if (!pkg.verified) return json({ error: "Package is not verified" }, 400);
  if (pkg.package_status === "delivered") return json({ error: "Package already delivered" }, 409);
  if (pkg.package_status === "picked_up") return json({ error: "Package already picked up" }, 409);

  // Check no active delivery already exists
  const { data: existing } = await supabase
    .from("package_delivery_requests")
    .select("id")
    .eq("package_record_id", package_record_id)
    .not("delivery_status", "in", '("cancelled","failed","delivered")')
    .limit(1);

  if (existing && existing.length > 0) {
    return json({ error: "Active delivery request already exists", existing_request_id: existing[0].id }, 409);
  }

  // Get customer user record
  const { data: user } = await supabase
    .from("users")
    .select("id")
    .eq("id", uid)
    .single();

  if (!user) return json({ error: "User not found" }, 404);

  const company = pkg.shipping_companies as {
    warehouse_address: string;
    warehouse_lat: number;
    warehouse_lng: number;
  };

  const distanceKm = haversineKm(
    Number(company.warehouse_lat),
    Number(company.warehouse_lng),
    Number(pkg.delivery_lat),
    Number(pkg.delivery_lng),
  );
  const durationMinutes = Math.round((distanceKm / 35) * 60);

  const paymentStatus = payment_method === "cash" ? "pending" : "authorized";
  const deliveryStatus = payment_method === "cash" ? "searching_driver" : "searching_driver";

  const { data: deliveryReq, error: createErr } = await supabase
    .from("package_delivery_requests")
    .insert({
      package_record_id,
      customer_id: uid,
      shipping_company_id,
      pickup_address: company.warehouse_address,
      pickup_lat: company.warehouse_lat,
      pickup_lng: company.warehouse_lng,
      destination_address: pkg.delivery_address,
      destination_lat: pkg.delivery_lat,
      destination_lng: pkg.delivery_lng,
      estimated_distance_km: Math.round(distanceKm * 100) / 100,
      estimated_duration_minutes: durationMinutes,
      delivery_fee,
      platform_fee,
      driver_earning,
      payment_method,
      payment_status: paymentStatus,
      saved_card_id: saved_card_id ?? null,
      stripe_payment_intent_id: stripe_payment_intent_id ?? null,
      delivery_status: deliveryStatus,
    })
    .select()
    .single();

  if (createErr || !deliveryReq) {
    return json({ error: "Failed to create delivery request", details: createErr?.message }, 500);
  }

  // Update package status to ready_for_pickup
  await supabase
    .from("package_records")
    .update({ package_status: "ready_for_pickup", updated_at: new Date().toISOString() })
    .eq("id", package_record_id);

  return json({ delivery_request: deliveryReq }, 201);
});

// verify-package: looks up a package record by shipping company + tracking number.
// Deployed with --no-verify-jwt (gateway skips JWT check; we decode manually).
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

  let body: { shipping_company_id: string; tracking_number: string };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }

  const { shipping_company_id, tracking_number } = body;
  if (!shipping_company_id || !tracking_number) {
    return json({ error: "shipping_company_id and tracking_number required" }, 400);
  }

  // Fetch shipping company
  const { data: company, error: companyErr } = await supabase
    .from("shipping_companies")
    .select("id, name, warehouse_address, warehouse_lat, warehouse_lng, active, verification_type")
    .eq("id", shipping_company_id)
    .single();

  if (companyErr || !company) return json({ error: "Shipping company not found" }, 404);
  if (!company.active) return json({ error: "Shipping company is not active" }, 400);

  // Fetch package record
  const { data: pkg, error: pkgErr } = await supabase
    .from("package_records")
    .select("*")
    .eq("shipping_company_id", shipping_company_id)
    .ilike("tracking_number", tracking_number.trim())
    .single();

  if (pkgErr || !pkg) {
    return json({ error: "Package not found. Check the tracking number and try again." }, 404);
  }

  if (pkg.package_status === "delivered") {
    return json({ error: "This package has already been delivered." }, 409);
  }
  if (pkg.package_status === "picked_up") {
    return json({ error: "This package is already out for delivery." }, 409);
  }
  if (!pkg.verified) {
    return json({ error: "Package not yet cleared for delivery. Please contact the shipping company." }, 400);
  }

  // Check if there's already an active delivery request for this package
  const { data: existingReq } = await supabase
    .from("package_delivery_requests")
    .select("id, delivery_status")
    .eq("package_record_id", pkg.id)
    .not("delivery_status", "in", '("cancelled","failed","delivered")')
    .limit(1);

  if (existingReq && existingReq.length > 0) {
    return json({ error: "A delivery request for this package is already active.", existing_request_id: existingReq[0].id }, 409);
  }

  return json({
    package: {
      id: pkg.id,
      tracking_number: pkg.tracking_number,
      customer_name: pkg.customer_name,
      customer_phone: pkg.customer_phone,
      warehouse_location: pkg.warehouse_location ?? company.warehouse_address,
      delivery_address: pkg.delivery_address,
      delivery_lat: pkg.delivery_lat,
      delivery_lng: pkg.delivery_lng,
      package_weight: pkg.package_weight,
      package_type: pkg.package_type,
      package_value: pkg.package_value,
      barcode_data: pkg.barcode_data,
      package_status: pkg.package_status,
      verified: pkg.verified,
      notes: pkg.notes,
    },
    company: {
      id: company.id,
      name: company.name,
      warehouse_address: company.warehouse_address,
      warehouse_lat: company.warehouse_lat,
      warehouse_lng: company.warehouse_lng,
    },
  });
});

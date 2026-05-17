// fetch-tracking-number
// Customer enters a tracking number → backend calls the selected shipping
// company's external API (e.g. Applizone at courier.shipavecorp.com/rpc)
// to fetch real package data → saves/updates package_records → returned to Flutter.
//
// KEY DESIGN:
//   The package may NOT exist in our DB yet. We call the external API FIRST,
//   then create/update the package_record. The tracking number = the key.
//
// Deployed with --no-verify-jwt (JWT decoded manually).

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function decodeUserId(authHeader: string | null): string | null {
  if (!authHeader) return null;
  try {
    const token = authHeader.replace(/^Bearer\s+/i, "");
    const payload = JSON.parse(atob(token.split(".")[1]));
    return (payload.sub as string) ?? null;
  } catch {
    return null;
  }
}

/** Try multiple key name variants; return first non-empty value found. */
function pick(obj: unknown, ...keys: string[]): string | null {
  if (!obj || typeof obj !== "object") return null;
  const o = obj as Record<string, unknown>;
  for (const k of keys) {
    const v = o[k];
    if (v !== null && v !== undefined && String(v).trim().length > 0)
      return String(v).trim();
  }
  return null;
}

function pickNum(obj: unknown, ...keys: string[]): number | null {
  if (!obj || typeof obj !== "object") return null;
  const o = obj as Record<string, unknown>;
  for (const k of keys) {
    const v = o[k];
    if (v !== null && v !== undefined) {
      const n = Number(v);
      if (!isNaN(n)) return n;
    }
  }
  return null;
}

/** Extract a nested sub-object by trying common key names. */
function nested(root: Record<string, unknown>, ...keys: string[]): Record<string, unknown> | null {
  for (const k of keys) {
    const v = root[k];
    if (v && typeof v === "object" && !Array.isArray(v))
      return v as Record<string, unknown>;
  }
  return null;
}

// ── Call the shipping company's external API ──────────────────────────────────

/** Derive the best endpoint URL for tracking.
 *  If the stored endpoint is the bare health-check root (/rpc returns "ware-api v1.5"),
 *  we automatically promote it to the real packages endpoint. */
function resolveTrackingEndpoint(rawEndpoint: string): string {
  const url = new URL(rawEndpoint);
  // /rpc on courier.shipavecorp.com is a health check, not a tracking endpoint
  if (url.pathname === "/rpc" || url.pathname === "/rpc/") {
    url.pathname = "/api/packages";
    return url.toString();
  }
  return rawEndpoint;
}

async function callShippingApi(
  apiEndpoint: string,
  apiKey: string,
  trackingNumber: string,
): Promise<Record<string, unknown>> {
  const endpoint = resolveTrackingEndpoint(apiEndpoint);
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 20_000);

  const body = JSON.stringify({
    tracking_number: trackingNumber,
    number: trackingNumber,
    waybill: trackingNumber,
    awb: trackingNumber,
    api_key: apiKey,
  });

  try {
    // Attempt 1: Bearer token (standard JWT pattern)
    const res1 = await fetch(endpoint, {
      method: "POST",
      signal: controller.signal,
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${apiKey}`,
        "X-API-Key": apiKey,
      },
      body,
    });

    if (res1.ok) {
      const ct = res1.headers.get("content-type") ?? "";
      if (ct.includes("application/json")) {
        return (await res1.json()) as Record<string, unknown>;
      }
      const text = await res1.text();
      if (text.startsWith("{") || text.startsWith("[")) {
        return JSON.parse(text) as Record<string, unknown>;
      }
      // Healthcheck-style plain text response — endpoint is wrong
      if (text.trim().startsWith("ware-api") || text.trim().length < 50) {
        throw new Error(
          `API endpoint (${endpoint}) returned a health-check response, not package data. ` +
          `Please update the API endpoint in the Applizone shipping company settings.`
        );
      }
      throw new Error(`API returned unexpected non-JSON response: ${text.slice(0, 200)}`);
    }

    // 405 = POST not allowed, try GET with query params
    if (res1.status === 405) {
      const getUrl = new URL(endpoint);
      getUrl.searchParams.set("tracking_number", trackingNumber);
      getUrl.searchParams.set("api_key", apiKey);
      const res2 = await fetch(getUrl.toString(), {
        method: "GET",
        signal: controller.signal,
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "X-API-Key": apiKey,
        },
      });
      if (res2.ok) {
        const ct = res2.headers.get("content-type") ?? "";
        if (ct.includes("application/json")) {
          return (await res2.json()) as Record<string, unknown>;
        }
        const text = await res2.text();
        if (text.trim().startsWith("ware-api") || text.trim().length < 50) {
          throw new Error(
            `API endpoint (${getUrl.toString()}) returned a health-check response. ` +
            `Please update the API endpoint in Applizone shipping company settings to the full tracking URL.`
          );
        }
        throw new Error(`API returned unexpected response: ${text.slice(0, 200)}`);
      }
      const errText = await res2.text().catch(() => "");
      throw new Error(`Shipping API error ${res2.status}: ${errText.slice(0, 300)}`);
    }

    // Auth failure — return specific guidance
    if (res1.status === 401 || res1.status === 403 || res1.status === 500) {
      const errText = await res1.text().catch(() => "");
      const errJson = (() => { try { return JSON.parse(errText); } catch { return null; } })();
      const msg = errJson?.message ?? errJson?.error ?? errText;
      if (typeof msg === "string" && (msg.includes("token") || msg.includes("auth") || msg.includes("unauthorized"))) {
        throw new Error(
          `Applizone API authentication failed: "${msg}". ` +
          `The API key stored for Applizone Shipping may need to be a service/session token rather than a public key. ` +
          `Please contact Applizone to get the correct server-side API credentials.`
        );
      }
      throw new Error(`Shipping API error ${res1.status}: ${msg?.toString().slice(0, 300)}`);
    }

    const errText = await res1.text().catch(() => "");
    throw new Error(`Shipping API error ${res1.status}: ${errText.slice(0, 300)}`);
  } finally {
    clearTimeout(timeout);
  }
}

/** Parse the external API response into our package_record shape. */
function parseApiResponse(
  root: Record<string, unknown>,
  trackingNumber: string,
): {
  customerName: string | null;
  customerPhone: string | null;
  deliveryAddress: string | null;
  deliveryLat: number | null;
  deliveryLng: number | null;
  packageType: string | null;
  packageWeight: number | null;
  packageValue: number | null;
  packageStatus: string;
  notes: string | null;
  trackingUrl: string | null;
  externalShipmentId: string | null;
  barcodeData: string | null;
} {
  // The API may nest data in sub-objects — check common nesting patterns
  const data = nested(root, "data", "result", "payload") ?? root;
  const recipientObj = nested(data, "recipient", "receiver", "consignee", "customer", "to") ?? data;
  const pkgObj = nested(data, "package", "parcel", "item", "shipment") ?? data;
  const locationObj = nested(data, "destination", "delivery_location", "location") ?? null;

  // ── Recipient info ──────────────────────────────────────────────────────────
  const customerName = pick(
    recipientObj,
    "name", "full_name", "fullName", "recipient_name", "receiverName",
    "customer_name", "consignee_name",
  ) ?? pick(data, "name", "customer_name", "recipient_name");

  const customerPhone = pick(
    recipientObj,
    "phone", "phone_number", "phoneNumber", "mobile", "contact",
    "customer_phone", "receiver_phone",
  ) ?? pick(data, "phone", "customer_phone", "mobile");

  const deliveryAddress = pick(
    recipientObj,
    "address", "full_address", "fullAddress", "street_address", "delivery_address",
  ) ?? pick(locationObj ?? data, "address", "delivery_address", "street");

  // ── Coordinates ─────────────────────────────────────────────────────────────
  const deliveryLat =
    pickNum(locationObj ?? recipientObj ?? data, "lat", "latitude") ??
    pickNum(data, "delivery_lat", "dest_lat");
  const deliveryLng =
    pickNum(locationObj ?? recipientObj ?? data, "lng", "lon", "longitude") ??
    pickNum(data, "delivery_lng", "dest_lng");

  // ── Package attributes ──────────────────────────────────────────────────────
  const packageType = pick(
    pkgObj,
    "type", "package_type", "parcel_type", "size", "category",
  ) ?? pick(data, "package_type", "type");

  const packageWeight = pickNum(
    pkgObj,
    "weight", "package_weight", "weight_kg",
  ) ?? pickNum(data, "weight", "package_weight");

  const packageValue = pickNum(
    pkgObj,
    "value", "declared_value", "insurance_value",
  ) ?? pickNum(data, "value", "declared_value");

  const notes = pick(data, "notes", "note", "remarks", "special_instructions", "description");

  // ── Tracking metadata ───────────────────────────────────────────────────────
  const trackingUrl = pick(
    root,
    "tracking_url", "trackingUrl", "track_url", "tracking_link",
  ) ?? pick(data, "tracking_url", "trackingUrl");

  const externalShipmentId = pick(
    root,
    "shipment_id", "shipmentId", "id", "external_id", "awb_id",
  ) ?? pick(data, "shipment_id", "id", "awb");

  const barcodeData = pick(data, "barcode", "barcode_data", "qr_code", "scan_code");

  // ── Package status mapping ──────────────────────────────────────────────────
  const rawStatus = (
    pick(data, "status", "package_status", "delivery_status", "shipment_status") ?? ""
  ).toLowerCase();

  let packageStatus = "at_warehouse";
  if (rawStatus.includes("deliver") && rawStatus.includes("complet")) packageStatus = "delivered";
  else if (rawStatus.includes("pickup") || rawStatus.includes("picked") || rawStatus.includes("transit")) packageStatus = "picked_up";
  else if (rawStatus.includes("warehouse") || rawStatus.includes("received") || rawStatus.includes("arrived")) packageStatus = "at_warehouse";
  else if (rawStatus.includes("pending") || rawStatus.includes("processing")) packageStatus = "at_warehouse";

  return {
    customerName,
    customerPhone,
    deliveryAddress,
    deliveryLat,
    deliveryLng,
    packageType: packageType ?? "small",
    packageWeight,
    packageValue,
    packageStatus,
    notes,
    trackingUrl,
    externalShipmentId: externalShipmentId ?? pick(root, "shipment_id", "id"),
    barcodeData,
  };
}

// ── Main ──────────────────────────────────────────────────────────────────────

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const uid = decodeUserId(req.headers.get("Authorization"));
  if (!uid) return json({ error: "Unauthorized" }, 401);

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // ── Parse body ──────────────────────────────────────────────────────────────
  let body: {
    shipping_company_id?: string;
    tracking_number?: string;
    package_record_id?: string;
  };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const { shipping_company_id, tracking_number, package_record_id } = body;

  if (!shipping_company_id) return json({ error: "shipping_company_id is required" }, 400);
  if (!tracking_number && !package_record_id) {
    return json({ error: "tracking_number is required" }, 400);
  }

  const trackingNum = tracking_number?.trim() ?? "";

  // ── Caller profile ──────────────────────────────────────────────────────────
  const { data: caller } = await supabase
    .from("users")
    .select("id, role, phone, name")
    .eq("id", uid)
    .single();

  if (!caller) return json({ error: "User profile not found" }, 401);
  const isAdmin = caller.role === "admin";

  // ── Shipping company + credentials ──────────────────────────────────────────
  const { data: company } = await supabase
    .from("shipping_companies")
    .select("id, name, verification_type, api_endpoint, api_key, webhook_endpoint, warehouse_address, warehouse_lat, warehouse_lng, active")
    .eq("id", shipping_company_id)
    .single();

  if (!company) return json({ error: "Shipping company not found" }, 404);
  if (!company.active) return json({ error: "Shipping company is not active" }, 400);

  // ── Step 1: Call the external shipping company API to get package data ───────
  // This is the PRIMARY data source. The package may not exist in our DB yet.
  let apiData: Record<string, unknown> | null = null;
  let apiError: string | null = null;

  if (
    company.verification_type === "api" &&
    company.api_endpoint &&
    company.api_key
  ) {
    try {
      apiData = await callShippingApi(
        company.api_endpoint,
        company.api_key,
        trackingNum || (package_record_id ?? ""),
      );
    } catch (err: unknown) {
      apiError = err instanceof Error ? err.message : String(err);
    }
  }

  // ── Step 2: Check if we already have this package in our DB ─────────────────
  let existingPkg: Record<string, unknown> | null = null;

  if (package_record_id) {
    const { data } = await supabase
      .from("package_records")
      .select("*")
      .eq("id", package_record_id)
      .eq("shipping_company_id", shipping_company_id)
      .single();
    existingPkg = data;
  } else if (trackingNum) {
    // Try uppercase then as-entered
    const { data: d1 } = await supabase
      .from("package_records")
      .select("*")
      .eq("shipping_company_id", shipping_company_id)
      .eq("tracking_number", trackingNum.toUpperCase())
      .maybeSingle();

    if (d1) {
      existingPkg = d1;
    } else {
      const { data: d2 } = await supabase
        .from("package_records")
        .select("*")
        .eq("shipping_company_id", shipping_company_id)
        .eq("tracking_number", trackingNum)
        .maybeSingle();
      existingPkg = d2;
    }
  }

  // ── Step 3: If API returned data, parse it and upsert the package record ─────
  const now = new Date().toISOString();

  if (apiData) {
    const parsed = parseApiResponse(apiData, trackingNum);
    const trackingStatus = apiError ? "tracking_error" : "tracking_active";

    if (existingPkg) {
      // Update existing record with fresh data from API
      const updatePayload: Record<string, unknown> = {
        tracking_status: trackingStatus,
        tracking_last_synced_at: now,
        tracking_error_message: null,
        updated_at: now,
        verified: true, // If API returned it, it's real — mark as verified
      };
      if (parsed.trackingUrl) updatePayload["tracking_url"] = parsed.trackingUrl;
      if (parsed.externalShipmentId) updatePayload["external_shipment_id"] = parsed.externalShipmentId;
      if (parsed.customerName) updatePayload["customer_name"] = parsed.customerName;
      if (parsed.customerPhone) updatePayload["customer_phone"] = parsed.customerPhone;
      if (parsed.deliveryAddress) updatePayload["delivery_address"] = parsed.deliveryAddress;
      if (parsed.deliveryLat != null) updatePayload["delivery_lat"] = parsed.deliveryLat;
      if (parsed.deliveryLng != null) updatePayload["delivery_lng"] = parsed.deliveryLng;
      if (parsed.packageType) updatePayload["package_type"] = parsed.packageType;
      if (parsed.packageWeight != null) updatePayload["package_weight"] = parsed.packageWeight;
      if (parsed.notes) updatePayload["notes"] = parsed.notes;

      // Auto-link to customer if unclaimed
      if (!existingPkg["customer_id"]) updatePayload["customer_id"] = uid;

      const { data: updated, error: updateErr } = await supabase
        .from("package_records")
        .update(updatePayload)
        .eq("id", existingPkg["id"] as string)
        .select("*")
        .single();

      if (!updateErr && updated) existingPkg = updated;
    } else {
      // CREATE a new package record from the API data
      const insertPayload: Record<string, unknown> = {
        shipping_company_id,
        tracking_number: trackingNum,
        customer_id: uid, // link to the searching customer
        customer_name: parsed.customerName ?? "Unknown",
        customer_phone: parsed.customerPhone ?? "",
        delivery_address: parsed.deliveryAddress ?? "",
        delivery_lat: parsed.deliveryLat,
        delivery_lng: parsed.deliveryLng,
        package_type: parsed.packageType ?? "small",
        package_weight: parsed.packageWeight,
        package_value: parsed.packageValue,
        package_status: parsed.packageStatus,
        notes: parsed.notes,
        barcode_data: parsed.barcodeData,
        tracking_url: parsed.trackingUrl,
        external_shipment_id: parsed.externalShipmentId,
        tracking_status: trackingStatus,
        tracking_last_synced_at: now,
        tracking_error_message: null,
        verified: true, // If the external API returned it, it's a real package
        created_at: now,
        updated_at: now,
      };

      const { data: inserted, error: insertErr } = await supabase
        .from("package_records")
        .insert(insertPayload)
        .select("*")
        .single();

      if (insertErr) {
        return json({
          error: "Package found via API but could not be saved: " + insertErr.message,
          api_error: apiError,
        }, 500);
      }
      existingPkg = inserted;
    }
  } else if (!existingPkg) {
    // API call failed (or no API) AND package not in our DB either
    const errMsg = apiError
      ? `Could not reach ${company.name} API: ${apiError}`
      : `Tracking number not found at ${company.name}. Please check and try again.`;
    return json({ error: errMsg }, 404);
  }

  // existingPkg is guaranteed non-null from here
  const pkg = existingPkg!;

  // ── Step 4: Ownership check ──────────────────────────────────────────────────
  if (!isAdmin) {
    const ownerId = pkg["customer_id"] as string | null;
    const ownedById = ownerId === uid;
    const ownedByPhone = caller.phone && caller.phone === pkg["customer_phone"];
    const unclaimed = !ownerId;
    if (!ownedById && !ownedByPhone && !unclaimed) {
      return json({ error: "This package does not belong to your account" }, 403);
    }
  }

  // ── Step 5: Package state validation ────────────────────────────────────────
  if (pkg["package_status"] === "delivered") {
    return json({ error: "This package has already been delivered." }, 409);
  }
  if (pkg["package_status"] === "picked_up") {
    return json({ error: "This package is already out for delivery." }, 409);
  }
  if (!pkg["verified"]) {
    return json({
      error:
        "This package has not been cleared for delivery yet. " +
        `Contact ${company.name} to verify it.`,
    }, 400);
  }

  // ── Step 6: Check for existing active delivery request ──────────────────────
  const { data: existingReq } = await supabase
    .from("package_delivery_requests")
    .select("id, delivery_status")
    .eq("package_record_id", pkg["id"] as string)
    .not("delivery_status", "in", '("cancelled","failed","delivered")')
    .limit(1);

  if (existingReq && existingReq.length > 0) {
    return json({
      error: "A delivery request for this package is already active.",
      existing_request_id: existingReq[0].id,
    }, 409);
  }

  // ── Return ───────────────────────────────────────────────────────────────────
  return json({
    success: true,
    tracking_number: pkg["tracking_number"],
    tracking_url: pkg["tracking_url"] ?? null,
    external_shipment_id: pkg["external_shipment_id"] ?? null,
    tracking_status: pkg["tracking_status"],
    tracking_last_synced_at: pkg["tracking_last_synced_at"],
    api_error: apiError,
    package: {
      id: pkg["id"],
      tracking_number: pkg["tracking_number"],
      customer_name: pkg["customer_name"],
      customer_phone: pkg["customer_phone"],
      warehouse_location: pkg["warehouse_location"] ?? company.warehouse_address,
      delivery_address: pkg["delivery_address"],
      delivery_lat: pkg["delivery_lat"],
      delivery_lng: pkg["delivery_lng"],
      package_weight: pkg["package_weight"],
      package_type: pkg["package_type"],
      package_value: pkg["package_value"],
      barcode_data: pkg["barcode_data"],
      package_status: pkg["package_status"],
      verified: pkg["verified"],
      notes: pkg["notes"],
      tracking_url: pkg["tracking_url"],
      external_shipment_id: pkg["external_shipment_id"],
      tracking_status: pkg["tracking_status"],
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

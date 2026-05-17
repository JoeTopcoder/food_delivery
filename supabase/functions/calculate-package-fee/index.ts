// calculate-package-fee: computes delivery fee based on distance + package type.
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

// Fee configuration (JMD)
const BASE_FEE = 500;           // base fee in JMD
const PER_KM_RATE = 80;         // per km in JMD
const PLATFORM_FEE_PCT = 0.15;  // 15% platform fee

const PACKAGE_TYPE_SURCHARGE: Record<string, number> = {
  small: 0,
  medium: 100,
  large: 250,
  fragile: 300,
  document: 0,
  electronics: 350,
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const uid = userId(req.headers.get("Authorization"));
  if (!uid) return json({ error: "Unauthorized" }, 401);

  let body: {
    pickup_lat: number;
    pickup_lng: number;
    destination_lat: number;
    destination_lng: number;
    package_type: string;
    package_weight?: number;
  };
  try { body = await req.json(); }
  catch { return json({ error: "Invalid JSON" }, 400); }

  const { pickup_lat, pickup_lng, destination_lat, destination_lng, package_type, package_weight } = body;

  if (
    pickup_lat == null || pickup_lng == null ||
    destination_lat == null || destination_lng == null ||
    !package_type
  ) {
    return json({ error: "pickup_lat, pickup_lng, destination_lat, destination_lng, package_type required" }, 400);
  }

  const distanceKm = haversineKm(pickup_lat, pickup_lng, destination_lat, destination_lng);
  const durationMinutes = Math.round((distanceKm / 35) * 60); // assume 35 km/h avg

  const typeSurcharge = PACKAGE_TYPE_SURCHARGE[package_type] ?? 0;
  const weightSurcharge = package_weight && package_weight > 10
    ? (package_weight - 10) * 50
    : 0;

  const deliveryFeeBase = BASE_FEE + (distanceKm * PER_KM_RATE) + typeSurcharge + weightSurcharge;
  const platformFee = Math.round(deliveryFeeBase * PLATFORM_FEE_PCT);
  const deliveryFee = Math.round(deliveryFeeBase);
  const driverEarning = deliveryFee - platformFee;
  const totalCharge = deliveryFee;

  return json({
    distance_km: Math.round(distanceKm * 100) / 100,
    duration_minutes: durationMinutes,
    delivery_fee: deliveryFee,
    platform_fee: platformFee,
    driver_earning: driverEarning,
    total_charge: totalCharge,
    currency: "JMD",
  });
});

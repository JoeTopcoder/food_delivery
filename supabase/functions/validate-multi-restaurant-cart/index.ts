// validate-multi-restaurant-cart
// Checks: restaurant count limit, each restaurant open, distance between restaurants,
// item availability, delivery address within range.
// Returns: { valid: true } or { valid: false, error: "human-readable message" }
// Deploy: supabase functions deploy validate-multi-restaurant-cart

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

function haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371;
  const dLat = (lat2 - lat1) * Math.PI / 180;
  const dLon = (lon2 - lon1) * Math.PI / 180;
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1 * Math.PI / 180) * Math.cos(lat2 * Math.PI / 180) *
    Math.sin(dLon / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

async function getConfig(key: string, fallback: number): Promise<number> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  return data ? parseFloat(data.value) : fallback;
}

async function getConfigBool(key: string, fallback: boolean): Promise<boolean> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  if (!data) return fallback;
  return data.value === "true" || data.value === "1";
}

interface CartRestaurantGroup {
  restaurant_id: string;
  item_ids: string[];  // menu_item ids to validate availability
}

interface ValidateRequest {
  restaurant_groups: CartRestaurantGroup[];
  delivery_latitude?: number;
  delivery_longitude?: number;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  try {
    const body: ValidateRequest = await req.json();
    const { restaurant_groups, delivery_latitude, delivery_longitude } = body;

    if (!restaurant_groups || restaurant_groups.length === 0) {
      return json({ valid: false, error: "Cart is empty." });
    }

    // ── Feature flag ──────────────────────────────────────────
    const featureEnabled = await getConfigBool("enable_multi_restaurant_orders", true);
    if (!featureEnabled && restaurant_groups.length > 1) {
      return json({ valid: false, error: "Multi-restaurant ordering is not currently available." });
    }

    // ── Restaurant count limit ────────────────────────────────
    const maxRestaurants = await getConfig("max_restaurants_per_order", 2);
    if (restaurant_groups.length > maxRestaurants) {
      return json({
        valid: false,
        error: `You can order from a maximum of ${maxRestaurants} restaurants at once.`,
      });
    }

    const restaurantIds = restaurant_groups.map((g) => g.restaurant_id);

    // ── Fetch restaurant data ─────────────────────────────────
    const { data: restaurants, error: rErr } = await admin
      .from("restaurants")
      .select("id, name, latitude, longitude, is_open, is_verified")
      .in("id", restaurantIds);

    if (rErr || !restaurants) {
      return json({ valid: false, error: "Could not load restaurant information." });
    }

    // ── All restaurants must be open and verified ─────────────
    for (const r of restaurants) {
      if (!r.is_open) {
        return json({ valid: false, error: `${r.name} is currently closed.` });
      }
      if (!r.is_verified) {
        return json({ valid: false, error: `${r.name} is not yet available for orders.` });
      }
    }

    // ── Distance between restaurants must be within limit ─────
    if (restaurants.length > 1) {
      const maxDist = await getConfig("max_restaurants_distance_km", 8.0);
      for (let i = 0; i < restaurants.length; i++) {
        for (let j = i + 1; j < restaurants.length; j++) {
          const a = restaurants[i];
          const b = restaurants[j];
          if (!a.latitude || !a.longitude || !b.latitude || !b.longitude) continue;
          const dist = haversineKm(a.latitude, a.longitude, b.latitude, b.longitude);
          if (dist > maxDist) {
            return json({
              valid: false,
              error: `${a.name} and ${b.name} are too far apart for a single delivery. Please order from one restaurant at a time.`,
            });
          }
        }
      }
    }

    // ── Item availability ─────────────────────────────────────
    const allItemIds = restaurant_groups.flatMap((g) => g.item_ids);
    if (allItemIds.length > 0) {
      const { data: items } = await admin
        .from("menus")
        .select("id, name, is_available")
        .in("id", allItemIds);

      if (items) {
        const unavailable = items.filter((i) => !i.is_available);
        if (unavailable.length > 0) {
          const names = unavailable.map((i) => i.name).join(", ");
          return json({
            valid: false,
            error: `The following items are no longer available: ${names}.`,
          });
        }
      }
    }

    // ── Delivery address within service range ─────────────────
    if (delivery_latitude && delivery_longitude) {
      const maxDeliveryKm = await getConfig("deliveryMaxKm", 30.0);
      for (const r of restaurants) {
        if (!r.latitude || !r.longitude) continue;
        const dist = haversineKm(delivery_latitude, delivery_longitude, r.latitude, r.longitude);
        if (dist > maxDeliveryKm) {
          return json({
            valid: false,
            error: `Your delivery address is outside the service area for ${r.name}.`,
          });
        }
      }
    }

    return json({ valid: true, restaurant_count: restaurants.length });
  } catch (err) {
    return json({ valid: false, error: `Validation error: ${err}` }, 500);
  }
});

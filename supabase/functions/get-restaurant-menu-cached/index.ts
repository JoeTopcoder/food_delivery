// get-restaurant-menu-cached — Cached menu endpoint for a single restaurant
// TTL: 120 seconds.  Cache key: restaurant_id|include_unavailable
//
// Deploy: supabase functions deploy get-restaurant-menu-cached

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl    = Deno.env.get("SUPABASE_URL")     ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const db = createClient(supabaseUrl, supabaseAnonKey);

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200, extra: Record<string, string> = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json", ...extra },
  });
}

// ── In-memory cache (120-second TTL) ─────────────────────────────────────────
const MENU_TTL_MS = 120_000;

interface CacheEntry { data: unknown; expiresAt: number }
const cache = new Map<string, CacheEntry>();

function cacheGet<T>(key: string): T | null {
  const entry = cache.get(key);
  if (!entry || Date.now() > entry.expiresAt) { cache.delete(key); return null; }
  return entry.data as T;
}

function cacheSet(key: string, data: unknown, ttlMs: number) {
  if (cache.size > 1000) {
    const now = Date.now();
    for (const [k, v] of cache) { if (now > v.expiresAt) cache.delete(k); }
  }
  cache.set(key, { data, expiresAt: Date.now() + ttlMs });
}

// Explicit column list — avoids pulling heavy unused fields on list requests.
// Includes sides via join so Flutter can render add-ons without a second call.
const MENU_COLUMNS = [
  "id", "restaurant_id", "name", "description", "price", "category",
  "image_url", "is_available", "discount_percentage", "preparation_time",
  "calories", "is_vegetarian", "is_vegan", "is_gluten_free", "spice_level",
  "menu_item_sides(*)",
  "menu_option_groups(*, menu_option_choices(*))",
].join(", ");

// ── Handler ───────────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET")     return json({ error: "Method not allowed" }, 405);

  const url = new URL(req.url);
  const restaurantId      = url.searchParams.get("restaurant_id") ?? "";
  const includeUnavailable = url.searchParams.get("include_unavailable") === "true";

  if (!restaurantId || restaurantId.length < 10) {
    return json({ success: false, error: "restaurant_id is required" }, 400);
  }

  // Restaurant owners need live data to manage items — skip cache for management calls
  const cacheKey = `menu:${restaurantId}:${includeUnavailable}`;
  const cached = cacheGet<unknown[]>(cacheKey);

  if (cached && !includeUnavailable) {
    return json(
      { success: true, data: cached, count: cached.length, cache_hit: true },
      200,
      { "X-Cache": "HIT", "Cache-Control": "public, max-age=120" },
    );
  }

  try {
    let query = db
      .from("menus")
      .select(MENU_COLUMNS)
      .eq("restaurant_id", restaurantId)
      .order("category");

    if (!includeUnavailable) {
      query = query.eq("is_available", true);
    }

    const { data, error } = await query;

    if (error) {
      console.error("[get-restaurant-menu-cached] DB error:", error.message);
      return json({ success: false, error: "Failed to fetch menu", code: "DB_ERROR" }, 500);
    }

    const rows = data ?? [];

    // Only cache the public (available-only) view
    if (!includeUnavailable) {
      cacheSet(cacheKey, rows, MENU_TTL_MS);
    }

    return json(
      { success: true, data: rows, count: rows.length, cache_hit: false },
      200,
      { "X-Cache": "MISS", "Cache-Control": "public, max-age=120" },
    );
  } catch (err) {
    console.error("[get-restaurant-menu-cached] Unexpected error:", err);
    return json({ success: false, error: "Server error", code: "INTERNAL_ERROR" }, 500);
  }
});

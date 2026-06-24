// get-restaurants-cached — High-performance restaurant browse endpoint
// Uses module-level in-memory cache (survives warm Deno isolate between requests).
// TTL: 60 seconds.  Cache key: page|limit|cuisine|search|store_type
//
// Why in-memory instead of Redis?
//   • No external dependency — works on any Supabase plan
//   • Deno isolates stay warm for minutes, so the cache is effective
//   • Falls back to DB transparently on cold start or cache miss
//   • Redis can be wired in later by replacing fromCache/toCache
//
// Deploy: supabase functions deploy get-restaurants-cached

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
// Use anon key for reads — RLS already limits visibility correctly.
// Service role is NOT needed and would bypass RLS.
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

// ── In-memory cache ───────────────────────────────────────────────────────────
const RESTAURANT_TTL_MS = 60_000; // 60 seconds

interface CacheEntry {
  data: unknown;
  expiresAt: number;
}

const cache = new Map<string, CacheEntry>();

function cacheGet<T>(key: string): T | null {
  const entry = cache.get(key);
  if (!entry || Date.now() > entry.expiresAt) {
    cache.delete(key);
    return null;
  }
  return entry.data as T;
}

function cacheSet(key: string, data: unknown, ttlMs: number) {
  // Evict if cache grows too large (safety valve — shouldn't exceed ~200 keys in practice)
  if (cache.size > 500) {
    const now = Date.now();
    for (const [k, v] of cache) {
      if (now > v.expiresAt) cache.delete(k);
    }
  }
  cache.set(key, { data, expiresAt: Date.now() + ttlMs });
}

// ── Columns returned to Flutter ───────────────────────────────────────────────
// Explicit column list avoids pulling large unused fields (description, etc.)
// on every list request.  Detail screen fetches full row via restaurant ID.
const LIST_COLUMNS = [
  "id", "name", "image_url", "cuisine_type", "rating", "review_count",
  "delivery_fee", "estimated_delivery_time", "is_open", "is_verified",
  "address", "latitude", "longitude", "store_type", "tags",
  "opening_time", "closing_time", "commission_rate",
].join(", ");

// ── Main handler ──────────────────────────────────────────────────────────────
Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "GET") return json({ error: "Method not allowed" }, 405);

  const url = new URL(req.url);
  const page    = Math.max(0, parseInt(url.searchParams.get("page")   ?? "0", 10));
  const limit   = Math.min(50, Math.max(1, parseInt(url.searchParams.get("limit") ?? "20", 10)));
  const cuisine = url.searchParams.get("cuisine") ?? "";
  const search  = (url.searchParams.get("search") ?? "").trim().slice(0, 100);
  const storeType = url.searchParams.get("store_type") ?? "food"; // "food" | "grocery" | "all"

  const cacheKey = `restaurants:${storeType}:${cuisine}:${search}:${page}:${limit}`;
  const cached = cacheGet<unknown[]>(cacheKey);

  if (cached) {
    return json(
      { success: true, data: cached, count: cached.length, page, cache_hit: true },
      200,
      { "X-Cache": "HIT", "Cache-Control": "public, max-age=60" },
    );
  }

  try {
    // Start building query
    let query = db
      .from("restaurants")
      .select(LIST_COLUMNS)
      .eq("is_verified", true)
      .range(page * limit, page * limit + limit - 1)
      .order("rating", { ascending: false });

    // Store type filter
    if (storeType === "food") {
      query = query.neq("store_type", "grocery");
    } else if (storeType === "grocery") {
      query = query.eq("store_type", "grocery");
    }
    // "all" = no store_type filter

    // Always filter to open restaurants for the browse list.
    // Closed restaurants can be fetched by ID directly.
    query = query.eq("is_open", true);

    // Search — cuisine type or name
    if (search.length > 0) {
      // Sanitise: strip PostgREST special chars
      const safe = search.replace(/[%_(),\\.]/g, "");
      query = query.or(`name.ilike.%${safe}%,cuisine_type.ilike.%${safe}%`);
    } else if (cuisine.length > 0) {
      const safe = cuisine.replace(/[%_(),\\.]/g, "");
      query = query.ilike("cuisine_type", `%${safe}%`);
    }

    const { data, error } = await query;

    if (error) {
      console.error("[get-restaurants-cached] DB error:", error.message);
      return json({ success: false, error: "Failed to fetch restaurants", code: "DB_ERROR" }, 500);
    }

    const rows = data ?? [];
    cacheSet(cacheKey, rows, RESTAURANT_TTL_MS);

    return json(
      { success: true, data: rows, count: rows.length, page, cache_hit: false },
      200,
      { "X-Cache": "MISS", "Cache-Control": "public, max-age=60" },
    );
  } catch (err) {
    console.error("[get-restaurants-cached] Unexpected error:", err);
    return json({ success: false, error: "Server error", code: "INTERNAL_ERROR" }, 500);
  }
});

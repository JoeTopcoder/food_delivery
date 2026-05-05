// menu-by-category — Fetch food menu items across all open restaurants for a
// given category. Used by the customer home screen so tapping a category chip
// shows every meal in that category (not just one restaurant).

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

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

function readParam(
  body: Record<string, unknown> | null,
  url: URL,
  key: string,
): string | undefined {
  const fromBody = body?.[key];
  if (typeof fromBody === "string" && fromBody.trim().length > 0) {
    return fromBody.trim();
  }
  const fromQuery = url.searchParams.get(key);
  if (fromQuery && fromQuery.trim().length > 0) {
    return fromQuery.trim();
  }
  return undefined;
}

function readNumber(
  body: Record<string, unknown> | null,
  url: URL,
  key: string,
): number | undefined {
  const raw = readParam(body, url, key);
  if (raw === undefined) return undefined;
  const n = Number(raw);
  return Number.isFinite(n) ? n : undefined;
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Accept GET (with query string) or POST (with JSON body) — easier to call
  // from a browser/curl while still working with supabase.functions.invoke.
  let body: Record<string, unknown> | null = null;
  if (request.method === "POST") {
    try {
      body = await request.json();
    } catch {
      return json({ error: "Invalid JSON" }, 400);
    }
  } else if (request.method !== "GET") {
    return json({ error: "Method not allowed" }, 405);
  }

  const url = new URL(request.url);
  const category = readParam(body, url, "category");
  if (!category) {
    return json({ error: "Missing category" }, 400);
  }
  const limit = Math.min(readNumber(body, url, "limit") ?? 100, 200);

  try {
    // Restaurant table is small; fetch open & active ones once, then filter in memory.
    const { data: restaurants, error: rErr } = await admin
      .from("restaurants")
      .select(
        "id, name, image_url, rating, review_count, delivery_fee, estimated_delivery_time, is_currently_open, is_active, opening_hours, latitude, longitude, address",
      )
      .eq("is_active", true);
    if (rErr) {
      return json({ error: "Failed to fetch restaurants", details: rErr.message }, 500);
    }

    const restaurantsById = new Map<string, Record<string, unknown>>();
    for (const r of restaurants ?? []) {
      restaurantsById.set(r.id as string, r as Record<string, unknown>);
    }

    if (restaurantsById.size === 0) {
      return json({ category, items: [], count: 0 });
    }

    // Case-insensitive category match. We use ilike so "pizza" finds "Pizza".
    const { data: items, error: mErr } = await admin
      .from("menus")
      .select(
        "id, restaurant_id, name, description, price, image_url, category, is_available, discount, rating, review_count, preparation_time, tags, calories, is_vegetarian, is_vegan, contains_nuts, contains_gluten, spice_level",
      )
      .ilike("category", category)
      .eq("is_available", true)
      .in("restaurant_id", Array.from(restaurantsById.keys()))
      .order("rating", { ascending: false })
      .limit(limit);

    if (mErr) {
      return json({ error: "Failed to fetch menu items", details: mErr.message }, 500);
    }

    const enriched = (items ?? []).map((m) => {
      const r = restaurantsById.get(m.restaurant_id as string) ?? {};
      return {
        ...m,
        restaurant: {
          id: r.id ?? null,
          name: r.name ?? null,
          image_url: r.image_url ?? null,
          rating: r.rating ?? null,
          delivery_fee: r.delivery_fee ?? null,
          estimated_delivery_time: r.estimated_delivery_time ?? null,
          is_currently_open: r.is_currently_open ?? false,
          address: r.address ?? null,
        },
      };
    });

    return json({ category, items: enriched, count: enriched.length });
  } catch (e) {
    return json({ error: "Unexpected error", details: String(e) }, 500);
  }
});

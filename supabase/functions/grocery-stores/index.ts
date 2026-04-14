// grocery-stores — Fetch and search verified grocery stores
// Supports: GET (all stores), POST with { query } for search, { store_id } for single store

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

function sanitize(q: string): string {
  return q.replace(/[%_(),.\\]/g, "");
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    let query: string | null = null;
    let storeId: string | null = null;
    let ownerId: string | null = null;
    let limit = 50;

    if (request.method === "POST") {
      const body = await request.json();
      query = body.query ?? null;
      storeId = body.store_id ?? null;
      ownerId = body.owner_id ?? null;
      limit = body.limit ?? 50;
    }

    // Single store by ID
    if (storeId) {
      const { data, error } = await admin
        .from("restaurants")
        .select("*")
        .eq("id", storeId)
        .or("store_type.eq.grocery,store_type.eq.both")
        .single();

      if (error || !data) {
        return json({ error: "Store not found" }, 404);
      }
      return json({ store: data });
    }

    // Owner's grocery store
    if (ownerId) {
      const { data, error } = await admin
        .from("restaurants")
        .select("*")
        .eq("owner_id", ownerId)
        .or("store_type.eq.grocery,store_type.eq.both")
        .limit(1);

      if (error) {
        return json({ error: "Failed to fetch owner store" }, 500);
      }
      return json({ store: data && data.length > 0 ? data[0] : null });
    }

    // Search or list all
    let dbQuery = admin
      .from("restaurants")
      .select("*")
      .or("store_type.eq.grocery,store_type.eq.both")
      .eq("is_verified", true)
      .order("rating", { ascending: false })
      .limit(limit);

    if (query && query.trim().length > 0) {
      dbQuery = dbQuery.ilike("name", `%${sanitize(query)}%`);
    }

    const { data, error } = await dbQuery;
    if (error) {
      return json({ error: "Failed to fetch stores", details: `${error.message}` }, 500);
    }

    return json({ stores: data ?? [], count: (data ?? []).length });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

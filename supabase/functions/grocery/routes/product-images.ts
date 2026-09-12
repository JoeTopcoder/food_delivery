// grocery/product-images — real web image search for a product, so the admin
// can pick a clean catalogue photo instead of uploading their rough snapshot.
//
// Uses SerpAPI's Google Images engine (SERPAPI_KEY is a server secret, never in
// the client). Returns candidate images; the app shows them in a grid and the
// admin taps one to use as the product image.

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined } };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SERPAPI_KEY = Deno.env.get("SERPAPI_KEY") ?? "";
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

// Admins and store owners only (never customers — it spends the search quota).
async function requireStaff(request: Request): Promise<Response | null> {
  const authHeader = request.headers.get("Authorization") ?? "";
  const token = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7)
    : "";
  if (!token) return json({ error: "Unauthorized" }, 401);
  const { data: authUser, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !authUser?.user) return json({ error: "Unauthorized" }, 401);
  const uid = authUser.user.id;

  const { data: userRow } = await admin
    .from("users").select("role").eq("id", uid).maybeSingle();
  if (userRow?.role === "admin") return null;

  const { data: ownedStore } = await admin
    .from("restaurants").select("id").eq("owner_id", uid).limit(1).maybeSingle();
  if (ownedStore) return null;

  return json({ error: "Forbidden" }, 403);
}

interface SerpImage {
  title?: string;
  source?: string;
  thumbnail?: string;
  original?: string;
  original_width?: number;
  original_height?: number;
}

export async function handle(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!SERPAPI_KEY) {
    return json({ error: "Web image search is not configured" }, 503);
  }

  const denied = await requireStaff(request);
  if (denied) return denied;

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const query = (body.query as string | undefined)?.trim();
  const limit = Math.min(Math.max(Number(body.num ?? 12), 1), 24);
  if (!query) return json({ error: "query is required" }, 400);

  try {
    const url = new URL("https://serpapi.com/search.json");
    url.searchParams.set("engine", "google_images");
    url.searchParams.set("q", query);
    url.searchParams.set("hl", "en");
    url.searchParams.set("api_key", SERPAPI_KEY);

    const res = await fetch(url.toString());
    if (!res.ok) {
      const errText = await res.text();
      console.error(`[grocery/product-images] SerpAPI ${res.status}: ${errText}`);
      return json({ error: "Image search failed. Please try again." }, 502);
    }

    const data = await res.json();
    if (data.error) {
      console.error(`[grocery/product-images] SerpAPI error: ${data.error}`);
      return json({ error: "Image search failed. Please try again." }, 502);
    }

    const results: SerpImage[] = Array.isArray(data.images_results)
      ? data.images_results
      : [];

    const images = results
      .filter((r) =>
        typeof r.original === "string" && r.original.startsWith("http")
      )
      .slice(0, limit)
      .map((r) => ({
        thumbnail: r.thumbnail ?? r.original,
        original: r.original,
        title: r.title ?? "",
        source: r.source ?? "",
        width: r.original_width ?? null,
        height: r.original_height ?? null,
      }));

    return json({ query, images });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[grocery/product-images] error: ${msg}`);
    return json({ error: "Image search failed. Please try again." }, 500);
  }
}

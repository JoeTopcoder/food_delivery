// get-app-config — Returns all or category-filtered app_config values
// Used by Flutter client to hydrate AppConstants from the database

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

function parseValue(raw: string, valueType: string): unknown {
  switch (valueType) {
    case "number": return parseFloat(raw);
    case "boolean": return raw === "true";
    case "json": try { return JSON.parse(raw); } catch { return raw; }
    default: return raw;
  }
}

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const url = new URL(request.url);
    const category = url.searchParams.get("category");

    let query = admin.from("app_config").select("key, value, value_type, category");
    if (category) {
      query = query.eq("category", category);
    }

    const { data, error } = await query;
    if (error) {
      return json({ error: "Failed to fetch config" }, 500);
    }

    // Build a flat key→typed-value map and a grouped-by-category map
    const flat: Record<string, unknown> = {};
    const grouped: Record<string, Record<string, unknown>> = {};

    for (const row of data ?? []) {
      const typed = parseValue(row.value, row.value_type);
      flat[row.key] = typed;
      if (!grouped[row.category]) grouped[row.category] = {};
      grouped[row.category][row.key] = typed;
    }

    return json({ config: flat, grouped });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

// cart-recommendations — thin wrapper over the get_cart_recommendations DB function.
// All analysis logic lives in the database; this function just handles auth.
// Deploy: supabase functions deploy cart-recommendations --no-verify-jwt

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined }; serve(handler: (req: Request) => Response | Promise<Response>): void };

// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin       = createClient(supabaseUrl, supabaseKey);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status, headers: { ...cors, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST")    return json({ error: "Method not allowed" }, 405);

  let body: {
    user_id: string;
    cart_restaurant_ids: string[];
    delivery_lat?: number;
    delivery_lng?: number;
  };
  try { body = await req.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const { user_id, cart_restaurant_ids, delivery_lat, delivery_lng } = body;
  if (!user_id || !cart_restaurant_ids?.length) {
    return json({ error: "user_id and cart_restaurant_ids are required" }, 400);
  }

  // Single DB call — all logic is in the PostgreSQL function
  const { data, error } = await admin.rpc("get_cart_recommendations", {
    p_user_id:            user_id,
    p_cart_restaurant_ids: cart_restaurant_ids,
    p_delivery_lat:        delivery_lat ?? null,
    p_delivery_lng:        delivery_lng ?? null,
  });

  if (error) {
    console.error("get_cart_recommendations error:", error.message);
    return json({ recommendations: [] });
  }

  return json({ recommendations: data ?? [] });
});

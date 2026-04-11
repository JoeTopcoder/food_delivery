// validate-promo — Server-authoritative promo code validation
// Checks code existence, active status, expiry, usage limits, min order amount
// Returns discount amount if valid, error if not

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

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const code = (body.code as string | undefined)?.trim().toUpperCase();
  const subtotal = body.subtotal as number | undefined;

  if (!code) return json({ error: "Missing promo code" }, 400);
  if (!subtotal || subtotal <= 0) return json({ error: "Missing or invalid subtotal" }, 400);

  try {
    const { data: promo, error } = await admin
      .from("promo_codes")
      .select("*")
      .eq("code", code)
      .eq("is_active", true)
      .maybeSingle();

    if (error || !promo) {
      return json({ valid: false, error: "Invalid or inactive promo code" });
    }

    // Expiry check
    if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
      return json({ valid: false, error: "Promo code has expired" });
    }

    // Usage limit check
    if (promo.max_uses !== null && promo.usage_count >= promo.max_uses) {
      return json({ valid: false, error: "Promo code usage limit reached" });
    }

    // Min order amount check
    if (promo.min_order_amount && subtotal < promo.min_order_amount) {
      return json({
        valid: false,
        error: `Minimum order of JMD$${promo.min_order_amount} required`,
      });
    }

    // Calculate discount
    let discount = 0;
    if (promo.discount_type === "percentage") {
      discount = Math.round(subtotal * promo.discount_value / 100 * 100) / 100;
    } else {
      discount = Math.min(promo.discount_value, subtotal);
    }

    return json({
      valid: true,
      promo: {
        id: promo.id,
        code: promo.code,
        discount_type: promo.discount_type,
        discount_value: promo.discount_value,
        discount_amount: discount,
        min_order_amount: promo.min_order_amount,
        expires_at: promo.expires_at,
      },
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

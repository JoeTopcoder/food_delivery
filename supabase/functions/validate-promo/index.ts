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
    // ── 1. Check promo_codes (no is_active filter so we can give specific errors) ──
    const { data: promo } = await admin
      .from("promo_codes")
      .select("*")
      .eq("code", code)
      .maybeSingle();

    if (promo) {
      // Already used / deactivated
      if (!promo.is_active) {
        return json({ valid: false, error: "This code has already been used." });
      }
      // Expiry check
      if (promo.expires_at && new Date(promo.expires_at) < new Date()) {
        return json({ valid: false, error: "This code has expired." });
      }
      // Usage limit check
      if (promo.max_uses !== null && promo.usage_count >= promo.max_uses) {
        return json({ valid: false, error: "This code has already been used." });
      }
      // Min order amount check
      if (promo.min_order_amount && subtotal < promo.min_order_amount) {
        return json({
          valid: false,
          error: `Your cart is a little short — this code needs a minimum order of JMD$${promo.min_order_amount} to apply.`,
        });
      }
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
    }

    // ── 2. Fallback: check user_coupons (AI-generated codes not yet bridged) ──
    // First check without is_used filter to detect already-used codes
    const { data: userCouponAny } = await admin
      .from("user_coupons")
      .select("*")
      .eq("code", code)
      .maybeSingle();

    if (!userCouponAny) {
      return json({ valid: false, error: "That code doesn't look right — please double-check and try again." });
    }
    if (userCouponAny.is_used) {
      return json({ valid: false, error: "This code has already been used." });
    }
    // Expiry check
    if (userCouponAny.expires_at && new Date(userCouponAny.expires_at) < new Date()) {
      return json({ valid: false, error: "This code has expired." });
    }
    // Min order check
    const minOrder = userCouponAny.min_order ?? 0;
    if (minOrder > 0 && subtotal < minOrder) {
      return json({
        valid: false,
        error: `Your cart is a little short — this code needs a minimum order of JMD$${minOrder} to apply.`,
      });
    }
    const userCoupon = userCouponAny;
    // Bridge: insert into promo_codes so future lookups hit path 1
    const bridgeId = crypto.randomUUID();
    await admin.from("promo_codes").insert({
      id: bridgeId,
      code: userCoupon.code,
      description: userCoupon.reason ?? "AI-generated coupon",
      discount_type: "percentage",
      discount_value: userCoupon.discount_percent,
      min_order_amount: minOrder,
      max_uses: 1,
      usage_count: 0,
      is_active: true,
      expires_at: userCoupon.expires_at,
    }).onConflict("code").ignore();

    const discount = Math.round(subtotal * userCoupon.discount_percent / 100 * 100) / 100;
    return json({
      valid: true,
      promo: {
        id: userCoupon.id,
        code: userCoupon.code,
        discount_type: "percentage",
        discount_value: userCoupon.discount_percent,
        discount_amount: discount,
        min_order_amount: minOrder,
        expires_at: userCoupon.expires_at,
      },
    });
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

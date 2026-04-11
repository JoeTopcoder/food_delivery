// process-loyalty — Server-authoritative loyalty point operations
// Handles: earn points, redeem points, check balance, calculate max redeemable
// All thresholds and multipliers come from app_config table

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

async function getConfig(key: string, fallback: number): Promise<number> {
  const { data } = await admin.from("app_config").select("value").eq("key", key).maybeSingle();
  return data ? parseFloat(data.value) : fallback;
}

async function getAllLoyaltyConfig() {
  const [
    pointValue, maxRedemptionPct, pointsPer100,
    bronzeThreshold, silverThreshold, goldThreshold, platinumThreshold,
    bronzeMultiplier, silverMultiplier, goldMultiplier, platinumMultiplier,
  ] = await Promise.all([
    getConfig("loyalty_point_value", 0.10),
    getConfig("loyalty_max_redemption_percent", 0.20),
    getConfig("loyalty_points_per_100", 10),
    getConfig("loyalty_tier_bronze_threshold", 0),
    getConfig("loyalty_tier_silver_threshold", 500),
    getConfig("loyalty_tier_gold_threshold", 2000),
    getConfig("loyalty_tier_platinum_threshold", 5000),
    getConfig("loyalty_multiplier_bronze", 1.0),
    getConfig("loyalty_multiplier_silver", 1.25),
    getConfig("loyalty_multiplier_gold", 1.5),
    getConfig("loyalty_multiplier_platinum", 2.0),
  ]);
  return {
    pointValue, maxRedemptionPct, pointsPer100,
    tiers: {
      bronze:   { threshold: bronzeThreshold,   multiplier: bronzeMultiplier },
      silver:   { threshold: silverThreshold,   multiplier: silverMultiplier },
      gold:     { threshold: goldThreshold,     multiplier: goldMultiplier },
      platinum: { threshold: platinumThreshold, multiplier: platinumMultiplier },
    },
  };
}

function getTier(totalEarned: number, tiers: Record<string, { threshold: number; multiplier: number }>) {
  if (totalEarned >= tiers.platinum.threshold) return "platinum";
  if (totalEarned >= tiers.gold.threshold) return "gold";
  if (totalEarned >= tiers.silver.threshold) return "silver";
  return "bronze";
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

  const action = body.action as string;
  const userId = body.user_id as string;

  if (!action || !userId) return json({ error: "Missing action and user_id" }, 400);

  try {
    const config = await getAllLoyaltyConfig();

    switch (action) {
      // ── Get account info + config ─────────────────────────────────────────
      case "get_account": {
        const { data: account } = await admin
          .from("loyalty_accounts")
          .select("*")
          .eq("user_id", userId)
          .maybeSingle();

        if (!account) {
          return json({
            account: null,
            config: {
              point_value: config.pointValue,
              max_redemption_percent: config.maxRedemptionPct,
              tiers: config.tiers,
            },
          });
        }

        const tier = getTier(account.total_earned, config.tiers);
        const multiplier = config.tiers[tier]?.multiplier ?? 1.0;

        return json({
          account: {
            ...account,
            tier,
            tier_multiplier: multiplier,
            redemption_value: account.points * config.pointValue,
          },
          config: {
            point_value: config.pointValue,
            max_redemption_percent: config.maxRedemptionPct,
            points_per_100: config.pointsPer100,
            tiers: config.tiers,
          },
        });
      }

      // ── Calculate max redeemable for a given order ────────────────────────
      case "max_redeemable": {
        const orderTotal = body.order_total as number;
        if (!orderTotal) return json({ error: "Missing order_total" }, 400);

        const { data: account } = await admin
          .from("loyalty_accounts")
          .select("points")
          .eq("user_id", userId)
          .maybeSingle();

        if (!account) {
          return json({ max_points: 0, max_discount: 0 });
        }

        const cap = orderTotal * config.maxRedemptionPct;
        const pointsValue = account.points * config.pointValue;
        const maxDiscount = Math.min(pointsValue, cap);
        const maxPoints = Math.floor(maxDiscount / config.pointValue);

        return json({
          max_points: maxPoints,
          max_discount: Math.round(maxDiscount * 100) / 100,
          available_points: account.points,
          point_value: config.pointValue,
          cap_percent: config.maxRedemptionPct,
        });
      }

      // ── Earn points (called after order delivery) ─────────────────────────
      case "earn": {
        const orderId = body.order_id as string;
        const orderTotal = body.order_total as number;
        if (!orderId || !orderTotal) return json({ error: "Missing order_id, order_total" }, 400);

        // Get current tier to apply multiplier
        const { data: account } = await admin
          .from("loyalty_accounts")
          .select("total_earned")
          .eq("user_id", userId)
          .maybeSingle();

        const currentTier = account ? getTier(account.total_earned, config.tiers) : "bronze";
        const multiplier = config.tiers[currentTier]?.multiplier ?? 1.0;
        const basePoints = Math.floor(orderTotal / 100 * config.pointsPer100);
        const earnedPoints = Math.floor(basePoints * multiplier);

        if (earnedPoints <= 0) return json({ earned: 0 });

        await admin.rpc("add_loyalty_points", {
          p_user_id: userId,
          p_points: earnedPoints,
          p_order_id: orderId,
          p_type: "earn",
          p_description: `Earned from order (${multiplier}x ${currentTier} bonus)`,
        });

        return json({
          earned: earnedPoints,
          base_points: basePoints,
          multiplier,
          tier: currentTier,
        });
      }

      // ── Redeem points (called at order creation) ──────────────────────────
      case "redeem": {
        const orderId = body.order_id as string;
        const points = body.points as number;
        const orderTotal = body.order_total as number;
        if (!orderId || !points || !orderTotal) {
          return json({ error: "Missing order_id, points, order_total" }, 400);
        }

        // Verify balance
        const { data: account } = await admin
          .from("loyalty_accounts")
          .select("points")
          .eq("user_id", userId)
          .maybeSingle();

        if (!account || account.points < points) {
          return json({ error: "Insufficient loyalty points" }, 400);
        }

        // Verify doesn't exceed cap
        const cap = orderTotal * config.maxRedemptionPct;
        const requestedValue = points * config.pointValue;
        if (requestedValue > cap + 0.01) {
          return json({ error: "Redemption exceeds maximum allowed" }, 400);
        }

        await admin.rpc("add_loyalty_points", {
          p_user_id: userId,
          p_points: -points,
          p_order_id: orderId,
          p_type: "redeem",
          p_description: "Redeemed at checkout",
        });

        return json({
          redeemed: points,
          discount: Math.round(Math.min(requestedValue, cap) * 100) / 100,
        });
      }

      default:
        return json({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

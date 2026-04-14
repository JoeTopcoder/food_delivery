// Brain Engine — Supabase Edge Function
// Computes user profile, generates recommendations, handles coupons.
// Deploy: supabase functions deploy brain-engine
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
    const supabaseKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    const supabase = createClient(supabaseUrl, supabaseKey);

    const { user_id, latitude, longitude } = await req.json();

    if (!user_id) {
      return new Response(
        JSON.stringify({ error: "user_id is required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // 1. Compute / refresh user intelligence profile
    const { data: profileData, error: profileErr } = await supabase.rpc(
      "compute_user_profile",
      { p_user_id: user_id }
    );

    if (profileErr) {
      console.error("compute_user_profile error:", profileErr);
    }

    const segment = profileData?.segment ?? "new_user";
    const churnRisk = profileData?.churn_risk ?? 0;
    const cuisineScores = profileData?.cuisine_scores ?? {};

    // Top cuisine
    let topCuisine: string | null = null;
    const cuisineEntries = Object.entries(cuisineScores);
    if (cuisineEntries.length > 0) {
      cuisineEntries.sort(
        (a, b) => Number(b[1]) - Number(a[1])
      );
      topCuisine = cuisineEntries[0][0];
    }

    // 2. Get scored recommendations
    const { data: recommendations, error: recErr } = await supabase.rpc(
      "get_smart_recommendations",
      {
        p_user_id: user_id,
        p_latitude: latitude ?? null,
        p_longitude: longitude ?? null,
        p_limit: 30,
      }
    );

    if (recErr) {
      console.error("get_smart_recommendations error:", recErr);
    }

    // Sort into sections
    const forYou: any[] = [];
    const becauseYouLove: any[] = [];
    const dealsForYou: any[] = [];
    const quickDelivery: any[] = [];

    for (const rec of recommendations ?? []) {
      switch (rec.section) {
        case "because_you_love":
          becauseYouLove.push(rec);
          break;
        case "deals_for_you":
          dealsForYou.push(rec);
          break;
        case "quick_delivery":
          quickDelivery.push(rec);
          break;
        default:
          forYou.push(rec);
      }
    }

    // 3. Generate coupon for at-risk / new users
    let coupon = null;
    if (churnRisk > 0.5 || segment === "new_user" || segment === "inactive") {
      const { data: couponData, error: couponErr } = await supabase.rpc(
        "generate_targeted_coupon",
        { p_user_id: user_id }
      );
      if (!couponErr && couponData?.generated) {
        coupon = couponData;
      }
    }

    // 4. Return assembled response
    const response = {
      recommendations: {
        for_you: forYou,
        because_you_love: becauseYouLove,
        deals_for_you: dealsForYou,
        quick_delivery: quickDelivery,
      },
      coupon,
      profile: {
        segment,
        churn_risk: churnRisk,
        top_cuisine: topCuisine,
        cuisine_scores: cuisineScores,
        total_orders: profileData?.total_orders ?? 0,
        days_since_last_order: profileData?.days_since_last_order ?? 0,
        activity_score: profileData?.activity_score ?? 0,
      },
    };

    return new Response(JSON.stringify(response), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
      status: 200,
    });
  } catch (err) {
    console.error("Brain engine error:", err);
    return new Response(
      JSON.stringify({ error: err.message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

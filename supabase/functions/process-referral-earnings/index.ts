// process-referral-earnings — Edge function for order referral earnings
// Called after order delivery to process direct/indirect referral earnings + volume bonuses
// Can be triggered by webhook, cron, or client-side after status update

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

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const action = (body.action as string) ?? "process_order";

  try {
    if (action === "process_order") {
      // Process referral earnings for a delivered order
      const orderId = body.order_id as string;
      const customerId = body.customer_id as string;

      if (!orderId || !customerId) {
        return json({ error: "Missing order_id or customer_id" }, 400);
      }

      // Call the RPC for order referral earnings
      const { data: orderResult, error: orderErr } = await admin.rpc(
        "process_order_referral_earnings",
        { p_order_id: orderId, p_customer_id: customerId }
      );
      if (orderErr) {
        console.error("Order earning error:", orderErr);
      }

      // Check volume bonus for the direct referrer
      const { data: referrerRow } = await admin
        .from("users")
        .select("referred_by")
        .eq("id", customerId)
        .single();

      let volumeResult = null;
      if (referrerRow?.referred_by) {
        const { data: vr, error: ve } = await admin.rpc(
          "process_volume_bonus",
          { p_user_id: referrerRow.referred_by }
        );
        if (!ve) volumeResult = vr;
      }

      return json({
        success: true,
        order_earnings: orderResult,
        volume_bonus: volumeResult,
      });

    } else if (action === "process_signup") {
      // Process signup referral bonus after first order
      const userId = body.user_id as string;
      if (!userId) {
        return json({ error: "Missing user_id" }, 400);
      }

      const { data, error } = await admin.rpc(
        "process_signup_referral_bonus",
        { p_referred_user_id: userId }
      );
      if (error) {
        return json({ error: error.message }, 500);
      }
      return json({ success: true, result: data });

    } else if (action === "expire_credits") {
      // Expire old credits (cron job action)
      const { data, error } = await admin.rpc("expire_old_credits");
      if (error) {
        return json({ error: error.message }, 500);
      }
      return json({ success: true, expired_count: data });

    } else {
      return json({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (err) {
    console.error("process-referral-earnings error:", err);
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

// admin-verify-restaurant — Admin approves or rejects a restaurant.
// Runs with service_role key to bypass RLS on the restaurants table.
// Deploy: supabase functions deploy admin-verify-restaurant

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    // Authenticate caller using service-role client (more reliable than anon-key getUser)
    const authHeader = req.headers.get("authorization") ?? "";
    const token = authHeader.startsWith("Bearer ") ? authHeader.slice(7) : authHeader;
    if (!token) return json({ error: "Unauthorized" }, 401);

    const { data: { user }, error: authErr } = await admin.auth.getUser(token);
    if (authErr || !user) return json({ error: "Unauthorized" }, 401);

    // Verify the caller is an admin
    const { data: adminUser, error: adminErr } = await admin
      .from("users")
      .select("role")
      .eq("id", user.id)
      .single();

    if (adminErr || !adminUser || adminUser.role !== "admin") {
      return json({ error: "Forbidden — admin access required" }, 403);
    }

    const body = await req.json();
    const restaurantId: string | undefined = body.restaurant_id;
    const isVerified: boolean = body.is_verified === true;

    if (!restaurantId) return json({ error: "restaurant_id is required" }, 400);

    const now = new Date().toISOString();

    // Update the restaurant using service role (bypasses RLS)
    const { error: updateErr } = await admin
      .from("restaurants")
      .update({
        is_verified: isVerified,
        status: isVerified ? "active" : "rejected",
        updated_at: now,
      })
      .eq("id", restaurantId);

    if (updateErr) {
      // If status=rejected violates a CHECK constraint, try without status
      if (updateErr.message?.includes("check") || updateErr.message?.includes("constraint")) {
        const { error: fallbackErr } = await admin
          .from("restaurants")
          .update({ is_verified: isVerified, updated_at: now })
          .eq("id", restaurantId);
        if (fallbackErr) throw fallbackErr;
      } else {
        throw updateErr;
      }
    }

    // Notify the restaurant owner via FCM (best-effort, non-fatal)
    try {
      const { data: restaurant } = await admin
        .from("restaurants")
        .select("owner_id, name")
        .eq("id", restaurantId)
        .single();

      if (restaurant?.owner_id) {
        const { data: ownerUser } = await admin
          .from("users")
          .select("fcm_token")
          .eq("id", restaurant.owner_id)
          .single();

        if (ownerUser?.fcm_token) {
          await admin.functions.invoke("send-fcm-notification", {
            body: {
              token: ownerUser.fcm_token,
              title: isVerified ? "Restaurant Approved! 🎉" : "Restaurant Application Update",
              body: isVerified
                ? `${restaurant.name} has been approved and is now visible to customers.`
                : `${restaurant.name} was not approved. Please contact support for more information.`,
              data: { type: "restaurant_verification", restaurant_id: restaurantId, is_verified: String(isVerified) },
            },
          });
        }
      }
    } catch (_) {
      // Non-fatal — notification failure should not block the approval
    }

    return json({ success: true, restaurant_id: restaurantId, is_verified: isVerified });
  } catch (err: unknown) {
    const msg = (err as { message?: string })?.message ?? String(err);
    console.error("[admin-verify-restaurant]", msg, err);
    return json({ error: msg }, 500);
  }
});

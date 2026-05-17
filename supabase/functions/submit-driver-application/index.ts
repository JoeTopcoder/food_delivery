// submit-driver-application — Called by driver app to submit their verification application.
// Changes driver_status from 'draft' → 'pending_review', sets submitted_at, logs the action.
// Deploy: supabase functions deploy submit-driver-application

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
    // Authenticate the caller
    const authHeader = req.headers.get("authorization") ?? "";
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { authorization: authHeader } },
    });
    const { data: { user }, error: authErr } = await userClient.auth.getUser();
    if (authErr || !user) return json({ error: "Unauthorized" }, 401);

    const body = await req.json();
    const driverId: string | undefined = body.driver_id;
    if (!driverId) return json({ error: "driver_id is required" }, 400);

    // Verify this driver belongs to the calling user
    const { data: driver, error: driverErr } = await admin
      .from("drivers")
      .select("id, user_id, driver_status, onboarding_step")
      .eq("id", driverId)
      .single();

    if (driverErr || !driver) return json({ error: "Driver not found" }, 404);
    if (driver.user_id !== user.id) return json({ error: "Forbidden" }, 403);

    // Only allow submission from draft or rejected states
    const allowedStatuses = ["draft", "rejected", "expired_documents"];
    if (!allowedStatuses.includes(driver.driver_status)) {
      return json({
        error: `Cannot submit from status '${driver.driver_status}'. Application is already ${driver.driver_status}.`,
      }, 409);
    }

    const now = new Date().toISOString();

    // Update driver status
    const { error: updateErr } = await admin
      .from("drivers")
      .update({
        driver_status: "pending_review",
        submitted_at: now,
        rejection_reason: null,
        updated_at: now,
      })
      .eq("id", driverId);

    if (updateErr) throw updateErr;

    // Log the verification action
    await admin.from("driver_verification_logs").insert({
      driver_id: driverId,
      action: "application_submitted",
      actor_id: user.id,
      old_status: driver.driver_status,
      new_status: "pending_review",
      notes: `Submitted at step ${driver.onboarding_step}/8`,
    });

    // Notify admin via FCM (best-effort)
    try {
      const { data: admins } = await admin
        .from("users")
        .select("fcm_token")
        .eq("role", "admin")
        .not("fcm_token", "is", null);

      if (admins && admins.length > 0) {
        for (const adminUser of admins) {
          if (adminUser.fcm_token) {
            await admin.functions.invoke("send-fcm-notification", {
              body: {
                token: adminUser.fcm_token,
                title: "New Driver Application",
                body: "A driver has submitted their verification application for review.",
                data: { type: "driver_application", driver_id: driverId },
              },
            });
          }
        }
      }
    } catch (_) {
      // Non-fatal — admin notification failure doesn't block submission
    }

    return json({ success: true, driver_status: "pending_review" });
  } catch (err) {
    console.error("[submit-driver-application]", err);
    return json({ error: "Internal server error" }, 500);
  }
});

// admin-review-driver — Admin approves or rejects a driver application.
// Sets driver_status, per-service approval flags, logs the action, and notifies the driver.
// Deploy: supabase functions deploy admin-review-driver

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
    // Authenticate caller — must be admin
    const authHeader = req.headers.get("authorization") ?? "";
    const userClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY") ?? "", {
      global: { headers: { authorization: authHeader } },
    });
    const { data: { user }, error: authErr } = await userClient.auth.getUser();
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
    const driverId: string | undefined = body.driver_id;
    const approved: boolean = body.approved === true;
    const rejectionReason: string | undefined = body.rejection_reason;
    const approveFoodDelivery: boolean = body.approve_food_delivery === true;
    const approveRideSharing: boolean = body.approve_ride_sharing === true;

    if (!driverId) return json({ error: "driver_id is required" }, 400);

    // Fetch current driver
    const { data: driver, error: driverErr } = await admin
      .from("drivers")
      .select("id, user_id, driver_status, full_name")
      .eq("id", driverId)
      .single();

    if (driverErr || !driver) return json({ error: "Driver not found" }, 404);

    const now = new Date().toISOString();
    const oldStatus = driver.driver_status as string;
    const newStatus = approved ? "approved" : "rejected";

    // Build update payload
    const updatePayload: Record<string, unknown> = {
      driver_status: newStatus,
      reviewed_by: user.id,
      reviewed_at: now,
      updated_at: now,
    };

    if (approved) {
      updatePayload.approved_at = now;
      updatePayload.is_food_driver_approved = approveFoodDelivery;
      updatePayload.is_ride_driver_approved = approveRideSharing;
      // Enable availability for approved services immediately
      updatePayload.is_available_for_food = approveFoodDelivery;
      updatePayload.is_available_for_rides = approveRideSharing;
      updatePayload.rejection_reason = null;
      // Also set legacy is_verified for backwards compat with existing code
      updatePayload.is_verified = true;
      updatePayload.documents_status = "approved";
    } else {
      updatePayload.rejection_reason = rejectionReason ?? "Application rejected by admin.";
      updatePayload.is_food_driver_approved = false;
      updatePayload.is_ride_driver_approved = false;
      updatePayload.is_available_for_food = false;
      updatePayload.is_available_for_rides = false;
      updatePayload.is_online = false;
      updatePayload.is_verified = false;
      updatePayload.documents_status = "rejected";
    }

    const { error: updateErr } = await admin
      .from("drivers")
      .update(updatePayload)
      .eq("id", driverId);

    if (updateErr) throw updateErr;

    // Log the action
    await admin.from("driver_verification_logs").insert({
      driver_id: driverId,
      action: approved ? "application_approved" : "application_rejected",
      actor_id: user.id,
      old_status: oldStatus,
      new_status: newStatus,
      notes: approved
        ? `Approved: food=${approveFoodDelivery}, rides=${approveRideSharing}`
        : `Rejected: ${rejectionReason ?? "no reason given"}`,
    });

    // Notify the driver via FCM (best-effort)
    try {
      const { data: driverUser } = await admin
        .from("users")
        .select("fcm_token, name")
        .eq("id", driver.user_id)
        .single();

      if (driverUser?.fcm_token) {
        const title = approved ? "Application Approved! 🎉" : "Application Update";
        const msgBody = approved
          ? "Congratulations! Your driver application has been approved. You can now start accepting deliveries."
          : `Your application was not approved. Reason: ${rejectionReason ?? "Please contact support."}`;

        await admin.functions.invoke("send-fcm-notification", {
          body: {
            token: driverUser.fcm_token,
            title,
            body: msgBody,
            data: {
              type: "driver_application_review",
              driver_id: driverId,
              status: newStatus,
            },
          },
        });
      }
    } catch (_) {
      // Non-fatal
    }

    return json({
      success: true,
      driver_id: driverId,
      driver_status: newStatus,
      is_food_driver_approved: approveFoodDelivery,
      is_ride_driver_approved: approveRideSharing,
    });
  } catch (err: unknown) {
    const msg = (err as { message?: string })?.message ?? String(err);
    console.error("[admin-review-driver]", msg, err);
    return json({ error: msg }, 500);
  }
});

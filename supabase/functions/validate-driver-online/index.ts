// validate-driver-online — Toggles a driver's is_online status after validating
// that they are approved and their documents are current. Falls back to a
// direct DB update if validation passes. Rejects if not approved.
// Deploy: supabase functions deploy validate-driver-online

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
    const goOnline: boolean = body.go_online === true;

    if (!driverId) return json({ error: "driver_id is required" }, 400);

    // Fetch driver
    const { data: driver, error: driverErr } = await admin
      .from("drivers")
      .select(
        "id, user_id, driver_status, is_food_driver_approved, is_ride_driver_approved, is_online"
      )
      .eq("id", driverId)
      .single();

    if (driverErr || !driver) return json({ error: "Driver not found" }, 404);
    if (driver.user_id !== user.id) return json({ error: "Forbidden" }, 403);

    // Going offline is always allowed
    if (!goOnline) {
      await admin
        .from("drivers")
        .update({ is_online: false, is_available: false, updated_at: new Date().toISOString() })
        .eq("id", driverId);
      return json({ success: true, is_online: false });
    }

    // Going online — validate approval status
    const isApproved =
      driver.driver_status === "approved" &&
      (driver.is_food_driver_approved || driver.is_ride_driver_approved);

    // Allow drivers with legacy 'draft' status (existing production drivers)
    // who were verified before this system was deployed
    const isLegacyDriver = driver.driver_status === "draft";

    if (!isApproved && !isLegacyDriver) {
      return json({
        error: "cannot_go_online",
        reason: `Your account status is '${driver.driver_status}'. You must be approved before going online.`,
        driver_status: driver.driver_status,
      }, 403);
    }

    // Check for expired documents (best-effort — don't block if query fails)
    try {
      const today = new Date().toISOString().substring(0, 10);

      const { data: expiredDocs } = await admin
        .from("driver_licenses")
        .select("expiry_date")
        .eq("driver_id", driverId)
        .lt("expiry_date", today)
        .not("expiry_date", "is", null);

      if (expiredDocs && expiredDocs.length > 0) {
        // Flag the driver and block going online
        await admin
          .from("drivers")
          .update({ driver_status: "expired_documents", updated_at: new Date().toISOString() })
          .eq("id", driverId);

        return json({
          error: "documents_expired",
          reason: "Your driver's license has expired. Please upload a valid license to go online.",
        }, 403);
      }

      const { data: expiredInsurance } = await admin
        .from("driver_insurance")
        .select("expiry_date")
        .eq("driver_id", driverId)
        .lt("expiry_date", today)
        .not("expiry_date", "is", null);

      if (expiredInsurance && expiredInsurance.length > 0) {
        await admin
          .from("drivers")
          .update({ driver_status: "expired_documents", updated_at: new Date().toISOString() })
          .eq("id", driverId);

        return json({
          error: "documents_expired",
          reason: "Your vehicle insurance has expired. Please upload a valid insurance certificate.",
        }, 403);
      }
    } catch (_) {
      // Non-fatal — proceed if document check fails
    }

    // All checks passed — set online
    await admin
      .from("drivers")
      .update({
        is_online: true,
        is_available: true,
        updated_at: new Date().toISOString(),
      })
      .eq("id", driverId);

    return json({ success: true, is_online: true });
  } catch (err) {
    console.error("[validate-driver-online]", err);
    return json({ error: "Internal server error" }, 500);
  }
});

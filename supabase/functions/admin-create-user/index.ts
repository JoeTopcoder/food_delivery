// Admin Create User Edge Function
// Creates confirmed users with roles (driver/restaurant) without email verification
// SECURITY: service_role key stays server-side, never exposed in client code

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseAnonKey = Deno.env.get("SUPABASE_ANON_KEY") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

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

  try {
    // 1. Verify calling user is admin
    const authHeader = request.headers.get("Authorization") ?? "";
    const anonClient = createClient(supabaseUrl, supabaseAnonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const {
      data: { user: caller },
      error: authError,
    } = await anonClient.auth.getUser();

    if (authError || !caller) {
      return json({ error: "Unauthorized" }, 401);
    }

    // Check caller role = admin
    const { data: callerProfile } = await createClient(
      supabaseUrl,
      supabaseServiceRoleKey
    )
      .from("users")
      .select("role")
      .eq("id", caller.id)
      .single();

    if (!callerProfile || callerProfile.role !== "admin") {
      return json({ error: "Forbidden — admin only" }, 403);
    }

    // 2. Parse request body
    const body = await request.json();
    const {
      email,
      password,
      name,
      role,
      vehicleType,
      vehicleNumber,
      licenseNumber,
      restaurantName,
      cuisineType,
      address,
      phone,
    } = body;

    if (!email || !password || !name || !role) {
      return json({ error: "Missing required fields: email, password, name, role" }, 400);
    }

    const validRoles = ["user", "driver", "restaurant", "admin"];
    if (!validRoles.includes(role)) {
      return json({ error: `Invalid role: ${role}` }, 400);
    }

    // 3. Create auth user via Admin API (service-role, auto-confirmed)
    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: authData, error: createError } =
      await adminClient.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { name, role },
      });

    if (createError) {
      return json({ error: createError.message }, 400);
    }

    const newUserId = authData.user.id;

    // Allow trigger time to create public.users row
    await new Promise((r) => setTimeout(r, 600));

    // 4. Create role-specific row
    if (role === "driver") {
      const { error: driverErr } = await adminClient.from("drivers").insert({
        user_id: newUserId,
        vehicle_type: vehicleType || "motorcycle",
        vehicle_number: vehicleNumber || "",
        license_number: licenseNumber || "",
        is_verified: false,
        is_available: false,
        completed_deliveries: 0,
        rating: 0.0,
        documents_status: "pending",
        created_at: new Date().toISOString(),
      });
      if (driverErr) {
        console.error("Driver insert error:", driverErr);
      }
    } else if (role === "restaurant") {
      const { error: restErr } = await adminClient
        .from("restaurants")
        .insert({
          owner_id: newUserId,
          name: restaurantName || name,
          cuisine_type: cuisineType || null,
          address: address || "",
          phone: phone || "",
          is_verified: false,
          is_open: false,
          rating: 0.0,
          delivery_fee: 0.0,
          estimated_delivery_time: 30,
          created_at: new Date().toISOString(),
        });
      if (restErr) {
        console.error("Restaurant insert error:", restErr);
      }
    }

    return json({ user_id: newUserId });
  } catch (e) {
    console.error("admin-create-user error:", e);
    return json({ error: (e as Error).message ?? "Internal error" }, 500);
  }
});

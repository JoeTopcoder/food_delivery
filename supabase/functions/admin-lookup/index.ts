// Admin Lookup Edge Function
// Handles card, order, and customer lookups that require service_role access
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

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function sanitize(q: string): string {
  return q.replace(/[%_\\]/g, "");
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

    const adminClient = createClient(supabaseUrl, supabaseServiceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });

    const { data: callerProfile } = await adminClient
      .from("users")
      .select("role")
      .eq("id", caller.id)
      .single();

    if (!callerProfile || callerProfile.role !== "admin") {
      return json({ error: "Forbidden — admin only" }, 403);
    }

    // 2. Parse request
    const body = await request.json();
    const { action, query } = body;

    if (!action || !query) {
      return json({ error: "Missing action or query" }, 400);
    }

    const sanitized = sanitize(query).trim();
    if (!sanitized) {
      return json({ error: "Empty query" }, 400);
    }

    // 3. Route by action
    if (action === "card") {
      const digits = sanitized.replace(/\D/g, "");
      if (!digits) return json([]);

      const cards = await adminClient
        .from("saved_cards")
        .select(
          "id, user_id, card_brand, last_four, cardholder_name, email, phone, is_default, created_at"
        )
        .eq("last_four", digits);

      if (!cards.data?.length) return json([]);

      const results = [];
      for (const card of cards.data) {
        const userId = card.user_id;
        const { data: user } = await adminClient
          .from("users")
          .select("id, name, email, phone, role, is_active, created_at")
          .eq("id", userId)
          .maybeSingle();

        const { data: orders } = await adminClient
          .from("orders")
          .select(
            "id, total_amount, status, payment_method, payment_status, ordered_at"
          )
          .eq("user_id", userId)
          .order("ordered_at", { ascending: false })
          .limit(5);

        results.push({ card, customer: user, recent_orders: orders ?? [] });
      }
      return json(results);
    }

    if (action === "order") {
      let order = null;
      const { data: exact } = await adminClient
        .from("orders")
        .select()
        .eq("id", sanitized)
        .maybeSingle();

      if (exact) {
        order = exact;
      } else {
        const { data: partial } = await adminClient
          .from("orders")
          .select()
          .ilike("id", `${sanitized}%`)
          .limit(1);
        if (partial?.length) order = partial[0];
      }

      if (!order) return json(null);

      const userId = order.user_id;
      let customer = null;
      if (userId) {
        const { data } = await adminClient
          .from("users")
          .select("id, name, email, phone, role, is_active")
          .eq("id", userId)
          .maybeSingle();
        customer = data;
      }

      const { data: payment } = await adminClient
        .from("payments")
        .select()
        .eq("order_id", order.id)
        .maybeSingle();

      const restaurantId = order.restaurant_id;
      let restaurant = null;
      if (restaurantId) {
        const { data } = await adminClient
          .from("restaurants")
          .select("id, name, phone, address")
          .eq("id", restaurantId)
          .maybeSingle();
        restaurant = data;
      }

      const driverId = order.driver_id;
      let driver = null;
      if (driverId) {
        const { data } = await adminClient
          .from("drivers")
          .select("id, user_id, vehicle_type, vehicle_number, rating")
          .eq("id", driverId)
          .maybeSingle();
        driver = data;
      }

      return json({ order, customer, payment, restaurant, driver });
    }

    if (action === "customer") {
      const { data: users } = await adminClient
        .from("users")
        .select("id, name, email, phone, role, is_active, created_at")
        .or(
          `email.ilike.%${sanitized}%,phone.ilike.%${sanitized}%,name.ilike.%${sanitized}%`
        )
        .limit(5);

      if (!users?.length) return json(null);

      const user = users[0];
      const userId = user.id;

      const { data: orders } = await adminClient
        .from("orders")
        .select(
          "id, total_amount, status, payment_method, payment_status, ordered_at, delivery_address"
        )
        .eq("user_id", userId)
        .order("ordered_at", { ascending: false })
        .limit(20);

      let cards: unknown[] = [];
      try {
        const { data } = await adminClient
          .from("saved_cards")
          .select(
            "id, card_brand, last_four, cardholder_name, is_default, created_at"
          )
          .eq("user_id", userId);
        cards = data ?? [];
      } catch (_) {
        // saved_cards may not exist
      }

      let wallet = null;
      try {
        const { data } = await adminClient
          .from("wallets")
          .select("balance, cashback_balance")
          .eq("user_id", userId)
          .maybeSingle();
        wallet = data;
      } catch (_) {
        // wallet may not exist
      }

      return json({
        customer: user,
        all_matches: users,
        orders: orders ?? [],
        saved_cards: cards,
        wallet,
      });
    }

    return json({ error: `Unknown action: ${action}` }, 400);
  } catch (e) {
    console.error("admin-lookup error:", e);
    return json({ error: (e as Error).message ?? "Internal error" }, 500);
  }
});

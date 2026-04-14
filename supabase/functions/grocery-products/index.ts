// grocery-products — Fetch, search, and manage grocery products
// Supports: list by store, search across stores, by category, CRUD for owners

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

function sanitize(q: string): string {
  return q.replace(/[%_(),.\\]/g, "");
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

  const action = (body.action as string) ?? "list";

  try {
    switch (action) {
      // ── List products for a store ──────────────────────────────────────
      case "list": {
        const storeId = body.store_id as string;
        if (!storeId) return json({ error: "Missing store_id" }, 400);

        const category = body.category as string | undefined;
        const includeUnavailable = body.include_unavailable === true;

        let query = admin
          .from("menus")
          .select("*, menu_item_sides(*), menu_option_groups(*, menu_option_choices(*))")
          .eq("restaurant_id", storeId)
          .eq("product_type", "grocery")
          .order("category");

        if (!includeUnavailable) {
          query = query.eq("is_available", true);
        }
        if (category) {
          query = query.eq("category", category);
        }

        const { data, error } = await query;
        if (error) return json({ error: "Failed to fetch products", details: error.message }, 500);

        return json({ products: data ?? [], count: (data ?? []).length });
      }

      // ── Search products across all stores ──────────────────────────────
      case "search": {
        const searchQuery = body.query as string;
        if (!searchQuery || searchQuery.trim().length === 0) {
          return json({ products: [], count: 0 });
        }

        const safe = sanitize(searchQuery);
        const { data, error } = await admin
          .from("menus")
          .select("*, menu_item_sides(*), menu_option_groups(*, menu_option_choices(*))")
          .eq("product_type", "grocery")
          .eq("is_available", true)
          .or(`name.ilike.%${safe}%,brand.ilike.%${safe}%,description.ilike.%${safe}%`)
          .order("name")
          .limit(50);

        if (error) return json({ error: "Search failed", details: error.message }, 500);
        return json({ products: data ?? [], count: (data ?? []).length });
      }

      // ── Get categories ─────────────────────────────────────────────────
      case "categories": {
        const { data, error } = await admin
          .from("grocery_categories")
          .select("*")
          .eq("is_active", true)
          .order("sort_order");

        if (error) return json({ error: "Failed to fetch categories" }, 500);
        return json({ categories: data ?? [] });
      }

      // ── Add product (owner) ────────────────────────────────────────────
      case "add": {
        const storeId = body.store_id as string;
        const name = body.name as string;
        const price = body.price as number;
        const categoryVal = body.category as string;

        if (!storeId || !name || price === undefined || !categoryVal) {
          return json({ error: "Missing required fields: store_id, name, price, category" }, 400);
        }

        const insert: Record<string, unknown> = {
          restaurant_id: storeId,
          name,
          price,
          category: categoryVal,
          description: body.description ?? null,
          image_url: body.image_url ?? null,
          is_available: true,
          product_type: "grocery",
          unit: body.unit ?? null,
          brand: body.brand ?? null,
          weight: body.weight ?? null,
          in_stock: true,
          max_quantity: body.max_quantity ?? 99,
        };

        const { data, error } = await admin.from("menus").insert(insert).select().single();
        if (error) return json({ error: "Failed to add product", details: error.message }, 500);
        return json({ product: data });
      }

      // ── Update product (owner) ─────────────────────────────────────────
      case "update": {
        const productId = body.product_id as string;
        if (!productId) return json({ error: "Missing product_id" }, 400);

        const updates: Record<string, unknown> = {};
        const fields = ["name", "price", "category", "description", "image_url",
          "unit", "brand", "weight", "max_quantity", "is_available", "in_stock"];
        for (const f of fields) {
          if (body[f] !== undefined) updates[f] = body[f];
        }

        if (Object.keys(updates).length === 0) {
          return json({ error: "No fields to update" }, 400);
        }

        const { data, error } = await admin
          .from("menus")
          .update(updates)
          .eq("id", productId)
          .eq("product_type", "grocery")
          .select()
          .single();

        if (error) return json({ error: "Failed to update product", details: error.message }, 500);
        return json({ product: data });
      }

      // ── Delete product (owner) ─────────────────────────────────────────
      case "delete": {
        const productId = body.product_id as string;
        if (!productId) return json({ error: "Missing product_id" }, 400);

        const { error } = await admin.from("menus").delete().eq("id", productId);
        if (error) return json({ error: "Failed to delete product", details: error.message }, 500);
        return json({ success: true });
      }

      // ── Toggle availability ────────────────────────────────────────────
      case "toggle": {
        const productId = body.product_id as string;
        const available = body.is_available as boolean;
        if (!productId || available === undefined) {
          return json({ error: "Missing product_id, is_available" }, 400);
        }

        const { error } = await admin
          .from("menus")
          .update({ is_available: available })
          .eq("id", productId);

        if (error) return json({ error: "Failed to toggle availability" }, 500);
        return json({ success: true, is_available: available });
      }

      // ── Toggle stock status ────────────────────────────────────────────
      case "stock": {
        const productId = body.product_id as string;
        const inStock = body.in_stock as boolean;
        if (!productId || inStock === undefined) {
          return json({ error: "Missing product_id, in_stock" }, 400);
        }

        const { error } = await admin
          .from("menus")
          .update({ in_stock: inStock })
          .eq("id", productId);

        if (error) return json({ error: "Failed to update stock" }, 500);
        return json({ success: true, in_stock: inStock });
      }

      default:
        return json({ error: `Unknown action: ${action}` }, 400);
    }
  } catch (err) {
    return json({ error: "Server error", details: `${err}` }, 500);
  }
});

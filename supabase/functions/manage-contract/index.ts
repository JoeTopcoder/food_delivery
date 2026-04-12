// manage-contract — CRUD for proprietor-client service agreements
// GET    ?id=<uuid>        → single contract
// GET    (no params)       → list all contracts
// POST   { ...fields }     → create new contract
// PUT    { id, ...fields } → update existing contract
// DELETE ?id=<uuid>        → soft-delete (set status=terminated)

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, serviceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

// Verify caller is admin
async function verifyAdmin(req: Request): Promise<string | null> {
  const authHeader = req.headers.get("authorization") ?? "";
  const token = authHeader.replace("Bearer ", "");
  if (!token) return null;

  const anonClient = createClient(
    supabaseUrl,
    Deno.env.get("SUPABASE_ANON_KEY") ?? ""
  );
  const {
    data: { user },
    error,
  } = await anonClient.auth.getUser(token);
  if (error || !user) return null;

  const { data: profile } = await admin
    .from("users")
    .select("role")
    .eq("id", user.id)
    .single();

  if (profile?.role !== "admin") return null;
  return user.id;
}

// Allowed columns for insert/update
const ALLOWED_FIELDS = [
  "doc_ref",
  "proprietor_name",
  "trading_as",
  "client_name",
  "fee_percent",
  "fee_cap_percent",
  "fee_cap_months",
  "support_email",
  "bank_name",
  "account_number",
  "account_name",
  "branch",
  "account_type",
  "restaurant_name",
  "authorized_personnel",
  "restaurant_email",
  "contract_date",
  "ceo_name",
  "ceo_title",
  "ceo_company",
  "ceo_date",
  "status",
];

function pickFields(body: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const k of ALLOWED_FIELDS) {
    if (k in body) out[k] = body[k];
  }
  return out;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  // Auth check
  const adminId = await verifyAdmin(req);
  if (!adminId) {
    return json({ error: "Unauthorized – admin access required" }, 401);
  }

  const url = new URL(req.url);

  try {
    // ── GET ─────────────────────────────────────────────────────────
    if (req.method === "GET") {
      const id = url.searchParams.get("id");
      if (id) {
        const { data, error } = await admin
          .from("contracts")
          .select("*")
          .eq("id", id)
          .single();
        if (error) return json({ error: error.message }, 404);
        return json({ contract: data });
      }
      // List all (non-terminated by default)
      const showAll = url.searchParams.get("all") === "true";
      let query = admin
        .from("contracts")
        .select("*")
        .order("created_at", { ascending: false });
      if (!showAll) {
        query = query.neq("status", "terminated");
      }
      const { data, error } = await query;
      if (error) return json({ error: error.message }, 500);
      return json({ contracts: data });
    }

    // ── POST (create) ───────────────────────────────────────────────
    if (req.method === "POST") {
      const body = await req.json();
      const fields = pickFields(body);
      if (!fields.client_name) {
        return json({ error: "client_name is required" }, 400);
      }
      const { data, error } = await admin
        .from("contracts")
        .insert(fields)
        .select()
        .single();
      if (error) return json({ error: error.message }, 500);
      return json({ contract: data }, 201);
    }

    // ── PUT (update) ────────────────────────────────────────────────
    if (req.method === "PUT") {
      const body = await req.json();
      const id = body.id ?? url.searchParams.get("id");
      if (!id) return json({ error: "id is required" }, 400);
      const fields = pickFields(body);
      if (Object.keys(fields).length === 0) {
        return json({ error: "No fields to update" }, 400);
      }
      const { data, error } = await admin
        .from("contracts")
        .update(fields)
        .eq("id", id)
        .select()
        .single();
      if (error) return json({ error: error.message }, 500);
      return json({ contract: data });
    }

    // ── DELETE (soft-delete) ────────────────────────────────────────
    if (req.method === "DELETE") {
      const id = url.searchParams.get("id");
      if (!id) return json({ error: "id query param required" }, 400);
      const { data, error } = await admin
        .from("contracts")
        .update({ status: "terminated" })
        .eq("id", id)
        .select()
        .single();
      if (error) return json({ error: error.message }, 500);
      return json({ contract: data });
    }

    return json({ error: "Method not allowed" }, 405);
  } catch (e) {
    return json({ error: (e as Error).message ?? "Internal error" }, 500);
  }
});

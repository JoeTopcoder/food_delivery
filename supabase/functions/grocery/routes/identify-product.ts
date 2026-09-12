// grocery/identify-product — AI product identification from a photo.
//
// Admin (or a store owner) sends a product photo; GPT-4o-mini vision returns a
// structured guess: full name, brand, size, dimensions, category, unit and a
// short description. No DB writes — the app shows the result in an editable
// form where the admin sets price + quantity and creates the product, using the
// captured photo as the image. (There is no web image-search key configured, so
// the product image is the admin's own photo, not a fetched catalogue image.)

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined } };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";
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

// Allow platform admins and anyone who owns a store (store owners can stock
// their own catalogue too). Never open to customers — it spends OpenAI credit.
async function requireStaff(request: Request): Promise<Response | null> {
  const authHeader = request.headers.get("Authorization") ?? "";
  const token = authHeader.toLowerCase().startsWith("bearer ")
    ? authHeader.slice(7)
    : "";
  if (!token) return json({ error: "Unauthorized" }, 401);
  const { data: authUser, error: authErr } = await admin.auth.getUser(token);
  if (authErr || !authUser?.user) return json({ error: "Unauthorized" }, 401);
  const uid = authUser.user.id;

  const { data: userRow } = await admin
    .from("users").select("role").eq("id", uid).maybeSingle();
  if (userRow?.role === "admin") return null;

  const { data: ownedStore } = await admin
    .from("restaurants").select("id").eq("owner_id", uid).limit(1).maybeSingle();
  if (ownedStore) return null;

  return json({ error: "Forbidden" }, 403);
}

const SYSTEM_PROMPT =
  "You identify retail grocery products from a single photo for a store " +
  "catalogue. Read any visible packaging text (brand, product name, net " +
  "weight/volume/count). Prefer what is printed on the package over guessing. " +
  "If the photo is not a clear single grocery product, set identified=false " +
  "and explain in notes. Respond ONLY with valid JSON — no markdown.";

const USER_PROMPT =
  "Identify this grocery product and respond with JSON exactly in this shape:\n" +
  "{\n" +
  '  "identified": true/false,\n' +
  '  "name": "full product name including brand and size, e.g. \\"Grace Coconut Milk 400ml\\"",\n' +
  '  "brand": "brand only, or null",\n' +
  '  "size": "net weight / volume / count as printed, e.g. \\"400 ml\\", \\"1 lb\\", \\"12 pack\\", or null",\n' +
  '  "dimensions": "physical package dimensions if determinable, e.g. \\"7 x 7 x 12 cm\\", else null",\n' +
  '  "category": "a short grocery category, e.g. \\"Canned Goods\\", \\"Beverages\\", \\"Snacks\\", \\"Produce\\", \\"Dairy\\"",\n' +
  '  "unit": "one of: each, pack, bottle, can, bag, lb, kg, oz",\n' +
  '  "description": "one or two factual sentences a shopper would find useful",\n' +
  '  "confidence": 0.0-1.0,\n' +
  '  "notes": "brief note if not identified or uncertain, else empty string"\n' +
  "}";

export async function handle(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!OPENAI_API_KEY) {
    return json({ error: "AI identification is not configured" }, 503);
  }

  const denied = await requireStaff(request);
  if (denied) return denied;

  let body: Record<string, unknown>;
  try {
    body = await request.json();
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  // Accept either a base64 payload (+ mime) or a direct https image URL.
  const rawB64 = (body.image_base64 as string | undefined)?.trim();
  const mime = (body.mime as string | undefined) || "image/jpeg";
  const directUrl = (body.image_url as string | undefined)?.trim();
  let imageUrl: string;
  if (rawB64) {
    const clean = rawB64.startsWith("data:") ? rawB64 : `data:${mime};base64,${rawB64}`;
    imageUrl = clean;
  } else if (directUrl && directUrl.startsWith("http")) {
    imageUrl = directUrl;
  } else {
    return json({ error: "image_base64 or image_url is required" }, 400);
  }

  try {
    const openaiRes = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          {
            role: "user",
            content: [
              { type: "text", text: USER_PROMPT },
              { type: "image_url", image_url: { url: imageUrl, detail: "low" } },
            ],
          },
        ],
        temperature: 0.2,
        response_format: { type: "json_object" },
        max_tokens: 500,
      }),
    });

    if (!openaiRes.ok) {
      const errText = await openaiRes.text();
      console.error(`[grocery/identify-product] OpenAI ${openaiRes.status}: ${errText}`);
      return json({ error: "Could not identify the product. Please try again." }, 502);
    }

    const data = await openaiRes.json();
    const content = data.choices?.[0]?.message?.content ?? "{}";
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(content);
    } catch {
      return json({ error: "Could not read the identification result." }, 502);
    }

    return json({
      identified: parsed.identified === true,
      name: (parsed.name as string) ?? "",
      brand: (parsed.brand as string) ?? null,
      size: (parsed.size as string) ?? null,
      dimensions: (parsed.dimensions as string) ?? null,
      category: (parsed.category as string) ?? "",
      unit: (parsed.unit as string) ?? "each",
      description: (parsed.description as string) ?? "",
      confidence: typeof parsed.confidence === "number" ? parsed.confidence : null,
      notes: (parsed.notes as string) ?? "",
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[grocery/identify-product] error: ${msg}`);
    return json({ error: "Identification failed. Please try again." }, 500);
  }
}

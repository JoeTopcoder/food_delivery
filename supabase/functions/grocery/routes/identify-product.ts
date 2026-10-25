// grocery/identify-product — read the product straight off the package using
// Google Gemini vision. It returns ONLY what is printed on the label (brand,
// flavour/variant, size), so the name matches the actual bottle rather than a
// visually-similar web product. SerpAPI (grocery/product-images) still supplies
// the catalogue image separately. No DB writes.

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined } };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
// Tried in order. The newest preview models frequently return 503 "high
// demand", so we fall through to stabler ones rather than failing the whole
// identify. An env override (GEMINI_MODEL) is prepended if set.
const GEMINI_MODELS = [
  Deno.env.get("GEMINI_MODEL"),
  "gemini-3.5-flash",
  "gemini-3.6-flash",
  "gemini-flash-latest",
].filter((m): m is string => !!m && m.trim().length > 0);
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

// Platform admins and store owners only — never customers (spends API credit).
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

const PROMPT =
  "You read a single retail grocery product from this photo for a store " +
  "catalogue. Use ONLY the text and facts printed on the package itself — " +
  "brand, product/flavour name, net weight/volume/count. Never guess a brand, " +
  "flavour or size that is not visibly printed, and never substitute a similar " +
  "product. If the label is unreadable or it is not a single grocery product, " +
  'set identified=false. Respond with JSON exactly in this shape:\n' +
  "{\n" +
  '  "identified": true/false,\n' +
  '  "name": "brand + flavour/variant exactly as printed, e.g. \\"Gatorade Berry Blue\\" — do NOT append size or extra words",\n' +
  '  "brand": "brand exactly as printed, or null",\n' +
  '  "flavour": "flavour/variant exactly as printed, or null",\n' +
  '  "size": "net volume/weight/count exactly as printed, e.g. \\"600 ml\\", or null",\n' +
  '  "category": "a short grocery category, e.g. \\"Beverages\\", \\"Snacks\\", \\"Dairy & Eggs\\", \\"Pantry\\"",\n' +
  '  "unit": "one of: each, pack, bottle, can, bag, lb, kg, oz",\n' +
  '  "description": "the product descriptor as printed on the label",\n' +
  '  "confidence": 0.0-1.0,\n' +
  '  "notes": "brief note if unreadable/uncertain, else empty string"\n' +
  "}";

// Gemini needs the image inline as base64. For an http URL, fetch + encode.
async function toBase64(rawB64: string | undefined, directUrl: string | undefined, mime: string):
  Promise<{ data: string; mime: string } | null> {
  if (rawB64) {
    const clean = rawB64.includes(",") ? rawB64.split(",").pop()! : rawB64;
    return { data: clean, mime };
  }
  if (directUrl && directUrl.startsWith("http")) {
    const r = await fetch(directUrl);
    if (!r.ok) return null;
    const ct = r.headers.get("content-type") || "image/jpeg";
    const buf = new Uint8Array(await r.arrayBuffer());
    let bin = "";
    for (let i = 0; i < buf.length; i++) bin += String.fromCharCode(buf[i]);
    return { data: btoa(bin), mime: ct };
  }
  return null;
}

export async function handle(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }
  if (!GEMINI_API_KEY) {
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

  const img = await toBase64(
    (body.image_base64 as string | undefined)?.trim(),
    (body.image_url as string | undefined)?.trim(),
    (body.mime as string | undefined) || "image/jpeg",
  );
  if (!img) return json({ error: "image_base64 or image_url is required" }, 400);

  const reqBody = JSON.stringify({
    contents: [{
      parts: [
        { text: PROMPT },
        { inline_data: { mime_type: img.mime, data: img.data } },
      ],
    }],
    generationConfig: { temperature: 0, responseMimeType: "application/json" },
  });

  try {
    // Try each model until one answers. 503/429/500 = overloaded or transient,
    // so move on to the next model; any other error is a real failure.
    let geminiRes: Response | null = null;
    let lastStatus = 0;
    let lastErr = "";
    for (const model of GEMINI_MODELS) {
      const res = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${GEMINI_API_KEY}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: reqBody,
        },
      );
      if (res.ok) {
        geminiRes = res;
        break;
      }
      lastStatus = res.status;
      lastErr = await res.text();
      console.error(`[grocery/identify-product] ${model} ${res.status}: ${lastErr.slice(0, 200)}`);
      // Only keep trying on overload/transient statuses.
      if (res.status !== 503 && res.status !== 429 && res.status !== 500) break;
    }

    if (!geminiRes) {
      const busy = lastStatus === 503 || lastStatus === 429;
      return json({
        error: busy
          ? "The AI is busy right now. Please try again in a moment."
          : "Could not identify the product. Please try again.",
      }, 502);
    }

    const data = await geminiRes.json();
    const parts = data.candidates?.[0]?.content?.parts ?? [];
    const content = parts.map((p: { text?: string }) => p.text ?? "").join("").trim();
    let parsed: Record<string, unknown>;
    try {
      parsed = JSON.parse(content);
    } catch {
      console.error(`[grocery/identify-product] parse fail: ${content.slice(0, 200)}`);
      return json({ error: "Could not read the identification result." }, 502);
    }

    return json({
      identified: parsed.identified === true,
      name: ((parsed.name as string) ?? "").trim(),
      brand: (parsed.brand as string) ?? null,
      flavour: (parsed.flavour as string) ?? null,
      size: (parsed.size as string) ?? null,
      dimensions: null,
      category: ((parsed.category as string) ?? "").trim(),
      unit: (parsed.unit as string) ?? "each",
      description: ((parsed.description as string) ?? "").trim(),
      confidence: typeof parsed.confidence === "number" ? parsed.confidence : null,
      notes: (parsed.notes as string) ?? "",
      images: [],
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[grocery/identify-product] error: ${msg}`);
    return json({ error: "Identification failed. Please try again." }, 500);
  }
}

// grocery/import-image — fetch a chosen web image and re-host it in our own
// storage, returning a stable public URL. Used after the admin picks a web
// search result: we don't hotlink the source (link rot / blocked hotlinking),
// we copy it into the same bucket product photos already use.

// deno-lint-ignore-file
declare const Deno: { env: { get(key: string): string | undefined } };

// @ts-ignore: Deno ESM import
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const supabaseServiceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const admin = createClient(supabaseUrl, supabaseServiceRoleKey);

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const MAX_BYTES = 8 * 1024 * 1024; // 8 MB

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

async function requireStaff(request: Request): Promise<{ uid: string } | Response> {
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
  if (userRow?.role === "admin") return { uid };
  const { data: ownedStore } = await admin
    .from("restaurants").select("id").eq("owner_id", uid).limit(1).maybeSingle();
  if (ownedStore) return { uid };
  return json({ error: "Forbidden" }, 403);
}

// Block non-http(s) and obvious internal targets (light SSRF guard).
function isSafeRemoteUrl(raw: string): boolean {
  let u: URL;
  try { u = new URL(raw); } catch { return false; }
  if (u.protocol !== "http:" && u.protocol !== "https:") return false;
  const host = u.hostname.toLowerCase();
  if (
    host === "localhost" ||
    host === "0.0.0.0" ||
    host === "169.254.169.254" ||
    host.endsWith(".local") ||
    host.startsWith("127.") ||
    host.startsWith("10.") ||
    host.startsWith("192.168.") ||
    /^172\.(1[6-9]|2\d|3[01])\./.test(host)
  ) return false;
  return true;
}

function extFor(contentType: string): string {
  if (contentType.includes("png")) return "png";
  if (contentType.includes("webp")) return "webp";
  if (contentType.includes("gif")) return "gif";
  return "jpg";
}

export async function handle(request: Request): Promise<Response> {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const staff = await requireStaff(request);
  if (staff instanceof Response) return staff;

  let body: Record<string, unknown>;
  try { body = await request.json(); } catch { return json({ error: "Invalid JSON" }, 400); }

  const imageUrl = (body.image_url as string | undefined)?.trim();
  const storeId = (body.store_id as string | undefined)?.trim();
  if (!imageUrl || !storeId) return json({ error: "image_url and store_id are required" }, 400);
  if (!isSafeRemoteUrl(imageUrl)) return json({ error: "Unsupported image URL" }, 400);

  try {
    const imgRes = await fetch(imageUrl, {
      headers: {
        // A browser-like UA improves success against hotlink filters.
        "User-Agent":
          "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36",
        "Accept": "image/avif,image/webp,image/apng,image/*,*/*;q=0.8",
      },
    });
    if (!imgRes.ok) {
      return json({ error: "Could not download that image. Pick another." }, 502);
    }
    let contentType = (imgRes.headers.get("content-type") ?? "").toLowerCase();
    // Some CDNs mislabel images as octet-stream; fall back to the URL extension.
    const urlExt = (imageUrl.split("?")[0].match(/\.(jpe?g|png|webp|gif)$/i) ??
      [])[1]?.toLowerCase();
    if (!contentType.startsWith("image/")) {
      if (urlExt) {
        contentType = urlExt === "jpg" ? "image/jpeg" : `image/${urlExt}`;
      } else {
        return json({ error: "That link is not an image. Pick another." }, 400);
      }
    }
    const buf = new Uint8Array(await imgRes.arrayBuffer());
    if (buf.byteLength === 0 || buf.byteLength > MAX_BYTES) {
      return json({ error: "Image is empty or too large. Pick another." }, 400);
    }

    const path = `grocery-products/${storeId}/web_${Date.now()}.${extFor(contentType)}`;
    const { error: upErr } = await admin.storage
      .from("profile-photos")
      .upload(path, buf, { contentType, upsert: false });
    if (upErr) {
      console.error(`[grocery/import-image] upload failed: ${upErr.message}`);
      return json({ error: "Could not save the image. Please try again." }, 500);
    }
    const { data: pub } = admin.storage.from("profile-photos").getPublicUrl(path);
    return json({ image_url: pub.publicUrl });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    console.error(`[grocery/import-image] error: ${msg}`);
    return json({ error: "Could not import the image. Please try again." }, 500);
  }
}

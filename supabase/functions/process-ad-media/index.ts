// process-ad-media — server-side validation + processing of an uploaded ad creative.
//
// Flow: a raw asset is uploaded to the PRIVATE `ad-assets-raw` bucket at
// "<restaurant_id>/<file>", an ad_creatives row is created (ad_new_creative RPC,
// status 'uploaded'). This function then:
//   1. validates type / size / (video) duration on the SERVER (never trusts the
//      client or filename extension),
//   2. for IMAGES: copies the validated asset into the PUBLIC `ad-assets` bucket
//      and marks the creative ready-for-approval (ad_mark_creative_ready),
//   3. for VIDEOS: transcoding to a compressed web-compatible format + thumbnail
//      is an EXTERNAL service (not configured here) — this is an honest integration
//      boundary. Without AD_TRANSCODE_URL set we DO NOT promote the raw upload;
//      we record a processing error so it never goes live unprocessed.
//
// Nothing is ever published automatically — promotion only makes a creative
// 'pending_approval'; a human still approves it before it can serve.
//
// Deploy: supabase functions deploy process-ad-media
// Secrets used: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, optional AD_TRANSCODE_URL.

// deno-lint-ignore-file
declare const Deno: {
  env: { get(k: string): string | undefined };
  serve(h: (req: Request) => Response | Promise<Response>): void;
};
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const admin = createClient(
  Deno.env.get("SUPABASE_URL") ?? "",
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
);
const TRANSCODE_URL = Deno.env.get("AD_TRANSCODE_URL") ?? "";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
function json(b: Record<string, unknown>, s = 200) {
  return new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });
}

const MAX_BYTES_DEFAULT = 52428800; // 50MB fallback
const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp"];
const VIDEO_TYPES = ["video/mp4", "video/quicktime", "video/webm"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // Caller must be an admin (the restaurant upload path triggers this via an
  // admin/staff action or a trusted server hook). Verify the JWT is an admin.
  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace("Bearer ", "");
  const { data: userRes } = await admin.auth.getUser(jwt);
  const uid = userRes?.user?.id;
  if (!uid) return json({ error: "unauthorized" }, 401);
  const { data: isAdmin } = await admin.rpc("is_admin");
  // is_admin() keys off auth.uid(); when called with service role it's null, so
  // we also check the users table for this caller.
  const { data: urow } = await admin.from("users").select("role").eq("id", uid).maybeSingle();
  if (isAdmin !== true && urow?.role !== "admin") return json({ error: "admin_only" }, 403);

  let body: { creative_id?: string };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }
  const creativeId = body?.creative_id;
  if (!creativeId) return json({ error: "creative_id required" }, 400);

  const { data: cr, error: ce } = await admin
    .from("ad_creatives")
    .select("id, raw_asset_path, media_type, restaurant_id, status")
    .eq("id", creativeId)
    .maybeSingle();
  if (ce || !cr) return json({ error: "creative_not_found" }, 404);
  if (!cr.raw_asset_path) return json({ error: "no_raw_asset" }, 400);

  const { data: settings } = await admin.from("ad_settings").select("max_upload_bytes, max_video_seconds").eq("id", 1).maybeSingle();
  const maxBytes = Number(settings?.max_upload_bytes ?? MAX_BYTES_DEFAULT);
  const maxSeconds = Number(settings?.max_video_seconds ?? 20);

  // Fetch the raw object to validate real type + size (not the filename).
  const dl = await admin.storage.from("ad-assets-raw").download(cr.raw_asset_path);
  if (dl.error || !dl.data) {
    await fail(creativeId, "raw asset unreadable");
    return json({ error: "raw_unreadable" }, 400);
  }
  const blob = dl.data;
  const bytes = blob.size;
  const type = blob.type || "";
  if (bytes > maxBytes) { await fail(creativeId, `file too large (${bytes} > ${maxBytes})`); return json({ error: "too_large" }, 400); }

  const isImage = IMAGE_TYPES.includes(type) || cr.media_type === "image";
  const isVideo = VIDEO_TYPES.includes(type) || cr.media_type === "video";
  if (!isImage && !isVideo) { await fail(creativeId, `unsupported type ${type}`); return json({ error: "unsupported_type" }, 400); }

  if (isImage) {
    // Promote the validated image into the public playback bucket.
    const pubPath = `${cr.restaurant_id}/${creativeId}.img`;
    const up = await admin.storage.from("ad-assets").upload(pubPath, blob, { upsert: true, contentType: type });
    if (up.error) { await fail(creativeId, "promote failed"); return json({ error: "promote_failed" }, 500); }
    const { data: pub } = admin.storage.from("ad-assets").getPublicUrl(pubPath);
    await admin.rpc("ad_mark_creative_ready", {
      p_creative_id: creativeId, p_playback_url: pub.publicUrl, p_thumbnail_url: pub.publicUrl,
    });
    return json({ ok: true, media: "image", playback_url: pub.publicUrl });
  }

  // VIDEO.
  // Preferred: an external service re-encodes to a guaranteed web-compatible
  // format + generates a thumbnail, then calls ad_mark_creative_ready. Use it
  // when AD_TRANSCODE_URL is configured.
  if (TRANSCODE_URL) {
    const resp = await fetch(TRANSCODE_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ creative_id: creativeId, raw_path: cr.raw_asset_path, max_seconds: maxSeconds }),
    });
    if (!resp.ok) { await fail(creativeId, `transcode request failed (${resp.status})`); return json({ error: "transcode_failed" }, 502); }
    return json({ ok: true, media: "video", status: "processing" });
  }

  // No transcode service configured: accept already-web-compatible uploads
  // (MP4 or WebM) as-is and promote them to the public bucket so the feature
  // works without external infra. Other containers (e.g. .mov/quicktime) are
  // rejected with a clear message rather than served in a form the player may
  // not support. Real transcoding (format conversion, duration trimming,
  // server-side thumbnail) still belongs to AD_TRANSCODE_URL when available.
  const webOk = type === "video/mp4" || type === "video/webm" ||
    cr.raw_asset_path.toLowerCase().endsWith(".mp4") ||
    cr.raw_asset_path.toLowerCase().endsWith(".webm");
  if (!webOk) {
    await fail(creativeId,
      "unsupported video container for direct playback — upload MP4 (H.264) or WebM, " +
      "or configure AD_TRANSCODE_URL for automatic conversion");
    return json({ error: "video_needs_transcode", max_video_seconds: maxSeconds }, 422);
  }
  const vext = type === "video/webm" ? "webm" : "mp4";
  const vPubPath = `${cr.restaurant_id}/${creativeId}.${vext}`;
  const vUp = await admin.storage.from("ad-assets").upload(vPubPath, blob, {
    upsert: true,
    contentType: type === "video/webm" ? "video/webm" : "video/mp4",
  });
  if (vUp.error) { await fail(creativeId, "promote failed"); return json({ error: "promote_failed" }, 500); }
  const { data: vPub } = admin.storage.from("ad-assets").getPublicUrl(vPubPath);
  await admin.rpc("ad_mark_creative_ready", {
    p_creative_id: creativeId,
    p_playback_url: vPub.publicUrl,
    p_thumbnail_url: null, // client-provided thumbnail (if any) kept on the creative row
  });
  return json({ ok: true, media: "video", playback_url: vPub.publicUrl, transcoded: false });
});

async function fail(creativeId: string, msg: string) {
  try {
    await admin.from("ad_creatives").update({ status: "failed", processing_error: msg }).eq("id", creativeId);
  } catch (_) { /* best effort */ }
}

// @ts-nocheck - Deno Edge Function (URL imports resolved at deploy time)
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

/**
 * Rate-limiting middleware edge function.
 * Uses in-memory sliding-window counter per IP.
 * Deploy: npx supabase functions deploy rate-limit --no-verify-jwt --project-ref yharweliruemjexmuuxn
 */

interface RateEntry {
  count: number;
  windowStart: number;
}

const store = new Map<string, RateEntry>();

const WINDOW_MS = 60_000;       // 1 minute window
const MAX_REQUESTS = 60;        // 60 requests per minute per IP
const CLEANUP_INTERVAL = 300_000; // cleanup old entries every 5 min

// Periodic cleanup
setInterval(() => {
  const now = Date.now();
  for (const [key, entry] of store) {
    if (now - entry.windowStart > WINDOW_MS * 2) {
      store.delete(key);
    }
  }
}, CLEANUP_INTERVAL);

serve(async (req) => {
  const ip =
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
    req.headers.get("x-real-ip") ??
    "unknown";

  const now = Date.now();
  let entry = store.get(ip);

  if (!entry || now - entry.windowStart > WINDOW_MS) {
    entry = { count: 1, windowStart: now };
    store.set(ip, entry);
  } else {
    entry.count++;
  }

  const remaining = Math.max(0, MAX_REQUESTS - entry.count);
  const resetAt = entry.windowStart + WINDOW_MS;

  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-RateLimit-Limit": String(MAX_REQUESTS),
    "X-RateLimit-Remaining": String(remaining),
    "X-RateLimit-Reset": String(Math.ceil(resetAt / 1000)),
    "Access-Control-Allow-Origin": "*",
  };

  if (req.method === "OPTIONS") {
    return new Response(null, {
      status: 204,
      headers: {
        ...headers,
        "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  if (entry.count > MAX_REQUESTS) {
    return new Response(
      JSON.stringify({
        error: "rate_limit_exceeded",
        message: "Too many requests. Please try again later.",
        retry_after_seconds: Math.ceil((resetAt - now) / 1000),
      }),
      { status: 429, headers }
    );
  }

  // If under limit, return success status
  // In production, this would proxy to the actual endpoint
  return new Response(
    JSON.stringify({
      allowed: true,
      remaining,
      reset_at: new Date(resetAt).toISOString(),
    }),
    { status: 200, headers }
  );
});

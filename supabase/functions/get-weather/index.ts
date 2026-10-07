// get-weather — secure server-side proxy to WeatherAPI.com's forecast endpoint.
//
// The provider key (WEATHERAPI_KEY) lives only as a server secret and is never
// returned to or logged for the client. Results are cached in public.weather_cache
// keyed by a coarse ~1 km geographic cell (+ units + days) so customers in nearby
// areas share one upstream call. Fresh cache = 10 minutes; if the provider is
// unavailable we may serve cache up to 60 minutes old, flagged stale.
//
// Guests are supported: deploy with --no-verify-jwt. Inputs are strictly
// validated and the upstream endpoint is fixed (no arbitrary URLs). We never
// log precise coordinates.
//
// Deploy: supabase functions deploy get-weather --no-verify-jwt
// Secret:  supabase secrets set WEATHERAPI_KEY=xxxxxxxx

// deno-lint-ignore-file
declare const Deno: {
  env: { get(key: string): string | undefined };
  serve(handler: (req: Request) => Response | Promise<Response>): void;
};

// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";

const supabaseUrl = Deno.env.get("SUPABASE_URL") ?? "";
const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const weatherKey = Deno.env.get("WEATHERAPI_KEY") ?? "";
const admin = createClient(supabaseUrl, serviceKey);

const UPSTREAM = "https://api.weatherapi.com/v1/forecast.json"; // fixed, never client-supplied
const UNITS = "c";
const DAYS = 1;
const FRESH_MS = 10 * 60 * 1000; // 10 minutes
const STALE_MS = 60 * 60 * 1000; // 60 minutes max fallback
const UPSTREAM_TIMEOUT_MS = 8000;

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

function json(body: Record<string, unknown>, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}

// Round to 2 dp (~1.1 km) for the shared cache cell. Fetch upstream for the
// cell's representative (rounded) coordinate so the result is independent of
// which customer first requested the cell.
function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

function cellKey(lat: number, lon: number): string {
  return `${lat.toFixed(2)},${lon.toFixed(2)}|${UNITS}|d${DAYS}`;
}

// Normalize the (large) provider payload down to a small, stable shape.
function normalize(raw: any, cellLat: number, cellLon: number) {
  const loc = raw?.location ?? {};
  const cur = raw?.current ?? {};
  const cond = cur?.condition ?? {};
  const hoursRaw: any[] = raw?.forecast?.forecastday?.[0]?.hour ?? [];

  const hourly = hoursRaw.map((h) => ({
    time: typeof h?.time === "string" ? h.time : null,
    time_epoch: typeof h?.time_epoch === "number" ? h.time_epoch : null,
    temp_c: typeof h?.temp_c === "number" ? h.temp_c : null,
    condition_code:
      typeof h?.condition?.code === "number" ? h.condition.code : null,
    condition_text:
      typeof h?.condition?.text === "string" ? h.condition.text : null,
    chance_of_rain:
      typeof h?.chance_of_rain === "number"
        ? h.chance_of_rain
        : Number.isFinite(Number(h?.chance_of_rain))
        ? Number(h.chance_of_rain)
        : 0,
    is_day: h?.is_day === 1 || h?.is_day === true,
  }));

  const observedIso =
    typeof cur?.last_updated_epoch === "number"
      ? new Date(cur.last_updated_epoch * 1000).toISOString()
      : null;

  return {
    location: {
      name: typeof loc?.name === "string" ? loc.name : null,
      region: typeof loc?.region === "string" ? loc.region : null,
      country: typeof loc?.country === "string" ? loc.country : null,
      tz_id: typeof loc?.tz_id === "string" ? loc.tz_id : null,
      localtime: typeof loc?.localtime === "string" ? loc.localtime : null,
    },
    current: {
      temp_c: typeof cur?.temp_c === "number" ? cur.temp_c : null,
      feelslike_c:
        typeof cur?.feelslike_c === "number" ? cur.feelslike_c : null,
      condition_text: typeof cond?.text === "string" ? cond.text : null,
      condition_code: typeof cond?.code === "number" ? cond.code : null,
      is_day: cur?.is_day === 1 || cur?.is_day === true,
      humidity: typeof cur?.humidity === "number" ? cur.humidity : null,
      wind_kph: typeof cur?.wind_kph === "number" ? cur.wind_kph : null,
      precip_mm: typeof cur?.precip_mm === "number" ? cur.precip_mm : null,
    },
    hourly,
    provider_observed_at: observedIso,
    // "near" — the rounded cell centre, not the exact requested point.
    cell: { lat: cellLat, lon: cellLon },
  };
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  let body: { lat?: unknown; lon?: unknown };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const lat = Number(body?.lat);
  const lon = Number(body?.lon);
  // Strict validation — reject malformed / out-of-range coordinates.
  if (
    !Number.isFinite(lat) ||
    !Number.isFinite(lon) ||
    lat < -90 ||
    lat > 90 ||
    lon < -180 ||
    lon > 180
  ) {
    return json({ error: "invalid_coordinates" }, 400);
  }

  if (!weatherKey) {
    console.error("WEATHERAPI_KEY not configured");
    return json({ error: "weather_unconfigured" }, 503);
  }

  const cLat = round2(lat);
  const cLon = round2(lon);
  const key = cellKey(cLat, cLon);
  const now = Date.now();

  // 1) Fresh cache hit → serve immediately (shared across users, no upstream call).
  try {
    const { data: cached } = await admin
      .from("weather_cache")
      .select("payload, provider_observed_at, fetched_at, expires_at")
      .eq("cell_key", key)
      .maybeSingle();

    if (cached && new Date(cached.expires_at).getTime() > now) {
      return json({
        ...cached.payload,
        stale: false,
        retrieved_at: cached.fetched_at,
        provider_observed_at:
          cached.provider_observed_at ??
          cached.payload?.provider_observed_at ??
          null,
      });
    }

    // 2) No fresh cache → call upstream for the cell's representative coord.
    try {
      const url =
        `${UPSTREAM}?key=${encodeURIComponent(weatherKey)}` +
        `&q=${cLat},${cLon}&days=${DAYS}&aqi=no&alerts=no`;

      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), UPSTREAM_TIMEOUT_MS);
      let resp: Response;
      try {
        resp = await fetch(url, { signal: controller.signal });
      } finally {
        clearTimeout(timer);
      }

      if (resp.status === 401 || resp.status === 403) {
        console.error("WeatherAPI auth/quota rejected request");
        return await serveStaleOr(admin, key, now, "weather_key_invalid");
      }
      if (resp.status === 429) {
        console.error("WeatherAPI quota/rate limit hit");
        return await serveStaleOr(admin, key, now, "weather_quota");
      }
      if (!resp.ok) {
        console.error("WeatherAPI upstream error status", resp.status);
        return await serveStaleOr(admin, key, now, "weather_upstream");
      }

      let raw: any;
      try {
        raw = await resp.json();
      } catch {
        console.error("WeatherAPI malformed response");
        return await serveStaleOr(admin, key, now, "weather_malformed");
      }
      if (!raw?.current || !raw?.location) {
        console.error("WeatherAPI response missing current/location");
        return await serveStaleOr(admin, key, now, "weather_malformed");
      }

      const payload = normalize(raw, cLat, cLon);
      const fetchedIso = new Date(now).toISOString();
      const expiresIso = new Date(now + FRESH_MS).toISOString();

      // Upsert shared cache (no customer id, no full address stored).
      try {
        await admin.from("weather_cache").upsert(
          {
            cell_key: key,
            lat: cLat,
            lon: cLon,
            payload,
            provider_observed_at: payload.provider_observed_at,
            fetched_at: fetchedIso,
            expires_at: expiresIso,
          },
          { onConflict: "cell_key" },
        );
      } catch (e) {
        console.error("weather_cache upsert failed");
      }

      // Opportunistic bounded cleanup (cheap, best-effort).
      try {
        await admin.rpc("prune_weather_cache");
      } catch (_) {}

      return json({ ...payload, stale: false, retrieved_at: fetchedIso });
    } catch (e) {
      // Network/timeout — fall back to stale cache if we have any.
      console.error("WeatherAPI fetch failed (network/timeout)");
      return await serveStaleOr(admin, key, now, "weather_unreachable");
    }
  } catch (e) {
    console.error("get-weather unexpected error");
    return json({ error: "weather_error" }, 500);
  }
});

// Serve cache up to 60 min old (flagged stale) when upstream is unavailable,
// otherwise return the given error. Older data is never presented as current.
async function serveStaleOr(
  admin: any,
  key: string,
  now: number,
  errorCode: string,
) {
  try {
    const { data: cached } = await admin
      .from("weather_cache")
      .select("payload, provider_observed_at, fetched_at")
      .eq("cell_key", key)
      .maybeSingle();
    if (cached) {
      const age = now - new Date(cached.fetched_at).getTime();
      if (age <= STALE_MS) {
        return json({
          ...cached.payload,
          stale: true,
          retrieved_at: cached.fetched_at,
          provider_observed_at:
            cached.provider_observed_at ??
            cached.payload?.provider_observed_at ??
            null,
        });
      }
    }
  } catch (_) {}
  return json({ error: errorCode }, 503);
}

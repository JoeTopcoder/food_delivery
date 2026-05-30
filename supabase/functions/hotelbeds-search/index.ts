import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { hotelbedsHeaders, getHotelbedsBase, extractError } from "../_shared/hotelbeds.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Decode JWT payload directly (function deployed with --no-verify-jwt)
    const token = authHeader.replace("Bearer ", "");
    let userId = "";
    try {
      const b64 = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/");
      const payload = JSON.parse(atob(b64)) as { sub?: string };
      userId = payload.sub ?? "";
    } catch { /* ignore */ }
    if (!userId) {
      return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });
    }

    // Load provider settings
    const { data: settings } = await supabase
      .from("travel_provider_settings")
      .select("*")
      .eq("provider", "hotelbeds")
      .single();

    if (!settings?.is_active) {
      return new Response(JSON.stringify({ error: "Hotel search is not available" }), { status: 503, headers: corsHeaders });
    }

    const apiKey = Deno.env.get("HOTELBEDS_API_KEY") ?? "";
    const secret = Deno.env.get("HOTELBEDS_SECRET") ?? "";
    if (!apiKey || !secret) {
      return new Response(JSON.stringify({ error: "Hotelbeds credentials not configured" }), { status: 500, headers: corsHeaders });
    }

    const body = await req.json();
    const {
      destination,          // destination code (e.g. "PMI")
      destination_name,
      latitude,             // for geolocation search
      longitude,
      radius = 50,          // km radius for geolocation
      check_in,             // "YYYY-MM-DD"
      check_out,            // "YYYY-MM-DD"
      rooms = 1,
      adults = 2,
      children = 0,
      children_ages = [],   // e.g. [5, 8]
      source_market,
      filters = {},
      max_hotels = 100,
    } = body;

    const hasGeo = latitude != null && longitude != null;
    if (!hasGeo && !destination) {
      return new Response(JSON.stringify({ error: "destination or latitude/longitude are required" }), { status: 400, headers: corsHeaders });
    }
    if (!check_in || !check_out) {
      return new Response(JSON.stringify({ error: "check_in and check_out are required" }), { status: 400, headers: corsHeaders });
    }

    // Build occupancy objects (one per room, same pax config)
    const paxArray = [
      ...Array(adults).fill({ type: "AD" }),
      ...children_ages.map((age: number) => ({ type: "CH", age })),
    ];
    const occupancies = Array(rooms).fill({ rooms: 1, adults, children, paxes: paxArray });

    const availRequest: Record<string, unknown> = {
      stay: { checkIn: check_in, checkOut: check_out },
      occupancies,
    };

    if (hasGeo) {
      availRequest.geolocation = { latitude, longitude, radius, unit: "km" };
    } else {
      availRequest.destination = { code: destination };
    }

    if (source_market ?? settings.source_market) {
      availRequest.sourceMarket = source_market ?? settings.source_market;
    }

    // Optional filters
    const filterObj: Record<string, unknown> = {};
    if (filters.min_category) filterObj.minCategory = filters.min_category;
    if (filters.max_category) filterObj.maxCategory = filters.max_category;
    if (filters.board_codes?.length) filterObj.boardCodes = filters.board_codes;
    if (filters.accommodation_types?.length) filterObj.accommodationTypes = filters.accommodation_types;
    if (filters.max_rate) filterObj.maxRate = filters.max_rate;
    if (filters.min_rate) filterObj.minRate = filters.min_rate;
    if (Object.keys(filterObj).length) availRequest.filter = filterObj;

    availRequest.reviews = [{ type: "HOTELBEDS", maxRate: 5, minRate: 1, minReviewCount: 3 }];

    const baseUrl = getHotelbedsBase(settings.mode);
    const hdrs = await hotelbedsHeaders(apiKey, secret);

    const hbRes = await fetch(`${baseUrl}/hotel-api/1.0/hotels`, {
      method: "POST",
      headers: hdrs,
      body: JSON.stringify(availRequest),
      signal: AbortSignal.timeout(30_000),
    });

    const hbData = await hbRes.json();

    if (!hbRes.ok) {
      const errMsg = extractError(hbData);
      console.error("Hotelbeds search error:", errMsg);
      // Log search attempt
      await supabase.from("hotel_search_logs").insert({
        user_id: userId,
        destination: destination_name ?? destination,
        destination_code: destination,
        check_in, check_out, rooms, adults, children, children_ages,
        source_market: source_market ?? settings.source_market,
        filters, results_count: 0,
        raw_request: availRequest,
        raw_response: hbData,
      });
      return new Response(JSON.stringify({ error: errMsg }), { status: hbRes.status, headers: corsHeaders });
    }

    const hotels = (hbData.hotels?.hotels ?? []) as Record<string, unknown>[];

    // Normalize results
    const normalized = hotels.slice(0, max_hotels).map((h: Record<string, unknown>) => {
      const rooms_ = (h.rooms ?? []) as Record<string, unknown>[];
      const minRate = rooms_.reduce((min: number, r: Record<string, unknown>) => {
        const rates = (r.rates ?? []) as Record<string, unknown>[];
        const rMin = rates.reduce((m: number, rt: Record<string, unknown>) => {
          const net = parseFloat((rt.net as string) ?? "999999");
          return net < m ? net : m;
        }, 999999);
        return rMin < min ? rMin : min;
      }, 999999);

      return {
        hotel_code: h.code,
        hotel_name: h.name,
        category_code: h.categoryCode,
        category_name: h.categoryName,
        destination_code: h.destinationCode,
        destination_name: h.destinationName,
        zone_code: h.zoneCode,
        zone_name: h.zoneName,
        latitude: h.latitude,
        longitude: h.longitude,
        min_rate: minRate === 999999 ? null : minRate,
        currency: hbData.hotels?.currency ?? "USD",
        rooms: rooms_,
        review_rating: (h.reviews as Record<string, unknown>[])?.[0]?.rate ?? null,
      };
    });

    // Log search
    await supabase.from("hotel_search_logs").insert({
      user_id: userId,
      destination: destination_name ?? destination,
      destination_code: destination,
      check_in, check_out, rooms, adults, children, children_ages,
      source_market: source_market ?? settings.source_market,
      filters, results_count: normalized.length,
      raw_request: availRequest,
      raw_response: { hotels_count: hotels.length, currency: hbData.hotels?.currency, hotel_codes: normalized.map((h: Record<string, unknown>) => h.hotel_code) },
    });

    // Pre-fetch content for hotels not yet cached
    const codes = normalized.map((h: Record<string, unknown>) => h.hotel_code as string);
    const { data: cached } = await supabase
      .from("hotel_content_cache")
      .select("hotel_code")
      .in("hotel_code", codes);
    const cachedCodes = new Set((cached ?? []).map((c: Record<string, unknown>) => c.hotel_code));
    const uncached = codes.filter((c) => !cachedCodes.has(c));

    // Enrich normalized with any existing cache data
    const { data: cacheRows } = await supabase
      .from("hotel_content_cache")
      .select("hotel_code, hotel_name, category, address, images, description")
      .in("hotel_code", codes);
    const cacheMap: Record<string, Record<string, unknown>> = {};
    for (const row of (cacheRows ?? []) as Record<string, unknown>[]) {
      cacheMap[row.hotel_code as string] = row;
    }

    const enriched = normalized.map((h: Record<string, unknown>) => {
      const c = cacheMap[h.hotel_code as string];
      return {
        ...h,
        hotel_name: c?.hotel_name ?? h.hotel_name,
        address: c?.address ?? null,
        images: c?.images ?? [],
        description: c?.description ?? null,
        needs_content_fetch: !cachedCodes.has(h.hotel_code as string),
      };
    });

    return new Response(JSON.stringify({
      hotels: enriched,
      total: hotels.length,
      currency: hbData.hotels?.currency ?? "USD",
      check_in,
      check_out,
      uncached_hotel_codes: uncached.slice(0, 50),
    }), { headers: corsHeaders });

  } catch (err) {
    console.error("hotelbeds-search error:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500, headers: corsHeaders });
  }
});

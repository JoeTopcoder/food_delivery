import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { hotelbedsHeaders, getHotelbedsBase, extractError } from "../_shared/hotelbeds.ts";

const CACHE_TTL_DAYS = 7;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { hotel_codes, language = "ENG", force_refresh = false } = await req.json() as {
      hotel_codes: string[];
      language?: string;
      force_refresh?: boolean;
    };

    if (!hotel_codes?.length) {
      return new Response(JSON.stringify({ error: "hotel_codes array is required" }), { status: 400, headers: corsHeaders });
    }

    // Load provider settings
    const { data: settings } = await supabase
      .from("travel_provider_settings")
      .select("*")
      .eq("provider", "hotelbeds")
      .single();

    const apiKey = Deno.env.get("HOTELBEDS_API_KEY") ?? "";
    const secret = Deno.env.get("HOTELBEDS_SECRET") ?? "";
    if (!apiKey || !secret) {
      return new Response(JSON.stringify({ error: "Hotelbeds credentials not configured" }), { status: 500, headers: corsHeaders });
    }

    const baseUrl = getHotelbedsBase(settings?.mode ?? "test");
    const hdrs = await hotelbedsHeaders(apiKey, secret);

    // Determine which codes need fetching
    let codesToFetch = [...hotel_codes];

    if (!force_refresh) {
      const cutoff = new Date(Date.now() - CACHE_TTL_DAYS * 24 * 60 * 60 * 1000).toISOString();
      const { data: cached } = await supabase
        .from("hotel_content_cache")
        .select("hotel_code")
        .in("hotel_code", hotel_codes)
        .gte("last_synced_at", cutoff);
      const freshCodes = new Set((cached ?? []).map((c: Record<string, unknown>) => c.hotel_code as string));
      codesToFetch = hotel_codes.filter((c) => !freshCodes.has(c));
    }

    const fetched: Record<string, unknown>[] = [];

    // Fetch in batches of 50 (API limit)
    for (let i = 0; i < codesToFetch.length; i += 50) {
      const batch = codesToFetch.slice(i, i + 50);
      const params = new URLSearchParams({
        fields: "all",
        language,
        codes: batch.join(","),
        from: "1",
        to: batch.length.toString(),
      });

      const res = await fetch(`${baseUrl}/hotel-content-api/1.0/hotels?${params}`, {
        method: "GET",
        headers: hdrs,
        signal: AbortSignal.timeout(30_000),
      });

      const data = await res.json();

      if (!res.ok) {
        console.error("Content API error for batch:", extractError(data));
        continue;
      }

      const hotels = (data.hotels ?? []) as Record<string, unknown>[];
      fetched.push(...hotels);
    }

    // Helper: Hotelbeds often returns localised text as {content, languageCode} or [{content, languageCode}]
    function extractText(raw: unknown, lang = language): string | null {
      if (typeof raw === "string") return raw || null;
      if (Array.isArray(raw)) {
        const match = raw.find((d: Record<string, unknown>) => d.languageCode === lang) ?? raw[0];
        return (match?.content as string) ?? null;
      }
      if (raw && typeof raw === "object") return ((raw as Record<string, unknown>).content as string) ?? null;
      return null;
    }

    // Upsert into cache
    const upsertRows = fetched.map((h: Record<string, unknown>) => {
      const rawAddr = h.address as Record<string, unknown> ?? {};
      // address may be {content, street, city, countryCode} or just an object
      const addrContent = extractText(rawAddr.content) ?? (rawAddr.street as string) ?? "";
      const city = (rawAddr.city as string) ?? null;
      const countryCode = (rawAddr.countryCode as string) ?? null;
      const address = [addrContent, city, countryCode].filter(Boolean).join(", ");
      const descriptionText = extractText(h.description);

      // images may be array or empty; path may include leading slash or not
      const rawImages = Array.isArray(h.images) ? h.images as Record<string, unknown>[] : [];
      const images = rawImages
        .slice(0, 20)
        .map((img: Record<string, unknown>) => {
          const path = (img.path as string) ?? "";
          const url = path.startsWith("http")
            ? path
            : `https://photos.hotelbeds.com/giata/${path.replace(/^\//, "")}`;
          return { url, type: img.imageTypeCode, order: img.order };
        })
        .filter((img) => img.url);

      const facilities = ((h.facilities as Record<string, unknown>[]) ?? []).map(
        (f: Record<string, unknown>) => ({
          code: f.facilityCode,
          group: f.facilityGroupCode,
          name: (f as Record<string, unknown>).description ?? f.facilityCode,
        })
      );

      const roomTypes = ((h.rooms as Record<string, unknown>[]) ?? []).map(
        (r: Record<string, unknown>) => ({
          code: r.roomCode,
          name: r.description,
          type: r.type,
          min_pax: r.minPax,
          max_pax: r.maxPax,
          characteristic: r.characteristic,
        })
      );

      const boardTypes = ((h.boards as Record<string, unknown>[]) ?? []).map(
        (b: Record<string, unknown>) => ({
          code: b.boardCode,
          description: b.description,
        })
      );

      const poi = ((h.interestPoints as Record<string, unknown>[]) ?? []).map(
        (p: Record<string, unknown>) => ({
          name: p.poiName,
          distance: p.distance,
          unit: p.unit,
        })
      );

      return {
        provider: "hotelbeds",
        hotel_code: (h.code as number | string).toString(),
        hotel_name: extractText(h.name) ?? (h.name as string) ?? null,
        category: extractText(h.categoryName) ?? (h.categoryName as string) ?? null,
        category_code: (h.categoryCode as string) ?? null,
        address,
        city,
        country_code: countryCode,
        destination_code: (h.destinationCode as string) ?? null,
        destination_name: (h.destinationName as string) ?? null,
        latitude: (h.coordinates as Record<string, unknown>)?.latitude ?? null,
        longitude: (h.coordinates as Record<string, unknown>)?.longitude ?? null,
        phone: (h.phones as Record<string, unknown>[])?.[0]?.phoneNumber ?? null,
        email: (h.email as string) ?? null,
        description: descriptionText,
        images,
        facilities,
        room_types: roomTypes,
        board_types: boardTypes,
        points_of_interest: poi,
        raw_content: h,
        last_synced_at: new Date().toISOString(),
      };
    });

    if (upsertRows.length > 0) {
      const { error: upsertErr } = await supabase
        .from("hotel_content_cache")
        .upsert(upsertRows, { onConflict: "provider,hotel_code" });
      if (upsertErr) {
        console.error("Cache upsert error:", upsertErr.message);
      }
    }

    // Return all requested from cache
    const { data: cacheRows } = await supabase
      .from("hotel_content_cache")
      .select("hotel_code, hotel_name, category, category_code, address, city, country_code, latitude, longitude, description, images, facilities, room_types, board_types, points_of_interest")
      .in("hotel_code", hotel_codes);

    return new Response(JSON.stringify({
      hotels: cacheRows ?? [],
      fetched_count: upsertRows.length,
    }), { headers: corsHeaders });

  } catch (err) {
    console.error("hotelbeds-get-hotel-content error:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500, headers: corsHeaders });
  }
});

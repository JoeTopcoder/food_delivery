import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { hotelbedsHeaders, getHotelbedsBase, extractError } from "../_shared/hotelbeds.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { rate_key } = await req.json() as { rate_key: string };

    if (!rate_key) {
      return new Response(JSON.stringify({ error: "rate_key is required" }), { status: 400, headers: corsHeaders });
    }

    const { data: settings } = await supabase
      .from("travel_provider_settings")
      .select("*")
      .eq("provider", "hotelbeds")
      .single();

    if (!settings?.is_active) {
      return new Response(JSON.stringify({ error: "Hotel booking is not available" }), { status: 503, headers: corsHeaders });
    }

    const apiKey = Deno.env.get("HOTELBEDS_API_KEY") ?? "";
    const secret = Deno.env.get("HOTELBEDS_SECRET") ?? "";
    if (!apiKey || !secret) {
      return new Response(JSON.stringify({ error: "Hotelbeds credentials not configured" }), { status: 500, headers: corsHeaders });
    }

    const baseUrl = getHotelbedsBase(settings.mode);
    const hdrs = await hotelbedsHeaders(apiKey, secret);

    const hbRes = await fetch(`${baseUrl}/hotel-api/1.0/checkrates`, {
      method: "POST",
      headers: hdrs,
      body: JSON.stringify({ rooms: [{ rateKey: rate_key }] }),
      signal: AbortSignal.timeout(20_000),
    });

    const hbData = await hbRes.json();

    if (!hbRes.ok) {
      const errMsg = extractError(hbData);
      console.error("CheckRate error:", errMsg);
      return new Response(JSON.stringify({ error: errMsg }), { status: hbRes.status, headers: corsHeaders });
    }

    const hotel = (hbData.hotel ?? {}) as Record<string, unknown>;
    const rooms = (hotel.rooms ?? []) as Record<string, unknown>[];

    // Extract the updated rate info
    let updatedRate: Record<string, unknown> | null = null;
    for (const room of rooms) {
      const rates = (room.rates ?? []) as Record<string, unknown>[];
      for (const rate of rates) {
        if (rate.rateKey === rate_key) {
          updatedRate = rate;
          break;
        }
      }
      if (updatedRate) break;
    }

    // Apply commission markup
    const commissionType = settings.commission_type ?? "percentage";
    const commissionValue = settings.commission_value ?? 10;
    const netRate = updatedRate ? parseFloat((updatedRate.net as string) ?? "0") : 0;
    let displayRate = netRate;
    if (commissionType === "percentage") {
      displayRate = netRate * (1 + commissionValue / 100);
    } else {
      displayRate = netRate + commissionValue;
    }

    return new Response(JSON.stringify({
      rate_key,
      net_rate: netRate,
      display_rate: Math.round(displayRate * 100) / 100,
      currency: hotel.currency ?? hbData.hotel?.currency ?? "USD",
      cancellation_policies: updatedRate?.cancellationPolicies ?? [],
      rate_comments: updatedRate?.rateComments ?? null,
      promotions: updatedRate?.promotions ?? [],
      rate_type: updatedRate?.rateType ?? null,
      rate_class: updatedRate?.rateClass ?? null,
      board_code: updatedRate?.boardCode ?? null,
      board_name: updatedRate?.boardName ?? null,
      payment_type: updatedRate?.paymentType ?? null,
      rooms: rooms,
    }), { headers: corsHeaders });

  } catch (err) {
    console.error("hotelbeds-check-rate error:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500, headers: corsHeaders });
  }
});

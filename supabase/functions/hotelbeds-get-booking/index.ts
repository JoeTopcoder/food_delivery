import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { hotelbedsHeaders, getHotelbedsBase } from "../_shared/hotelbeds.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const token = authHeader.replace("Bearer ", "");
    const jwtPayload = JSON.parse(atob(token.split(".")[1])) as { sub: string };
    const userId = jwtPayload.sub;

    const url = new URL(req.url);
    const bookingId = url.searchParams.get("booking_id");
    const hbReference = url.searchParams.get("reference");
    const syncFromProvider = url.searchParams.get("sync") === "true";

    if (!bookingId && !hbReference) {
      return new Response(JSON.stringify({ error: "booking_id or reference is required" }), { status: 400, headers: corsHeaders });
    }

    // Load from DB
    let query = supabase.from("hotel_bookings").select("*");
    if (bookingId) {
      query = query.eq("id", bookingId);
    } else {
      query = query.eq("hotelbeds_reference", hbReference!);
    }
    const { data: booking } = await query.single();

    if (!booking) {
      return new Response(JSON.stringify({ error: "Booking not found" }), { status: 404, headers: corsHeaders });
    }

    // Check ownership
    const { data: userRow } = await supabase.from("users").select("role").eq("id", userId).single();
    const isAdmin = userRow?.role === "admin";
    if (!isAdmin && booking.user_id !== userId) {
      return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: corsHeaders });
    }

    let providerData: Record<string, unknown> | null = null;

    if (syncFromProvider && booking.hotelbeds_reference) {
      const { data: settings } = await supabase
        .from("travel_provider_settings")
        .select("*")
        .eq("provider", "hotelbeds")
        .single();

      const apiKey = Deno.env.get("HOTELBEDS_API_KEY") ?? "";
      const secret = Deno.env.get("HOTELBEDS_SECRET") ?? "";

      if (apiKey && secret) {
        const baseUrl = getHotelbedsBase(settings?.mode ?? "test");
        const hdrs = await hotelbedsHeaders(apiKey, secret);

        const hbRes = await fetch(`${baseUrl}/hotel-api/1.0/bookings/${booking.hotelbeds_reference}`, {
          method: "GET",
          headers: hdrs,
          signal: AbortSignal.timeout(15_000),
        });

        if (hbRes.ok) {
          const hbData = await hbRes.json();
          providerData = hbData;

          const hbBooking = (hbData.booking ?? {}) as Record<string, unknown>;
          const newStatus = (hbBooking.status as string)?.toLowerCase();

          if (newStatus && newStatus !== booking.booking_status) {
            await supabase.from("hotel_bookings").update({
              booking_status: newStatus === "confirmed" ? "confirmed" : newStatus === "cancelled" ? "cancelled" : booking.booking_status,
              raw_provider_response: hbData,
            }).eq("id", booking.id);
          }
        }
      }
    }

    return new Response(JSON.stringify({
      booking,
      provider_data: providerData,
    }), { headers: corsHeaders });

  } catch (err) {
    console.error("hotelbeds-get-booking error:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500, headers: corsHeaders });
  }
});

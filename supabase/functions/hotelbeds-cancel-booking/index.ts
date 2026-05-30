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

    const token = authHeader.replace("Bearer ", "");
    const jwtPayload = JSON.parse(atob(token.split(".")[1])) as { sub: string };
    const userId = jwtPayload.sub;

    const { booking_id, cancellation_flag = "CANCELLATION" } = await req.json() as {
      booking_id: string;
      cancellation_flag?: "CANCELLATION" | "SIMULATION";
    };

    if (!booking_id) {
      return new Response(JSON.stringify({ error: "booking_id is required" }), { status: 400, headers: corsHeaders });
    }

    // Load booking — user must own it (or be admin)
    const { data: booking } = await supabase
      .from("hotel_bookings")
      .select("*")
      .eq("id", booking_id)
      .single();

    if (!booking) {
      return new Response(JSON.stringify({ error: "Booking not found" }), { status: 404, headers: corsHeaders });
    }

    // Check ownership (service role bypasses RLS, so manual check)
    const { data: userRow } = await supabase.from("users").select("role").eq("id", userId).single();
    const isAdmin = userRow?.role === "admin";
    if (!isAdmin && booking.user_id !== userId) {
      return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: corsHeaders });
    }

    if (booking.booking_status === "cancelled") {
      return new Response(JSON.stringify({ error: "Booking is already cancelled" }), { status: 409, headers: corsHeaders });
    }

    if (!booking.hotelbeds_reference) {
      return new Response(JSON.stringify({ error: "No Hotelbeds reference found for this booking" }), { status: 400, headers: corsHeaders });
    }

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

    const hbRes = await fetch(
      `${baseUrl}/hotel-api/1.0/bookings/${booking.hotelbeds_reference}?cancellationFlag=${cancellation_flag}`,
      {
        method: "DELETE",
        headers: hdrs,
        signal: AbortSignal.timeout(20_000),
      }
    );

    const hbData = await hbRes.json();

    if (!hbRes.ok) {
      const errMsg = extractError(hbData);
      console.error("Cancel booking error:", errMsg);
      return new Response(JSON.stringify({ error: errMsg }), { status: hbRes.status, headers: corsHeaders });
    }

    const hbBooking = (hbData.booking ?? {}) as Record<string, unknown>;
    const cancellationRef = (hbBooking.cancellationReference as string) ?? null;
    const cancellationAmount = parseFloat((hbBooking.cancellationAmount as string) ?? "0");

    // Update booking in DB
    await supabase.from("hotel_bookings").update({
      booking_status: "cancelled",
      cancellation_status: "cancelled",
      cancellation_reference: cancellationRef,
      cancellation_amount: cancellationAmount,
      raw_provider_response: hbData,
    }).eq("id", booking_id);

    // Log event
    await supabase.from("hotel_booking_events").insert({
      booking_id,
      event_type: "booking_cancelled",
      event_payload: {
        cancellation_reference: cancellationRef,
        cancellation_amount: cancellationAmount,
        flag: cancellation_flag,
      },
    });

    // Refund wallet if applicable
    if (booking.payment_method !== "stripe" && cancellationAmount < booking.total_amount) {
      const refundAmount = booking.total_amount - cancellationAmount;
      await supabase.rpc("wallet_topup", {
        p_user_id: booking.user_id,
        p_amount: refundAmount,
        p_description: `Hotel cancellation refund: ${booking.hotelbeds_reference}`,
        p_type: "refund",
      }).catch((e: Error) => console.error("Wallet refund error:", e.message));
    }

    // Send cancellation notification
    await supabase.from("notifications").insert({
      user_id: booking.user_id,
      type: "hotel_booking_cancelled",
      title: "Hotel Booking Cancelled",
      body: `Your booking at ${booking.hotel_name} has been cancelled. ${cancellationAmount > 0 ? `Cancellation fee: ${booking.currency} ${cancellationAmount.toFixed(2)}` : "No cancellation fee."}`,
      data: { booking_id, cancellation_reference: cancellationRef },
      is_read: false,
    }).catch((e: Error) => console.error("Notification error:", e.message));

    return new Response(JSON.stringify({
      cancelled: true,
      cancellation_reference: cancellationRef,
      cancellation_amount: cancellationAmount,
      currency: booking.currency,
    }), { headers: corsHeaders });

  } catch (err) {
    console.error("hotelbeds-cancel-booking error:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500, headers: corsHeaders });
  }
});

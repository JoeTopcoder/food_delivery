import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";
import { hotelbedsHeaders, getHotelbedsBase, extractError } from "../_shared/hotelbeds.ts";

interface Passenger {
  room_id: number;
  type: "AD" | "CH";
  name: string;
  surname: string;
  age?: number;
}

interface BookingRequest {
  rate_key: string;
  hotel_code: string;
  hotel_name?: string;
  check_in: string;
  check_out: string;
  rooms: number;
  adults: number;
  children: number;
  children_ages?: number[];
  holder_first_name: string;
  holder_last_name: string;
  holder_email: string;
  holder_phone?: string;
  passengers: Passenger[];
  net_rate: number;
  display_rate: number;
  currency: string;
  board_code?: string;
  room_type?: string;
  idempotency_key?: string;
  payment_method?: "wallet" | "card" | "stripe";
  stripe_payment_intent_id?: string;
  cancellation_policies?: unknown[];
  rate_comments?: string;
  rate_type?: string;
  rate_class?: string;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return new Response(JSON.stringify({ error: "Unauthorized" }), { status: 401, headers: corsHeaders });

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    // Verify user
    const token = authHeader.replace("Bearer ", "");
    const jwtPayload = JSON.parse(atob(token.split(".")[1])) as { sub: string };
    const userId = jwtPayload.sub;

    const body = await req.json() as BookingRequest;

    // Validate required fields
    const required = ["rate_key", "hotel_code", "check_in", "check_out", "holder_first_name", "holder_last_name", "holder_email"];
    for (const field of required) {
      if (!body[field as keyof BookingRequest]) {
        return new Response(JSON.stringify({ error: `${field} is required` }), { status: 400, headers: corsHeaders });
      }
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

    // Idempotency check
    const idempotencyKey = body.idempotency_key ?? `${userId}-${body.rate_key}-${Date.now()}`;
    const { data: existing } = await supabase
      .from("hotel_booking_attempts")
      .select("*")
      .eq("idempotency_key", idempotencyKey)
      .single();

    if (existing?.status === "confirmed") {
      // Return the booking
      const { data: booking } = await supabase
        .from("hotel_bookings")
        .select("*")
        .eq("user_id", userId)
        .eq("hotel_code", body.hotel_code)
        .eq("rate_key", body.rate_key)
        .order("created_at", { ascending: false })
        .limit(1)
        .single();
      return new Response(JSON.stringify({ booking, already_confirmed: true }), { headers: corsHeaders });
    }

    // Calculate service fee
    const commissionType = settings.commission_type ?? "percentage";
    const commissionValue = settings.commission_value ?? 10;
    const netAmount = body.net_rate;
    let serviceFee = 0;
    if (commissionType === "percentage") {
      serviceFee = netAmount * (commissionValue / 100);
    } else {
      serviceFee = commissionValue;
    }
    const totalAmount = netAmount + serviceFee;

    // Wallet payment check
    if (body.payment_method === "wallet") {
      const { error: walletErr } = await supabase.rpc("wallet_deduct", {
        p_user_id: userId,
        p_amount: totalAmount,
        p_description: `Hotel booking: ${body.hotel_name ?? body.hotel_code} ${body.check_in}–${body.check_out}`,
      });
      if (walletErr) {
        const isInsufficient = (walletErr.message ?? "").toLowerCase().includes("insufficient");
        return new Response(
          JSON.stringify({ error: isInsufficient ? "Insufficient wallet balance" : walletErr.message }),
          { status: 402, headers: corsHeaders }
        );
      }
    }

    // Create attempt record
    const { data: attempt } = await supabase
      .from("hotel_booking_attempts")
      .upsert({
        user_id: userId,
        hotel_code: body.hotel_code,
        rate_key: body.rate_key,
        amount: totalAmount,
        currency: body.currency,
        status: "pending",
        idempotency_key: idempotencyKey,
        raw_request: body,
      }, { onConflict: "idempotency_key" })
      .select()
      .single();

    // Build Hotelbeds booking request
    const agencyRef = `7DASH-${Date.now()}`;
    const bookingRooms = Array.from({ length: body.rooms }, (_, i) => {
      const roomPax = body.passengers?.filter((p) => p.room_id === i + 1) ?? [];
      return {
        rateKey: body.rate_key,
        paxes: roomPax.map((p) => ({
          roomId: i + 1,
          type: p.type,
          name: p.name,
          surname: p.surname,
          ...(p.age !== undefined ? { age: p.age } : {}),
        })),
      };
    });

    const hbBookingPayload = {
      holder: { name: body.holder_first_name, surname: body.holder_last_name },
      rooms: bookingRooms,
      clientReference: agencyRef,
      remark: `Booking via 7DASH | ${body.holder_email}${body.holder_phone ? ` | ${body.holder_phone}` : ""}`,
      tolerance: 2, // 2% price tolerance
    };

    const baseUrl = getHotelbedsBase(settings.mode);
    const hdrs = await hotelbedsHeaders(apiKey, secret);

    const hbRes = await fetch(`${baseUrl}/hotel-api/1.0/bookings`, {
      method: "POST",
      headers: hdrs,
      body: JSON.stringify(hbBookingPayload),
      signal: AbortSignal.timeout(30_000),
    });

    const hbData = await hbRes.json();

    if (!hbRes.ok) {
      const errMsg = extractError(hbData);
      console.error("Hotelbeds booking error:", errMsg);

      // Mark attempt as failed
      await supabase.from("hotel_booking_attempts").update({
        status: "failed",
        error_message: errMsg,
        raw_response: hbData,
      }).eq("idempotency_key", idempotencyKey);

      // Refund wallet if payment was wallet
      if (body.payment_method === "wallet") {
        await supabase.rpc("wallet_topup", {
          p_user_id: userId,
          p_amount: totalAmount,
          p_description: `Refund: failed hotel booking ${agencyRef}`,
          p_type: "refund",
        }).catch((e: Error) => console.error("Wallet refund failed:", e.message));
      }

      return new Response(JSON.stringify({ error: errMsg }), { status: hbRes.status, headers: corsHeaders });
    }

    const hbBooking = (hbData.booking ?? {}) as Record<string, unknown>;
    const hbHotel = (hbBooking.hotel ?? {}) as Record<string, unknown>;
    const hbHolder = (hbBooking.clientReference as string) ?? agencyRef;
    const hbRooms = (hbHotel.rooms ?? []) as Record<string, unknown>[];
    const firstRoom = hbRooms[0] ?? {};
    const firstRate = ((firstRoom.rates as Record<string, unknown>[]) ?? [])[0] ?? {};
    const hotelInfo = (hbHotel as Record<string, unknown>);
    const supplier = (hbBooking.supplier as Record<string, unknown>) ?? {};

    const nights = Math.round(
      (new Date(body.check_out).getTime() - new Date(body.check_in).getTime()) / (1000 * 60 * 60 * 24)
    );

    // Store booking
    const { data: booking, error: bookingErr } = await supabase
      .from("hotel_bookings")
      .insert({
        user_id: userId,
        provider: "hotelbeds",
        hotelbeds_reference: hbBooking.reference as string,
        agency_reference: agencyRef,
        hotel_code: body.hotel_code,
        hotel_name: body.hotel_name ?? (hotelInfo.name as string),
        hotel_category: (hotelInfo.categoryName as string) ?? null,
        hotel_address: (hotelInfo.address as string) ?? null,
        hotel_city: (hotelInfo.destinationName as string) ?? null,
        hotel_country: (hotelInfo.countryCode as string) ?? null,
        hotel_phone: (hotelInfo.phone as string) ?? null,
        destination_name: (hotelInfo.destinationName as string) ?? null,
        room_type: body.room_type ?? (firstRoom.description as string) ?? null,
        board_type: (firstRate.boardName as string) ?? null,
        board_code: body.board_code ?? (firstRate.boardCode as string) ?? null,
        check_in: body.check_in,
        check_out: body.check_out,
        nights,
        rooms: body.rooms,
        adults: body.adults,
        children: body.children,
        children_ages: body.children_ages ?? [],
        holder_first_name: body.holder_first_name,
        holder_last_name: body.holder_last_name,
        holder_email: body.holder_email,
        holder_phone: body.holder_phone ?? null,
        passenger_details: body.passengers ?? [],
        base_amount: netAmount,
        service_fee: serviceFee,
        total_amount: totalAmount,
        currency: body.currency,
        rate_key: body.rate_key,
        rate_type: body.rate_type ?? (firstRate.rateType as string) ?? null,
        rate_class: body.rate_class ?? (firstRate.rateClass as string) ?? null,
        cancellation_policies: body.cancellation_policies ?? (firstRate.cancellationPolicies as unknown[]) ?? [],
        rate_comments: body.rate_comments ?? (firstRate.rateComments as string) ?? null,
        promotions: (firstRate.promotions as unknown[]) ?? [],
        supplier_name: (supplier.name as string) ?? null,
        supplier_vat: (supplier.vatNumber as string) ?? null,
        payment_status: body.payment_method === "wallet" ? "paid" : (body.stripe_payment_intent_id ? "authorized" : "pending"),
        booking_status: "confirmed",
        stripe_payment_intent_id: body.stripe_payment_intent_id ?? null,
        raw_provider_response: hbData,
      })
      .select()
      .single();

    if (bookingErr) {
      console.error("DB booking insert error:", bookingErr.message);
    }

    // Update attempt to confirmed
    await supabase.from("hotel_booking_attempts").update({
      status: "confirmed",
      raw_response: { reference: hbBooking.reference },
    }).eq("idempotency_key", idempotencyKey);

    // Log event
    if (booking?.id) {
      await supabase.from("hotel_booking_events").insert({
        booking_id: booking.id,
        event_type: "booking_confirmed",
        event_payload: { reference: hbBooking.reference, payment_method: body.payment_method },
      });
    }

    // Send confirmation notification
    const token_ = authHeader.replace("Bearer ", "");
    const { data: profile } = await supabase.from("users").select("fcm_token, name").eq("id", userId).single();
    if (profile?.fcm_token) {
      await supabase.from("notifications").insert({
        user_id: userId,
        type: "hotel_booking_confirmed",
        title: "Hotel Booking Confirmed!",
        body: `Your booking at ${body.hotel_name ?? body.hotel_code} (${body.check_in}) is confirmed. Ref: ${hbBooking.reference}`,
        data: { booking_id: booking?.id, reference: hbBooking.reference },
        is_read: false,
      }).catch((e: Error) => console.error("Notification insert error:", e.message));
    }

    return new Response(JSON.stringify({
      booking,
      hotelbeds_reference: hbBooking.reference,
      agency_reference: agencyRef,
    }), { headers: corsHeaders });

  } catch (err) {
    console.error("hotelbeds-create-booking error:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500, headers: corsHeaders });
  }
});

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

function buildVoucherHtml(booking: Record<string, unknown>): string {
  const cancellationPolicies = (booking.cancellation_policies as Record<string, unknown>[]) ?? [];
  const policyRows = cancellationPolicies.map((p: Record<string, unknown>) => `
    <tr>
      <td>${p.amount ?? "N/A"} ${booking.currency}</td>
      <td>${p.from ? new Date(p.from as string).toLocaleDateString() : "N/A"}</td>
    </tr>
  `).join("");

  const passengers = (booking.passenger_details as Record<string, unknown>[]) ?? [];
  const passengerRows = passengers.map((p: Record<string, unknown>) => `
    <tr>
      <td>${p.name} ${p.surname}</td>
      <td>${p.type === "AD" ? "Adult" : `Child (age ${p.age ?? "N/A"})`}</td>
      <td>Room ${p.room_id}</td>
    </tr>
  `).join("");

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <title>Hotel Voucher – ${booking.hotelbeds_reference}</title>
  <style>
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: Arial, sans-serif; font-size: 14px; color: #1a1a1a; background: #fff; }
    .container { max-width: 700px; margin: 0 auto; padding: 32px; }
    .header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 24px; border-bottom: 3px solid #F4A024; padding-bottom: 16px; }
    .header h1 { color: #F4A024; font-size: 28px; }
    .header .ref { font-size: 12px; color: #666; text-align: right; }
    .status-badge { display: inline-block; background: #22c55e; color: #fff; padding: 4px 12px; border-radius: 20px; font-weight: bold; font-size: 12px; }
    section { margin-bottom: 24px; }
    section h2 { font-size: 16px; color: #F4A024; margin-bottom: 10px; border-bottom: 1px solid #f0e0c0; padding-bottom: 4px; }
    .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 8px 24px; }
    .grid .label { color: #777; font-size: 12px; }
    .grid .value { font-weight: 600; }
    table { width: 100%; border-collapse: collapse; }
    th { background: #f8f0e0; text-align: left; padding: 8px; font-size: 12px; }
    td { padding: 8px; border-bottom: 1px solid #f0f0f0; font-size: 13px; }
    .total-row td { font-weight: bold; background: #fffbf0; }
    .footer { margin-top: 32px; font-size: 11px; color: #999; text-align: center; border-top: 1px solid #eee; padding-top: 16px; }
    .nights-badge { background: #F4A024; color: #fff; padding: 2px 8px; border-radius: 4px; font-size: 12px; }
    @media print { .container { max-width: 100%; } }
  </style>
</head>
<body>
<div class="container">
  <div class="header">
    <div>
      <h1>7DASH Travel</h1>
      <div class="status-badge">CONFIRMED</div>
    </div>
    <div class="ref">
      <div><strong>Booking Reference</strong></div>
      <div style="font-size:18px;font-weight:bold;color:#1a1a1a">${booking.hotelbeds_reference}</div>
      <div>Agency Ref: ${booking.agency_reference}</div>
      <div>Issued: ${new Date().toLocaleDateString()}</div>
    </div>
  </div>

  <section>
    <h2>Hotel Details</h2>
    <div class="grid">
      <div><div class="label">Hotel</div><div class="value">${booking.hotel_name}</div></div>
      <div><div class="label">Category</div><div class="value">${booking.hotel_category ?? "–"}</div></div>
      <div><div class="label">Address</div><div class="value">${booking.hotel_address ?? "–"}</div></div>
      <div><div class="label">City</div><div class="value">${booking.hotel_city ?? "–"}</div></div>
      <div><div class="label">Phone</div><div class="value">${booking.hotel_phone ?? "–"}</div></div>
      <div><div class="label">Destination</div><div class="value">${booking.destination_name ?? "–"}</div></div>
    </div>
  </section>

  <section>
    <h2>Stay Details</h2>
    <div class="grid">
      <div><div class="label">Check-in</div><div class="value">${booking.check_in}</div></div>
      <div><div class="label">Check-out</div><div class="value">${booking.check_out}</div></div>
      <div><div class="label">Duration</div><div class="value"><span class="nights-badge">${booking.nights} night${Number(booking.nights) !== 1 ? "s" : ""}</span></div></div>
      <div><div class="label">Rooms</div><div class="value">${booking.rooms}</div></div>
      <div><div class="label">Room Type</div><div class="value">${booking.room_type ?? "–"}</div></div>
      <div><div class="label">Board</div><div class="value">${booking.board_type ?? booking.board_code ?? "–"}</div></div>
      <div><div class="label">Adults</div><div class="value">${booking.adults}</div></div>
      <div><div class="label">Children</div><div class="value">${booking.children}</div></div>
    </div>
  </section>

  <section>
    <h2>Guest Details</h2>
    <div class="grid">
      <div><div class="label">Lead Guest</div><div class="value">${booking.holder_first_name} ${booking.holder_last_name}</div></div>
      <div><div class="label">Email</div><div class="value">${booking.holder_email}</div></div>
      ${booking.holder_phone ? `<div><div class="label">Phone</div><div class="value">${booking.holder_phone}</div></div>` : ""}
    </div>
    ${passengerRows ? `<br/><table><thead><tr><th>Name</th><th>Type</th><th>Room</th></tr></thead><tbody>${passengerRows}</tbody></table>` : ""}
  </section>

  <section>
    <h2>Price Summary</h2>
    <table>
      <thead><tr><th>Item</th><th style="text-align:right">Amount</th></tr></thead>
      <tbody>
        <tr><td>Room Rate</td><td style="text-align:right">${booking.currency} ${Number(booking.base_amount).toFixed(2)}</td></tr>
        <tr><td>Service Fee</td><td style="text-align:right">${booking.currency} ${Number(booking.service_fee ?? 0).toFixed(2)}</td></tr>
        <tr class="total-row"><td>Total Charged</td><td style="text-align:right">${booking.currency} ${Number(booking.total_amount).toFixed(2)}</td></tr>
      </tbody>
    </table>
  </section>

  ${cancellationPolicies.length > 0 ? `
  <section>
    <h2>Cancellation Policy</h2>
    <table>
      <thead><tr><th>Cancellation Fee</th><th>From Date</th></tr></thead>
      <tbody>${policyRows}</tbody>
    </table>
    ${booking.rate_comments ? `<p style="margin-top:8px;font-size:12px;color:#555">${booking.rate_comments}</p>` : ""}
  </section>` : ""}

  <div class="footer">
    <p>This voucher is your proof of booking. Please present it at check-in.</p>
    <p>For support, contact 7DASH Travel Support.</p>
    <p style="margin-top:8px">Generated by 7DASH &bull; ${new Date().toISOString()}</p>
  </div>
</div>
</body>
</html>`;
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

    const token = authHeader.replace("Bearer ", "");
    const jwtPayload = JSON.parse(atob(token.split(".")[1])) as { sub: string };
    const userId = jwtPayload.sub;

    const url = new URL(req.url);
    const bookingId = url.searchParams.get("booking_id");
    const format = url.searchParams.get("format") ?? "html"; // html or json

    if (!bookingId) {
      return new Response(JSON.stringify({ error: "booking_id is required" }), { status: 400, headers: corsHeaders });
    }

    const { data: booking } = await supabase
      .from("hotel_bookings")
      .select("*")
      .eq("id", bookingId)
      .single();

    if (!booking) {
      return new Response(JSON.stringify({ error: "Booking not found" }), { status: 404, headers: corsHeaders });
    }

    const { data: userRow } = await supabase.from("users").select("role").eq("id", userId).single();
    const isAdmin = userRow?.role === "admin";
    if (!isAdmin && booking.user_id !== userId) {
      return new Response(JSON.stringify({ error: "Forbidden" }), { status: 403, headers: corsHeaders });
    }

    if (booking.booking_status !== "confirmed") {
      return new Response(JSON.stringify({ error: "Voucher only available for confirmed bookings" }), { status: 409, headers: corsHeaders });
    }

    if (format === "html") {
      const html = buildVoucherHtml(booking as Record<string, unknown>);
      return new Response(html, {
        headers: {
          ...corsHeaders,
          "Content-Type": "text/html; charset=utf-8",
          "Content-Disposition": `inline; filename="voucher-${booking.hotelbeds_reference}.html"`,
        },
      });
    }

    // JSON format — return structured voucher data
    return new Response(JSON.stringify({
      voucher: {
        reference: booking.hotelbeds_reference,
        agency_reference: booking.agency_reference,
        hotel_name: booking.hotel_name,
        hotel_address: booking.hotel_address,
        hotel_city: booking.hotel_city,
        hotel_phone: booking.hotel_phone,
        check_in: booking.check_in,
        check_out: booking.check_out,
        nights: booking.nights,
        rooms: booking.rooms,
        adults: booking.adults,
        children: booking.children,
        room_type: booking.room_type,
        board_type: booking.board_type,
        holder_name: `${booking.holder_first_name} ${booking.holder_last_name}`,
        holder_email: booking.holder_email,
        total_amount: booking.total_amount,
        currency: booking.currency,
        booking_status: booking.booking_status,
        cancellation_policies: booking.cancellation_policies,
        issued_at: new Date().toISOString(),
      },
    }), { headers: corsHeaders });

  } catch (err) {
    console.error("hotelbeds-generate-voucher error:", err);
    return new Response(JSON.stringify({ error: (err as Error).message }), { status: 500, headers: corsHeaders });
  }
});

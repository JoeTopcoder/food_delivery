import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { corsHeaders } from "../_shared/cors.ts";

interface RespondToRideRequestPayload {
  ride_driver_request_id: string;
  action: "accept" | "reject";
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return new Response(
        JSON.stringify({ error: "Missing authorization header" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const token = authHeader.replace("Bearer ", "");
    const jwtParts = token.split(".");
    if (jwtParts.length !== 3) {
      return new Response(
        JSON.stringify({ error: "Malformed authorization token" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const decodedPayload = JSON.parse(atob(jwtParts[1])) as { sub: string };
    const userId = decodedPayload.sub;

    let body: RespondToRideRequestPayload;
    try {
      body = await req.json() as RespondToRideRequestPayload;
    } catch {
      return new Response(
        JSON.stringify({ error: "Invalid JSON body" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { ride_driver_request_id, action } = body;

    if (!ride_driver_request_id || !action) {
      return new Response(
        JSON.stringify({ error: "ride_driver_request_id and action are required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (action !== "accept" && action !== "reject") {
      return new Response(
        JSON.stringify({ error: "action must be 'accept' or 'reject'" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL") ?? "",
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? ""
    );

    const { data: driver, error: driverError } = await supabase
      .from("drivers")
      .select("id, user_id")
      .eq("user_id", userId)
      .single();

    if (driverError || !driver) {
      return new Response(
        JSON.stringify({ error: "Driver profile not found" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const { data: driverRequest, error: requestError } = await supabase
      .from("ride_driver_requests")
      .select("id, ride_id, driver_id, status, expires_at")
      .eq("id", ride_driver_request_id)
      .single();

    if (requestError || !driverRequest) {
      return new Response(
        JSON.stringify({ error: "Ride driver request not found" }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (driverRequest.driver_id !== driver.id) {
      return new Response(
        JSON.stringify({ error: "This request does not belong to you" }),
        { status: 403, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (driverRequest.status !== "pending") {
      return new Response(
        JSON.stringify({ error: "Request is no longer pending", current_status: driverRequest.status }),
        { status: 409, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    if (new Date(driverRequest.expires_at) < new Date()) {
      return new Response(
        JSON.stringify({ error: "This ride request has expired" }),
        { status: 410, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const respondedAt = new Date().toISOString();

    if (action === "reject") {
      const { error: rejectError } = await supabase
        .from("ride_driver_requests")
        .update({ status: "rejected", responded_at: respondedAt })
        .eq("id", ride_driver_request_id);

      if (rejectError) {
        return new Response(
          JSON.stringify({ error: "Failed to reject ride request" }),
          { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ accepted: false }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Accept = driver is offering — mark as 'offered', do NOT auto-assign.
    // The customer will see this offer and choose whether to accept.
    // Atomic guard: WHERE status='pending' ensures only one concurrent accept wins.
    const { data: offeredRows, error: offerError } = await supabase
      .from("ride_driver_requests")
      .update({ status: "offered", responded_at: respondedAt })
      .eq("id", ride_driver_request_id)
      .eq("status", "pending")
      .eq("driver_id", driver.id)
      .select("id");

    if (offerError) {
      return new Response(
        JSON.stringify({ error: "Failed to offer ride request" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // If no rows updated the request was already processed (idempotent success)
    if (!offeredRows || offeredRows.length === 0) {
      return new Response(
        JSON.stringify({ accepted: true, waiting_for_customer: true, ride_id: driverRequest.ride_id }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Return accepted:true so the driver popup navigates correctly.
    return new Response(
      JSON.stringify({ accepted: true, waiting_for_customer: true, ride_id: driverRequest.ride_id }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  } catch (error) {
    console.error("Error in respond_to_ride_request:", error);
    return new Response(
      JSON.stringify({ error: "Internal server error", details: (error as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});

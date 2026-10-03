// Restaurant Pickup Coordinator — places the 15-minute follow-up as a real
// Agora in-app voice call, using the AI's own account (HotBite Assistant).
//
//   action "dial_due" — refresh the queue, then for each queued call:
//        pickup_begin_dial() re-checks conditions → creates a `calls` row
//        (caller = AI account, receiver = restaurant owner) → starts the Agora
//        Conversational AI voice bot in that channel with the pickup script →
//        rings the restaurant via send-call-notification. The restaurant answers
//        in-app and talks to the AI.
//   action "outcome"  — the bot's function-call (or an operator) posts the
//        captured answers here → pickup_record_call_outcome() applies the rules.
//   action "run_jobs" — execute due authorized auto-Ready jobs.
//
// Auth: service-role JWT or AUTOMATION_RUNNER_SECRET.
// Secrets reused from agora-ai-agent: AGORA_APP_ID, AGORA_APP_CERTIFICATE,
// AGORA_CUSTOMER_KEY, AGORA_CUSTOMER_SECRET, OPENAI_API_KEY.

// deno-lint-ignore-file
declare const Deno: { env: { get(k: string): string | undefined }; serve(h: (r: Request) => Response | Promise<Response>): void };
// @ts-ignore
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.49.8";
// @ts-ignore
import { RtcTokenBuilder, RtcRole } from "npm:agora-access-token";

const URL = Deno.env.get("SUPABASE_URL") ?? "";
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const RUNNER_SECRET = Deno.env.get("AUTOMATION_RUNNER_SECRET") ?? "";
const AGORA_APP_ID = Deno.env.get("AGORA_APP_ID") ?? "";
const AGORA_APP_CERTIFICATE = Deno.env.get("AGORA_APP_CERTIFICATE") ?? "";
const AGORA_CUSTOMER_KEY = Deno.env.get("AGORA_CUSTOMER_KEY") ?? "";
const AGORA_CUSTOMER_SECRET = Deno.env.get("AGORA_CUSTOMER_SECRET") ?? "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";

const AGENT_UID = 12345;
const TOKEN_TTL = 3600;
const admin = createClient(URL, SERVICE_KEY);

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

function jwtRole(token: string): string | null {
  try {
    const payload = token.split(".")[1];
    const json = atob(payload.replace(/-/g, "+").replace(/_/g, "/"));
    return (JSON.parse(json).role as string) ?? null;
  } catch { return null; }
}

function authorized(req: Request): boolean {
  const h = req.headers.get("Authorization") ?? "";
  const token = h.startsWith("Bearer ") ? h.slice(7) : "";
  if (RUNNER_SECRET && token === RUNNER_SECRET) return true;
  if (SERVICE_KEY && token === SERVICE_KEY) return true;
  // Accept a service_role JWT regardless of the env key format (legacy vs sb_secret).
  return jwtRole(token) === "service_role";
}

// The exact spoken announcement (letter/digit order ref, read out clearly).
function announcement(orderRef: string): string {
  const spelled = orderRef.split("").join(" ");
  return `Good day. Please can you start preparing order ${spelled}. Thank you.`;
}

function announcerPrompt(orderRef: string): string {
  return (
    `You are HotBite's automated assistant placing a one-line courtesy call. Your ONLY message is: ` +
    `"${announcement(orderRef)}". Say it once, clearly. Do not ask questions, do not hold a conversation, ` +
    `and do not say anything else no matter what the other person says. After delivering the message, stay silent.`
  );
}

function buildToken(channel: string, uid: number): string {
  const expiry = Math.floor(Date.now() / 1000) + TOKEN_TTL;
  return RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID, AGORA_APP_CERTIFICATE, channel, uid, RtcRole.PUBLISHER, expiry, expiry,
  );
}

// Start the Agora Conversational AI voice bot in the channel (v2 API: everything
// nested under `properties`, agent_rtc_uid as a string, OpenAI TTS). Returns the
// agent_id, or null with the error captured for the caller to record.
async function startVoiceBot(channel: string, orderRef: string): Promise<{ agentId: string | null; error?: string }> {
  if (!AGORA_CUSTOMER_KEY || !AGORA_CUSTOMER_SECRET || !OPENAI_API_KEY) {
    return { agentId: null, error: "agora/openai secrets missing" };
  }
  const agentToken = buildToken(channel, AGENT_UID);
  const basic = btoa(`${AGORA_CUSTOMER_KEY}:${AGORA_CUSTOMER_SECRET}`);
  const resp = await fetch(
    `https://api.agora.io/api/conversational-ai-agent/v2/projects/${AGORA_APP_ID}/join`,
    {
      method: "POST",
      headers: { Authorization: `Basic ${basic}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        name: `pickup_${Date.now()}`,
        properties: {
          channel,
          token: agentToken,
          agent_rtc_uid: String(AGENT_UID),
          remote_rtc_uids: ["*"],
          enable_string_uid: false,
          idle_timeout: 12, // hang up shortly after the one-line announcement
          asr: { language: "en-US" },
          llm: {
            url: "https://api.openai.com/v1/chat/completions",
            api_key: OPENAI_API_KEY,
            system_messages: [{ role: "system", content: announcerPrompt(orderRef) }],
            params: { model: "gpt-4o-mini", max_tokens: 60, temperature: 0 },
            greeting_message: announcement(orderRef),
          },
          // ElevenLabs streams and sounds smoothest; used automatically when an
          // ELEVENLABS_API_KEY is set. Otherwise OpenAI's HD model (still smoother
          // than tts-1) with a natural voice.
          tts: Deno.env.get("ELEVENLABS_API_KEY")
            ? {
                vendor: "elevenlabs",
                params: {
                  key: Deno.env.get("ELEVENLABS_API_KEY"),
                  model_id: "eleven_flash_v2_5",
                  voice_id: Deno.env.get("ELEVENLABS_VOICE_ID") ?? "21m00Tcm4TlvDq8ikWAM",
                  sample_rate: 24000,
                },
              }
            : { vendor: "openai", params: { api_key: OPENAI_API_KEY, model: "tts-1-hd", voice: "nova", speed: 1.0 } },
        },
      }),
    },
  );
  if (!resp.ok) {
    const err = await resp.text();
    console.error("agent join failed:", err);
    return { agentId: null, error: err.slice(0, 300) };
  }
  const d = await resp.json();
  return { agentId: d.agent_id ?? null };
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (!authorized(req)) return json({ error: "UNAUTHORIZED" }, 401);

  let body: Record<string, unknown> = {};
  try { body = await req.json(); } catch { /* empty ok */ }
  const action = (body.action as string) ?? "dial_due";

  try {
    if (action === "dial_due") {
      await admin.rpc("pickup_scan_and_enqueue");

      // The AI's own account is the caller.
      const { data: aiCfg } = await admin.from("app_config")
        .select("value").eq("key", "pickup_ai_account_id").maybeSingle();
      const aiAccountId = aiCfg?.value as string | undefined;
      if (!aiAccountId) return json({ error: "pickup_ai_account_id not configured" }, 500);

      const { data: calls } = await admin.from("restaurant_pickup_calls")
        .select("id, order_id, restaurant_id").eq("status", "queued").limit(25);

      let placed = 0, skipped = 0, agentless = 0;
      for (const c of calls ?? []) {
        const { data: begin } = await admin.rpc("pickup_begin_dial", { p_call_id: c.id });
        if (!begin?.ok) { skipped++; continue; }

        // Receiver = restaurant owner.
        const { data: rest } = await admin.from("restaurants")
          .select("owner_id, name").eq("id", c.restaurant_id).maybeSingle();
        if (!rest?.owner_id) { skipped++; continue; }

        const channel = `pickup_${String(c.order_id).slice(0, 8)}_${Date.now()}`;
        const receiverToken = buildToken(channel, 0);

        // Create the in-app call row (caller = AI, receiver = restaurant owner).
        const { data: callRow } = await admin.from("calls").insert({
          order_id: c.order_id,
          caller_id: aiAccountId,
          receiver_id: rest.owner_id,
          channel_name: channel,
          agora_token: receiverToken,
          status: "ringing",
        }).select("id").single();

        // Ring the restaurant so their app shows the incoming HotBite call. The
        // announcer bot is NOT started here — it starts the moment they ANSWER
        // (via the "announce" action, fired by the calls-answered DB trigger) so
        // the one-line message lands when someone is actually on the line.
        await admin.functions.invoke("send-call-notification", {
          body: {
            recipientUserId: rest.owner_id,
            callerName: "HotBite Assistant",
            callId: callRow?.id,
            callerId: aiAccountId,
            orderId: c.order_id,
            channelName: channel,
          },
        }).catch(() => {});

        await admin.from("restaurant_pickup_calls").update({
          channel_name: channel,
          agora_call_id: callRow?.id ?? null,
          notes: "ringing — announcer starts on answer",
        }).eq("id", c.id);

        placed++;
      }
      return json({ ok: true, placed, skipped });
    }

    // Fired when the restaurant ANSWERS: start the one-line announcer bot.
    if (action === "announce") {
      const pickupCallId = body.pickup_call_id as string | undefined;
      const agoraCallId = body.agora_call_id as string | undefined;
      const q = admin.from("restaurant_pickup_calls").select("id, order_id, channel_name, agent_id");
      const { data: pc } = await (pickupCallId
        ? q.eq("id", pickupCallId)
        : q.eq("agora_call_id", agoraCallId)).maybeSingle();
      if (!pc?.channel_name) return json({ error: "call_not_found_or_no_channel" }, 404);
      if (pc.agent_id) return json({ ok: true, idempotent: true }); // already announced
      const orderRef = String(pc.order_id).slice(0, 8).toUpperCase();
      const bot = await startVoiceBot(pc.channel_name, orderRef);
      await admin.from("restaurant_pickup_calls").update({
        agent_id: bot.agentId,
        notes: bot.agentId ? "announcer running" : `announcer failed: ${bot.error ?? "unknown"}`,
      }).eq("id", pc.id);
      return json({ ok: !!bot.agentId, agent_id: bot.agentId, error: bot.error });
    }

    if (action === "outcome") {
      const { data, error } = await admin.rpc("pickup_record_call_outcome", {
        p_call_id: body.call_id,
        p_prep_underway: body.prep_underway ?? null,
        p_ready_now: body.ready_now ?? false,
        p_confirmed_ready_at: body.confirmed_ready_at ?? null,
        p_auto_authorized: body.auto_authorized ?? false,
        p_delay_reported: body.delay_reported ?? false,
        p_unfulfillable: body.unfulfillable ?? false,
        p_notes: body.notes ?? null,
      });
      if (error) return json({ error: error.message }, 400);
      return json({ ok: true, result: data });
    }

    if (action === "run_jobs") {
      const { data } = await admin.rpc("pickup_run_ready_jobs");
      return json({ ok: true, result: data });
    }

    return json({ error: `Unknown action: ${action}` }, 400);
  } catch (e) {
    return json({ error: "server_error", details: `${e}` }, 500);
  }
});

// Agora Conversational AI Agent — starts/stops an AI voice agent in an RTC channel.
// POST { action:'start', role, order_id?, language? } → { channel_name, user_token, agent_id, agent_uid }
// POST { action:'stop',  agent_id }                   → { stopped: true }
//
// Required secrets:
//   AGORA_APP_ID, AGORA_APP_CERTIFICATE  — already set
//   AGORA_CUSTOMER_KEY, AGORA_CUSTOMER_SECRET — from Agora Console → Project Management → RESTful API
//   OPENAI_API_KEY — already set (LLM)

// @ts-ignore
import { RtcTokenBuilder, RtcRole } from 'npm:agora-access-token'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const AGORA_APP_ID          = Deno.env.get('AGORA_APP_ID') ?? ''
const AGORA_APP_CERTIFICATE = Deno.env.get('AGORA_APP_CERTIFICATE') ?? ''
const AGORA_CUSTOMER_KEY    = Deno.env.get('AGORA_CUSTOMER_KEY') ?? ''
const AGORA_CUSTOMER_SECRET = Deno.env.get('AGORA_CUSTOMER_SECRET') ?? ''
const OPENAI_API_KEY        = Deno.env.get('OPENAI_API_KEY') ?? ''

const AGENT_UID = 12345
const TOKEN_TTL = 7200  // 2-hour token

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  // ── Auth ────────────────────────────────────────────────────────────────────
  const authHeader = req.headers.get('Authorization')
  if (!authHeader) return json({ error: 'Unauthorized' }, 401)

  const userClient = createClient(
    Deno.env.get('SUPABASE_URL') ?? '',
    Deno.env.get('SUPABASE_ANON_KEY') ?? '',
    { global: { headers: { Authorization: authHeader } } },
  )
  const { data: { user }, error: authError } = await userClient.auth.getUser()
  if (authError || !user) return json({ error: 'Unauthorized' }, 401)

  const body = await req.json()
  const { action } = body

  // ── Stop agent ──────────────────────────────────────────────────────────────
  if (action === 'stop') {
    const { agent_id } = body
    if (!agent_id) return json({ error: 'agent_id required' }, 400)
    if (AGORA_CUSTOMER_KEY && AGORA_CUSTOMER_SECRET) {
      try {
        const basicAuth = btoa(`${AGORA_CUSTOMER_KEY}:${AGORA_CUSTOMER_SECRET}`)
        await fetch(
          `https://api.agora.io/api/conversational-ai/v2/projects/${AGORA_APP_ID}/leave/${agent_id}`,
          { method: 'DELETE', headers: { Authorization: `Basic ${basicAuth}` } },
        )
      } catch (e) {
        console.error('Stop agent error (non-fatal):', e)
      }
    }
    return json({ stopped: true })
  }

  // ── Start agent ─────────────────────────────────────────────────────────────
  const { role, order_id, language } = body

  // Validate required secrets
  const missing: string[] = []
  if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE)       missing.push('AGORA_APP_ID / AGORA_APP_CERTIFICATE')
  if (!AGORA_CUSTOMER_KEY || !AGORA_CUSTOMER_SECRET) missing.push('AGORA_CUSTOMER_KEY + AGORA_CUSTOMER_SECRET (Agora Console → Project Management → RESTful API)')
  if (!OPENAI_API_KEY)                               missing.push('OPENAI_API_KEY')
  if (missing.length > 0) {
    return json({ error: `Missing secrets: ${missing.join(', ')}` }, 503)
  }

  // Unique channel for this session
  const channelName = `ai_${user.id.slice(0, 8)}_${Date.now()}`
  const expiry      = Math.floor(Date.now() / 1000) + TOKEN_TTL

  // User token (uid=0 → Agora auto-assigns)
  const userToken = RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID, AGORA_APP_CERTIFICATE,
    channelName, 0, RtcRole.PUBLISHER, expiry, expiry,
  )

  // AI agent token (fixed uid)
  const agentToken = RtcTokenBuilder.buildTokenWithUid(
    AGORA_APP_ID, AGORA_APP_CERTIFICATE,
    channelName, AGENT_UID, RtcRole.PUBLISHER, expiry, expiry,
  )

  // Fetch order context if provided
  let orderContext = ''
  if (order_id) {
    try {
      const svc = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      )
      const { data: order } = await svc
        .from('orders')
        .select('id, status, total_amount, ordered_at, restaurants(name)')
        .eq('id', order_id)
        .eq('user_id', user.id)
        .maybeSingle()
      if (order) {
        const rest = (order.restaurants as any)?.name ?? 'the restaurant'
        const mins = Math.round((Date.now() - new Date(order.ordered_at).getTime()) / 60_000)
        orderContext = ` Active order: from ${rest}, status "${order.status}", placed ${mins} min ago, total $${Number(order.total_amount).toFixed(2)}.`
      }
    } catch (_) {}
  }

  const systemPrompt = buildSystemPrompt(role ?? 'customer', orderContext)

  // Start agent via Agora Conversational AI REST API
  const basicAuth = btoa(`${AGORA_CUSTOMER_KEY}:${AGORA_CUSTOMER_SECRET}`)

  const agentResp = await fetch(
    `https://api.agora.io/api/conversational-ai/v2/projects/${AGORA_APP_ID}/join`,
    {
      method: 'POST',
      headers: {
        Authorization: `Basic ${basicAuth}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        name: `7dash_${Date.now()}`,
        properties: {
          channel: channelName,
          token: agentToken,
          agent_rtc_uid: AGENT_UID,
          remote_rtc_uids: ['*'],
          enable_string_uid: false,
          idle_timeout: 60,
        },
        llm: {
          url: 'https://api.openai.com/v1/chat/completions',
          api_key: OPENAI_API_KEY,
          system_messages: [{ role: 'system', content: systemPrompt }],
          model: 'gpt-4o-mini',
          max_tokens: 150,
          temperature: 0.3,
        },
        // Agora's built-in TTS — billed through your Agora account, no external key needed
        tts: {
          vendor: 'agora',
          params: {
            voice: language === 'es' ? 'female-es-MX-1' : 'female-en-US-1',
          },
        },
        // Agora's built-in STT — billed through your Agora account, no external key needed
        stt: {
          vendor: 'agora',
          params: {
            language: language ?? 'en-US',
          },
        },
        vad: { silence_timeout: 800 },
      }),
    },
  )

  if (!agentResp.ok) {
    const err = await agentResp.text()
    console.error('Agora AI agent start failed:', err)
    return json({ error: 'Failed to start AI agent', details: err }, 502)
  }

  const agentData = await agentResp.json()

  return json({
    channel_name: channelName,
    user_token:   userToken,
    agent_id:     agentData.agent_id,
    agent_uid:    AGENT_UID,
  })
})

function buildSystemPrompt(role: string, orderCtx: string): string {
  const base = `You are the 7Dash AI assistant for a food delivery platform in the Cayman Islands. Be warm, concise, and helpful. Keep responses SHORT — 1 to 2 sentences max — this is a live voice call.${orderCtx}`
  switch (role) {
    case 'driver': return `${base} You are helping a delivery driver. Assist with deliveries, navigation, earnings, and order issues.`
    case 'admin':  return `${base} You are helping a platform admin. Assist with orders, drivers, restaurants, and analytics.`
    default:       return `${base} You are helping a customer. Assist with order status, ETAs, cancellations, delivery issues, and promotions.`
  }
}

// Agora RTC Token Generator Edge Function
// Generates temporary Agora RTC tokens for authenticated users.
// Requires env vars: AGORA_APP_ID, AGORA_APP_CERTIFICATE

// @ts-ignore: Deno URL import
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
// @ts-ignore: Deno npm specifier
import { RtcTokenBuilder, RtcRole } from 'npm:agora-access-token'

const AGORA_APP_ID = Deno.env.get('AGORA_APP_ID') ?? ''
const AGORA_APP_CERTIFICATE = Deno.env.get('AGORA_APP_CERTIFICATE') ?? ''

Deno.serve(async (req: Request) => {
  try {
    // Check Agora config first — fail fast before any DB queries
    if (!AGORA_APP_ID || !AGORA_APP_CERTIFICATE) {
      console.error('Agora secrets not configured')
      return new Response(JSON.stringify({
        error: 'Agora not configured: missing AGORA_APP_ID or AGORA_APP_CERTIFICATE',
      }), {
        status: 503,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Verify auth
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'No authorization header' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Use service role to bypass RLS and verify user JWT
    const serviceClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    )

    // Verify the user JWT using service role client (avoids ES256 algorithm issues)
    const jwt = authHeader.replace('Bearer ', '')
    const { data: { user }, error: authError } = await serviceClient.auth.getUser(jwt)
    if (authError || !user) {
      console.error('Auth error:', authError?.message)
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        status: 401,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    const { channelName, callId } = await req.json()

    if (!channelName || !callId) {
      return new Response(JSON.stringify({ error: 'channelName and callId required' }), {
        status: 400,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    console.log(`Token request: user=${user.id} callId=${callId} channel=${channelName}`)

    // Look up call using service role (bypasses RLS)
    const { data: call, error: callError } = await serviceClient
      .from('calls')
      .select('id, caller_id, receiver_id, status')
      .eq('id', callId)
      .single()

    if (callError) {
      console.error('Call lookup error:', callError.message, 'code:', callError.code)
      return new Response(JSON.stringify({ error: `Call lookup failed: ${callError.message}` }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (!call) {
      return new Response(JSON.stringify({ error: 'Call not found' }), {
        status: 404,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    if (call.caller_id !== user.id && call.receiver_id !== user.id) {
      console.error(`User ${user.id} not authorized for call. caller=${call.caller_id} receiver=${call.receiver_id}`)
      return new Response(JSON.stringify({ error: 'Not authorized for this call' }), {
        status: 403,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Don't issue tokens for calls that have already ended
    const terminalStatuses = ['ended', 'missed', 'declined', 'failed']
    if (terminalStatuses.includes(call.status)) {
      return new Response(JSON.stringify({ error: `Call already ended (status: ${call.status})` }), {
        status: 410,
        headers: { 'Content-Type': 'application/json' },
      })
    }

    // Generate token — expires in 1 hour
    const uid = 0
    const privilegeExpiredTs = Math.floor(Date.now() / 1000) + 3600

    console.log(`Generating token: appId=${AGORA_APP_ID.substring(0, 8)}..., channel=${channelName}`)

    const agoraToken = RtcTokenBuilder.buildTokenWithUid(
      AGORA_APP_ID,
      AGORA_APP_CERTIFICATE,
      channelName,
      uid,
      RtcRole.PUBLISHER,
      privilegeExpiredTs,
    )

    console.log(`Token generated: length=${agoraToken.length}`)

    // Write token to calls table using service role
    await serviceClient
      .from('calls')
      .update({ agora_token: agoraToken })
      .eq('id', callId)

    return new Response(JSON.stringify({
      token: agoraToken,
      appId: AGORA_APP_ID,
      channelName,
      uid,
    }), {
      status: 200,
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (err: unknown) {
    const message = err instanceof Error ? err.message : String(err)
    console.error('Unhandled error:', message)
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { 'Content-Type': 'application/json' },
    })
  }
})

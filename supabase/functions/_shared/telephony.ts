// _shared/telephony.ts — provider-isolated telephone bridge.
//
// All Twilio-specific code is confined here so the provider can be swapped
// later. Selection: Twilio is used only when creds AND app_config provider are
// set; otherwise a clearly-labelled MOCK provider is used (no real/paid calls).
//
// Privacy: the customer's number is only ever passed to the provider here on the
// server. Callers (edge functions) pass phone numbers in, never out to clients.

declare const Deno: { env: { get(k: string): string | undefined } }

export interface StartDriverLegArgs {
  fallbackId: string
  driverPhone: string          // E.164, server-resolved
  callerId: string             // approved HotBite caller ID
  voiceWebhookUrl: string      // TwiML url (driver leg -> gather press 1)
  statusCallbackUrl: string
}
export interface LegResult { ok: boolean; sid?: string; mock?: boolean; error?: string }

export interface TelephonyProvider {
  readonly name: string
  readonly isMock: boolean
  startDriverLeg(a: StartDriverLegArgs): Promise<LegResult>
  endCall(sid: string): Promise<void>
}

// ── Twilio ──────────────────────────────────────────────────────────────────
// Auth: basic auth with either the Account SID + Auth Token, or an API Key SID
// (SK…) + its secret. In BOTH cases the REST path uses the Account SID (AC…).
class TwilioProvider implements TelephonyProvider {
  name = 'twilio'; isMock = false
  constructor(private accountSid: string, private authUser: string, private authPass: string) {}
  private auth() { return 'Basic ' + btoa(`${this.authUser}:${this.authPass}`) }

  async startDriverLeg(a: StartDriverLegArgs): Promise<LegResult> {
    // Call the DRIVER first. The TwiML at voiceWebhookUrl plays "press 1" and,
    // on digit 1, dials the customer with the HotBite caller ID (set in TwiML).
    const body = new URLSearchParams({
      To: a.driverPhone,
      From: a.callerId,
      Url: a.voiceWebhookUrl,
      StatusCallback: a.statusCallbackUrl,
      'StatusCallbackEvent': 'initiated ringing answered completed',
      Timeout: '30',
    })
    const resp = await fetch(`https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Calls.json`, {
      method: 'POST',
      headers: { Authorization: this.auth(), 'Content-Type': 'application/x-www-form-urlencoded' },
      body: body.toString(),
    })
    if (!resp.ok) return { ok: false, error: `twilio_${resp.status}` }
    const d = await resp.json()
    return { ok: true, sid: d.sid }
  }

  async endCall(sid: string): Promise<void> {
    try {
      await fetch(`https://api.twilio.com/2010-04-01/Accounts/${this.accountSid}/Calls/${sid}.json`, {
        method: 'POST',
        headers: { Authorization: this.auth(), 'Content-Type': 'application/x-www-form-urlencoded' },
        body: 'Status=completed',
      })
    } catch { /* best-effort */ }
  }
}

// ── Mock (no real calls; never presented to users as real) ──────────────────
class MockProvider implements TelephonyProvider {
  name = 'mock'; isMock = true
  async startDriverLeg(_a: StartDriverLegArgs): Promise<LegResult> {
    return { ok: true, sid: 'MOCK_' + crypto.randomUUID(), mock: true }
  }
  async endCall(_sid: string): Promise<void> { /* no-op */ }
}

// Twilio Programmable Voice signs webhooks with X-Twilio-Signature (HMAC-SHA1 of
// the full URL + sorted POST params, base64). Verify before trusting a callback.
export async function verifyTwilioSignature(
  authToken: string, url: string, params: Record<string, string>, signature: string,
): Promise<boolean> {
  try {
    const sorted = Object.keys(params).sort().map(k => k + params[k]).join('')
    const data = url + sorted
    const key = await crypto.subtle.importKey(
      'raw', new TextEncoder().encode(authToken),
      { name: 'HMAC', hash: 'SHA-1' }, false, ['sign'])
    const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(data))
    const expected = btoa(String.fromCharCode(...new Uint8Array(mac)))
    return expected === signature
  } catch { return false }
}

export function getProvider(): TelephonyProvider {
  const accountSid = Deno.env.get('TWILIO_ACCOUNT_SID') ?? ''   // AC…
  const authToken  = Deno.env.get('TWILIO_AUTH_TOKEN') ?? ''
  const apiKeySid  = Deno.env.get('TWILIO_API_KEY_SID') ?? ''   // SK…
  const apiKeySecret = Deno.env.get('TWILIO_API_KEY_SECRET') ?? ''
  const configured = (Deno.env.get('CALL_FALLBACK_PROVIDER') ?? 'mock').toLowerCase()
  if (configured === 'twilio' && accountSid) {
    // Prefer API key auth when present, else Account SID + Auth Token.
    if (apiKeySid && apiKeySecret) return new TwilioProvider(accountSid, apiKeySid, apiKeySecret)
    if (authToken) return new TwilioProvider(accountSid, accountSid, authToken)
  }
  return new MockProvider()
}

export function getCallerId(): string {
  return Deno.env.get('TWILIO_CALLER_ID') ?? '+10000000000'
}
export function getTwilioAuthToken(): string {
  return Deno.env.get('TWILIO_AUTH_TOKEN') ?? ''
}

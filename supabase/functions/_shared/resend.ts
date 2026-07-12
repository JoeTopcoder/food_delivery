// _shared/resend.ts — single Resend send path, shared by every function that
// emails a customer (receipts, retention outreach, and so on).
//
// FROM prefers the real support_email on file (app_config) — as of
// 2026-07-12 that domain is verified in Resend — falling back to the
// onboarding@resend.dev sandbox (which only ever reaches the Resend
// account's own inbox) if support_email isn't set.

import { serviceClient } from '../stripe-shared/supabase.ts'

declare const Deno: { env: { get(key: string): string | undefined } }

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FALLBACK_FROM_EMAIL = Deno.env.get('RESEND_FROM_EMAIL') ?? '7Dash <onboarding@resend.dev>'

export async function getDefaultFromEmail(): Promise<string> {
  const { data } = await serviceClient.from('app_config').select('value').eq('key', 'support_email').maybeSingle()
  const email = data?.value ? String(data.value).replace(/"/g, '').trim() : null
  return email ? `7Dash <${email}>` : FALLBACK_FROM_EMAIL
}

export interface SendEmailArgs {
  to: string | string[]
  subject: string
  html: string
  from?: string
}

export interface SendEmailResult {
  ok: boolean
  id?: string
  error?: string
}

export async function sendEmail({ to, subject, html, from }: SendEmailArgs): Promise<SendEmailResult> {
  if (!RESEND_API_KEY) return { ok: false, error: 'RESEND_API_KEY not configured' }
  const resp = await fetch('https://api.resend.com/emails', {
    method: 'POST',
    headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
    body: JSON.stringify({ from: from ?? (await getDefaultFromEmail()), to: Array.isArray(to) ? to : [to], subject, html }),
  })
  if (!resp.ok) {
    return { ok: false, error: await resp.text() }
  }
  const data = await resp.json()
  return { ok: true, id: data?.id }
}

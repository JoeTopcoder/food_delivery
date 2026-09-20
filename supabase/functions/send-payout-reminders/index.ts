// Emails restaurants/drivers who are owed money but have NO bank account on
// file, reminding them to add banking info so they can be paid. Called by the
// admin app right after a payout run. Admin-gated.
import { serviceClient } from '../stripe-shared/supabase.ts'
import { sendEmail } from '../_shared/resend.ts'

declare const Deno: { serve: (h: (r: Request) => Response | Promise<Response>) => void }

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })
}

function reminderHtml(name: string): string {
  const who = name && name.trim() ? name.trim() : 'there'
  return `
  <div style="font-family:-apple-system,Segoe UI,Roboto,Arial,sans-serif;max-width:520px;margin:0 auto;padding:24px;color:#1a1a2e;">
    <h2 style="margin:0 0 12px;">Add your bank details to get paid</h2>
    <p>Hi ${who},</p>
    <p>You have earnings waiting with HotBite, but we couldn't pay you in the
       latest payout run because there are <b>no bank account details on file</b>
       for your account.</p>
    <p>Please open the HotBite app and add your banking information under
       <b>Payments / Banking</b> so we can include you in the next payout.</p>
    <p style="color:#6b7280;font-size:13px;">Once your bank details are saved,
       your balance will be paid in the next run — no further action needed.</p>
    <p style="margin-top:20px;">Thank you,<br/>The HotBite Team</p>
  </div>`
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'method_not_allowed' }, 405)

  try {
    // ── Admin auth ────────────────────────────────────────────────
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    if (!token) return json({ error: 'missing_token' }, 401)
    const { data: userData, error: userErr } = await serviceClient.auth.getUser(token)
    if (userErr || !userData?.user) return json({ error: 'invalid_token' }, 401)
    const { data: caller } = await serviceClient
      .from('users').select('role').eq('id', userData.user.id).maybeSingle()
    if (!caller || caller.role !== 'admin') return json({ error: 'not_authorized' }, 403)

    // ── Find owed-without-bank drivers ────────────────────────────
    const { data: drivers } = await serviceClient
      .from('drivers')
      .select('id, full_name, user_id, total_earnings, total_paid_out, cash_float, bank_account_number')

    const targets: { userId: string; name: string }[] = []
    for (const d of (drivers ?? []) as Record<string, unknown>[]) {
      const bal = (Number(d.total_earnings) || 0) - (Number(d.total_paid_out) || 0)
      const net = bal - (Number(d.cash_float) || 0)
      const owed = bal > 0.005 || net > 0.005
      const noBank = !String(d.bank_account_number ?? '').trim()
      if (owed && noBank && d.user_id) {
        targets.push({ userId: String(d.user_id), name: String(d.full_name ?? '') })
      }
    }

    // ── Find owed-without-bank restaurants ────────────────────────
    const { data: rests } = await serviceClient
      .from('restaurants')
      .select('id, name, owner_id, total_earnings, total_paid_out, bank_account_number')

    for (const r of (rests ?? []) as Record<string, unknown>[]) {
      const bal = (Number(r.total_earnings) || 0) - (Number(r.total_paid_out) || 0)
      const noBank = !String(r.bank_account_number ?? '').trim()
      if (bal > 0.005 && noBank && r.owner_id) {
        targets.push({ userId: String(r.owner_id), name: String(r.name ?? '') })
      }
    }

    if (targets.length === 0) return json({ sent: 0 })

    // ── Resolve emails ────────────────────────────────────────────
    const ids = [...new Set(targets.map((t) => t.userId))]
    const { data: users } = await serviceClient
      .from('users').select('id, email, name').in('id', ids)
    const emailById = new Map<string, string>()
    const nameById = new Map<string, string>()
    for (const u of (users ?? []) as Record<string, unknown>[]) {
      if (u.email) emailById.set(String(u.id), String(u.email))
      if (u.name) nameById.set(String(u.id), String(u.name))
    }

    // ── Send (de-duplicated by email) ─────────────────────────────
    const sentEmails = new Set<string>()
    let sent = 0
    for (const t of targets) {
      const email = emailById.get(t.userId)
      if (!email || sentEmails.has(email)) continue
      sentEmails.add(email)
      const name = t.name || nameById.get(t.userId) || ''
      const res = await sendEmail({
        to: email,
        subject: 'Add your bank details to get paid — HotBite',
        html: reminderHtml(name),
      })
      if (res.ok) sent++
    }

    return json({ sent })
  } catch (e) {
    return json({ error: String(e) }, 500)
  }
})

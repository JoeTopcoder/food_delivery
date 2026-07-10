// support-agent-approve — AI Support Agent (7Dash AI Operations, v1)
// Admin review step for a support-agent-draft output. Only this function may
// send the customer-facing email or move money (wallet credit) — the draft
// function never does either.
// Deploy: supabase functions deploy support-agent-approve

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY') ?? ''
const FROM_EMAIL = Deno.env.get('SUPPORT_FROM_EMAIL') ?? '7Dash Support <onboarding@resend.dev>'

// Wallet credit is the only money-moving action this function will execute
// automatically. "refund_manual" is intentionally NOT auto-executed — there is
// no reliable stored link from an order to its Stripe PaymentIntent for the
// saved-card off-session charge path, so a real Stripe refund must be issued
// by an admin through existing tooling. Auto-crediting is capped as an extra
// safety margin on top of the draft-time clamp to the order total.
const MAX_AUTO_CREDIT = 100

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { support_request_id, decision, final_reply, execute_credit } = await req.json()

    if (!support_request_id) return json({ error: 'BAD_REQUEST: support_request_id required' }, 400)
    if (!['approve', 'reject'].includes(decision)) return json({ error: 'BAD_REQUEST: decision must be approve or reject' }, 400)

    const { data: ticket, error: ticketErr } = await serviceClient
      .from('support_requests')
      .select('*')
      .eq('id', support_request_id)
      .single()

    if (ticketErr || !ticket) return json({ error: 'Support request not found' }, 404)

    // Idempotency — a ticket can only be finalized once.
    if (ticket.ai_status === 'sent' || ticket.ai_status === 'rejected') {
      return json({ error: `Already ${ticket.ai_status} — no further action taken` }, 409)
    }
    if (ticket.ai_status !== 'drafted') {
      return json({ error: 'No pending draft for this ticket. Generate a draft first.' }, 400)
    }

    if (decision === 'reject') {
      await serviceClient
        .from('support_requests')
        .update({ ai_status: 'rejected', reviewed_by: admin.id, reviewed_at: new Date().toISOString() })
        .eq('id', support_request_id)

      await serviceClient.from('ai_agent_runs').insert({
        agent_name: 'support_agent_approve',
        entity_type: 'support_request',
        entity_id: support_request_id,
        input: { decision: 'reject' },
        output: { rejected: true },
        status: 'completed',
        created_by: admin.id,
      })

      return json({ success: true, status: 'rejected' })
    }

    // ── Approve ──────────────────────────────────────────────────────────
    const replyText = String(final_reply ?? ticket.ai_draft_reply ?? '').trim()
    if (!replyText) return json({ error: 'BAD_REQUEST: no reply text to send' }, 400)

    let creditIssued = false
    let creditAmount = 0
    const wantsCredit = execute_credit === true && ticket.ai_suggested_action === 'credit'

    if (wantsCredit) {
      if (!ticket.user_id) {
        return json({ error: 'Cannot issue wallet credit — this ticket has no linked user account (guest submission)' }, 400)
      }
      const amount = Math.min(Number(ticket.ai_suggested_amount) || 0, MAX_AUTO_CREDIT)
      if (amount <= 0) {
        return json({ error: 'BAD_REQUEST: suggested credit amount is not positive' }, 400)
      }
      const { error: creditErr } = await serviceClient.rpc('wallet_credit', {
        p_user_id: ticket.user_id,
        p_amount: amount,
        p_description: `Support resolution — ticket ${support_request_id}`,
      })
      if (creditErr) {
        return json({ error: 'Wallet credit failed', details: creditErr.message }, 500)
      }
      creditIssued = true
      creditAmount = amount
    }

    let emailSent = false
    if (RESEND_API_KEY) {
      const html = `<!DOCTYPE html><html><body style="font-family:-apple-system,sans-serif;max-width:560px;margin:0 auto;padding:24px;color:#1a1a2e;">
        <p>Hi ${escapeHtml(ticket.name || 'there')},</p>
        <p style="white-space:pre-wrap;line-height:1.6;">${escapeHtml(replyText)}</p>
        ${creditIssued ? `<p style="background:#f0fdf4;border:1px solid #bbf7d0;border-radius:8px;padding:12px 16px;color:#16a34a;">We've added a $${creditAmount.toFixed(2)} credit to your 7Dash wallet.</p>` : ''}
        <p style="color:#999;font-size:12px;margin-top:24px;">Reference: ${support_request_id}</p>
      </body></html>`

      const emailResp = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: { Authorization: `Bearer ${RESEND_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          from: FROM_EMAIL,
          to: [ticket.email],
          subject: `Re: Your 7Dash support request (${ticket.category})`,
          html,
        }),
      })
      emailSent = emailResp.ok
      if (!emailResp.ok) {
        console.error('support-agent-approve: Resend send failed', await emailResp.text())
      }
    }

    await serviceClient
      .from('support_requests')
      .update({
        ai_final_reply: replyText,
        ai_status: 'sent',
        status: 'resolved',
        reviewed_by: admin.id,
        reviewed_at: new Date().toISOString(),
      })
      .eq('id', support_request_id)

    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'support_agent_approve',
      entity_type: 'support_request',
      entity_id: support_request_id,
      input: { decision: 'approve', final_reply: replyText, execute_credit: wantsCredit },
      output: { credit_issued: creditIssued, credit_amount: creditAmount, email_sent: emailSent },
      status: 'completed',
      created_by: admin.id,
    })

    return json({ success: true, status: 'sent', email_sent: emailSent, credit_issued: creditIssued, credit_amount: creditAmount })
  } catch (e) {
    return errorResponse(e)
  }
})

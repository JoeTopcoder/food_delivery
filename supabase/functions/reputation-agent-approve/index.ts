// reputation-agent-approve — Reputation Management Agent (7Dash AI Operations)
// Admin approval step. Only this function writes to reviews.response_text —
// the draft function never touches it.
// Deploy: supabase functions deploy reputation-agent-approve --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { review_id, decision, final_response } = await req.json()
    if (!review_id) return json({ error: 'BAD_REQUEST: review_id required' }, 400)
    if (!['approve', 'reject'].includes(decision)) return json({ error: 'BAD_REQUEST: decision must be approve or reject' }, 400)

    const { data: review, error: reviewErr } = await serviceClient
      .from('reviews')
      .select('id, response_text')
      .eq('id', review_id)
      .single()
    if (reviewErr || !review) return json({ error: 'Review not found' }, 404)
    if (review.response_text) return json({ error: 'This review already has a response.' }, 409)

    if (decision === 'reject') {
      await serviceClient.from('ai_agent_runs').insert({
        agent_name: 'reputation_management_approve',
        entity_type: 'review',
        entity_id: review_id,
        input: { decision: 'reject' },
        output: { rejected: true },
        status: 'completed',
        created_by: admin.id,
      })
      return json({ success: true, status: 'rejected' })
    }

    const responseText = String(final_response ?? '').trim()
    if (!responseText) return json({ error: 'BAD_REQUEST: no response text to post' }, 400)

    const { error: updateErr } = await serviceClient
      .from('reviews')
      .update({ response_text: responseText, responded_at: new Date().toISOString(), response_by: admin.id })
      .eq('id', review_id)
      .is('response_text', null) // idempotency guard against a race with another admin

    if (updateErr) return json({ error: 'Failed to post response', details: updateErr.message }, 500)

    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'reputation_management_approve',
      entity_type: 'review',
      entity_id: review_id,
      input: { decision: 'approve', final_response: responseText },
      output: { posted: true },
      status: 'completed',
      created_by: admin.id,
    })

    return json({ success: true, status: 'posted' })
  } catch (e) {
    return errorResponse(e)
  }
})

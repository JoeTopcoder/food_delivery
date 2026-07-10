import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { payout_request_id, admin_note } = await req.json()

    if (!payout_request_id) {
      return json({ error: 'BAD_REQUEST: payout_request_id required' }, 400)
    }
    if (!admin_note || admin_note.trim().length === 0) {
      return json({ error: 'BAD_REQUEST: admin_note is required when rejecting' }, 400)
    }

    const { data: pr } = await serviceClient
      .from('stripe_payout_requests')
      .select('*')
      .eq('id', payout_request_id)
      .single()

    if (!pr) return json({ error: 'Payout request not found' }, 404)
    if (!['requested', 'approved'].includes(pr.status)) {
      return json({ error: `Cannot reject payout in status: ${pr.status}` }, 400)
    }

    // Unlock ledger entries so earnings return to 'available'
    await serviceClient.rpc('unlock_ledger_entries_for_payout', {
      p_payout_request_id: payout_request_id,
    })

    // Mark as rejected
    await serviceClient
      .from('stripe_payout_requests')
      .update({
        status: 'rejected',
        admin_note: admin_note.trim(),
        approved_by: admin.id,
        updated_at: new Date().toISOString(),
      })
      .eq('id', payout_request_id)

    return json({ success: true })
  } catch (e) {
    return errorResponse(e)
  }
})

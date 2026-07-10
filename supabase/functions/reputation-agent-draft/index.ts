// reputation-agent-draft — Reputation Management Agent (7Dash AI Operations)
// Drafts a public response to a customer review. Scope: in-app reviews only
// (the `reviews` table) — external platforms (Google/App Store/Play Store)
// aren't wired up to any API yet, so this agent doesn't claim to monitor
// them. Never posts anything itself; that's reputation-agent-approve, after
// an admin reviews the draft.
// Deploy: supabase functions deploy reputation-agent-draft --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)
    const { review_id } = await req.json()
    if (!review_id) return json({ error: 'BAD_REQUEST: review_id required' }, 400)

    if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)

    const { data: agentRow } = await serviceClient
      .from('ai_agents')
      .select('status')
      .eq('slug', 'reputation_management')
      .maybeSingle()
    if (agentRow?.status === 'paused') return json({ error: 'Reputation Management Agent is paused.' }, 403)

    const { data: review, error: reviewErr } = await serviceClient
      .from('reviews')
      .select('id, rating, food_quality, delivery_speed, driver_behavior, review_text, would_recommend, restaurant_id, response_text')
      .eq('id', review_id)
      .single()
    if (reviewErr || !review) return json({ error: 'Review not found' }, 404)
    if (review.response_text) return json({ error: 'This review already has a response.' }, 400)

    const { data: restaurant } = await serviceClient.from('restaurants').select('name').eq('id', review.restaurant_id).maybeSingle()

    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          {
            role: 'system',
            content: `You are the 7Dash Reputation Management Agent, drafting a PUBLIC reply to a customer review that other customers will see. Rules:
- Never promise or imply a refund, credit, replacement, or any specific compensation — that must be handled privately through Support, not in a public reply.
- Never fabricate details about what happened; only reference what's in the review itself.
- Tone: warm and professional for positive reviews, genuinely apologetic and non-defensive for negative ones. 2-4 sentences.
- Also classify: sentiment ("positive"|"neutral"|"negative"), urgency ("low"|"medium"|"high" — high only for serious complaints like food safety, safety incidents, or repeated failures), and whether this needs escalation to a human before any reply is posted (needs_escalation: true/false).
Respond ONLY with JSON: { "draft_response": string, "sentiment": string, "urgency": string, "needs_escalation": boolean, "reasoning": string }`,
          },
          {
            role: 'user',
            content: `Restaurant: ${restaurant?.name ?? 'Unknown'}
Rating: ${review.rating}/5
Food quality: ${review.food_quality ?? 'N/A'}, Delivery speed: ${review.delivery_speed ?? 'N/A'}, Driver behavior: ${review.driver_behavior ?? 'N/A'}
Would recommend: ${review.would_recommend}
Review text: ${review.review_text ?? '(no written review)'}`,
          },
        ],
        response_format: { type: 'json_object' },
        temperature: 0.4,
      }),
    })

    if (!res.ok) {
      const errText = await res.text()
      return json({ error: 'AI drafting failed', details: errText }, 502)
    }

    const completion = await res.json()
    const parsed = JSON.parse(completion.choices?.[0]?.message?.content ?? '{}')
    const draftResponse = String(parsed.draft_response ?? '').slice(0, 1000)
    const sentiment = ['positive', 'neutral', 'negative'].includes(parsed.sentiment) ? parsed.sentiment : 'neutral'
    const urgency = ['low', 'medium', 'high'].includes(parsed.urgency) ? parsed.urgency : 'low'
    const needsEscalation = parsed.needs_escalation === true
    const reasoning = String(parsed.reasoning ?? '').slice(0, 1000)

    const { data: run, error: runErr } = await serviceClient
      .from('ai_agent_runs')
      .insert({
        agent_name: 'reputation_management',
        entity_type: 'review',
        entity_id: review_id,
        related_entities: [{ type: 'restaurant', id: review.restaurant_id }],
        input: { review, restaurant_name: restaurant?.name },
        output: { draft_response: draftResponse, sentiment, urgency, needs_escalation: needsEscalation, reasoning },
        model: 'gpt-4o-mini',
        status: 'completed',
        created_by: admin.id,
      })
      .select('id')
      .single()
    if (runErr) return json({ error: 'Failed to log agent run', details: runErr.message }, 500)

    return json({
      success: true,
      draft_response: draftResponse,
      sentiment,
      urgency,
      needs_escalation: needsEscalation,
      reasoning,
      run_id: run.id,
    })
  } catch (e) {
    return errorResponse(e)
  }
})

// ai-banner-designer — an AI "staff" member that designs promo banners.
// You describe what you want ("a banner for KFC, 25% off delivery"); it matches
// the real restaurant, writes the copy, and creates a DRAFT banner (is_active=
// false) for the admin to preview and publish. It never invents a restaurant or
// a live discount — it only drafts; the admin publishes.
//
// Auth: admin JWT or service role. Deploy: supabase functions deploy ai-banner-designer --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
const RUNNER_SECRET = Deno.env.get('AUTOMATION_RUNNER_SECRET') ?? ''

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '')
    let tokenRole = ''
    try { tokenRole = String(JSON.parse(atob((token.split('.')[1] ?? '').replace(/-/g, '+').replace(/_/g, '/'))).role ?? '') } catch { /* */ }
    const isService = tokenRole === 'service_role'
      || (SERVICE_ROLE_KEY && token === SERVICE_ROLE_KEY)
      || (RUNNER_SECRET && token === RUNNER_SECRET)
    let adminId: string | null = null
    if (!isService) {
      try { adminId = (await requireAdmin(req)).id } catch { return json({ error: 'FORBIDDEN' }, 403) }
    }
    if (!OPENAI_API_KEY) return json({ error: 'AI not configured (OPENAI_API_KEY missing)' }, 500)

    const body = await req.json().catch(() => ({}))
    const prompt = String(body.prompt ?? '').trim()
    const publish = body.publish === true
    if (!prompt) return json({ error: 'Describe the banner you want (e.g. "a banner for KFC, 25% off delivery").' }, 400)

    // Real, verified restaurants for the model to match against — no invented ones.
    const { data: rests } = await serviceClient
      .from('restaurants').select('id, name, cuisine_type, image_url')
      .eq('is_verified', true).limit(200)
    const restaurants = (rests ?? []) as Array<Record<string, unknown>>
    if (restaurants.length === 0) return json({ error: 'No verified restaurants to design for.' }, 400)

    const sys = `You design a short promotional banner for the HotBite food-delivery app home carousel.
From the user's request and the RESTAURANT LIST, choose the single best-matching restaurant and write punchy copy.
RULES:
- "restaurant_id" MUST be one of the ids in the provided list. Never invent one.
- "title": the headline/offer, <= 22 chars (e.g. "25% Off", "Free Delivery", "Flat $200 Off").
- "subtitle": <= 34 chars supporting line (e.g. "On delivery today", "On your first order").
- Only include a discount if the request implies one: "discount_type" is "percentage" or "fixed"; "discount_value" a number; else null.
- "promo_code": UPPERCASE short code ONLY if the request asks for one, else null. Do not fabricate a working code.
Respond ONLY with JSON: { "restaurant_id": string, "title": string, "subtitle": string, "discount_type": string|null, "discount_value": number|null, "promo_code": string|null }`

    const res = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: sys },
          { role: 'user', content: JSON.stringify({ request: prompt, restaurants: restaurants.map((r) => ({ id: r.id, name: r.name, cuisine: r.cuisine_type })) }) },
        ],
        response_format: { type: 'json_object' }, temperature: 0.5,
      }),
    })
    if (!res.ok) return json({ error: 'AI design failed', details: (await res.text()).slice(0, 300) }, 502)
    const d = JSON.parse((await res.json()).choices?.[0]?.message?.content ?? '{}')

    // Validate the chosen restaurant against the real list.
    const chosen = restaurants.find((r) => r.id === d.restaurant_id)
    if (!chosen) return json({ error: `Couldn't match a restaurant for "${prompt}". Try naming it exactly.` }, 400)

    const dt = ['percentage', 'fixed'].includes(String(d.discount_type)) ? String(d.discount_type) : null
    const banner = {
      title: String(d.title ?? 'Special Offer').slice(0, 40),
      subtitle: String(d.subtitle ?? '').slice(0, 80),
      image_url: (chosen.image_url as string) ?? null,
      restaurant_id: chosen.id,
      section: 'food',
      discount_type: dt,
      discount_value: dt && d.discount_value != null ? Number(d.discount_value) : null,
      promo_code: d.promo_code ? String(d.promo_code).toUpperCase().slice(0, 24) : null,
      is_active: publish === true,            // default: DRAFT until the admin publishes
      sort_order: 0,
    }

    const { data: inserted, error: insErr } = await serviceClient
      .from('banners').insert(banner).select().single()
    if (insErr) return json({ error: 'Could not save banner', details: insErr.message }, 500)

    return json({ success: true, banner: inserted, restaurant: { id: chosen.id, name: chosen.name }, published: banner.is_active })
  } catch (e) {
    return json({ error: 'ai-banner-designer failed', details: String((e as Error).message ?? e) }, 500)
  }
})

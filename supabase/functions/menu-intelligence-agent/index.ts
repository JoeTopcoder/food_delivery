// menu-intelligence-agent — Menu Intelligence Agent (7Dash AI Operations)
// Read-only. Scans real menu items (table is confusingly named `menus`) for
// concrete, objective quality issues — missing images, missing descriptions,
// unavailable items, invalid prices, exact-name duplicates within a
// restaurant. All detection is deterministic; the model only narrates which
// restaurants most need attention. No AI modifies any menu item.
// Deploy: supabase functions deploy menu-intelligence-agent --no-verify-jwt

import { serviceClient } from '../stripe-shared/supabase.ts'
import { requireAdmin } from '../stripe-shared/auth.ts'
import { json, errorResponse, handleOptions } from '../stripe-shared/errors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

interface MenuItemRow {
  id: string
  restaurant_id: string
  name: string
  description: string | null
  price: number
  image_url: string | null
  is_available: boolean | null
}

interface RestaurantMenuSummary {
  restaurant_id: string
  restaurant_name: string
  item_count: number
  missing_image: number
  missing_description: number
  unavailable: number
  invalid_price: number
  duplicate_names: string[]
  issue_score: number
}

async function computeMenuIssues(): Promise<RestaurantMenuSummary[]> {
  const [{ data: items }, { data: restaurants }] = await Promise.all([
    serviceClient
      .from('menus')
      .select('id, restaurant_id, name, description, price, image_url, is_available')
      .or('is_mock_data.is.null,is_mock_data.eq.false'),
    serviceClient.from('restaurants').select('id, name').eq('status', 'approved'),
  ])

  const itemRows = (items ?? []) as MenuItemRow[]
  const restaurantNames = new Map((restaurants ?? []).map((r) => [r.id, r.name]))

  const byRestaurant = new Map<string, MenuItemRow[]>()
  for (const item of itemRows) {
    if (!restaurantNames.has(item.restaurant_id)) continue // skip items for non-approved/removed restaurants
    const list = byRestaurant.get(item.restaurant_id) ?? []
    list.push(item)
    byRestaurant.set(item.restaurant_id, list)
  }

  const summaries: RestaurantMenuSummary[] = []
  for (const [restaurantId, restaurantItems] of byRestaurant) {
    const missingImage = restaurantItems.filter((i) => !i.image_url).length
    const missingDescription = restaurantItems.filter((i) => !i.description || i.description.trim().length === 0).length
    const unavailable = restaurantItems.filter((i) => i.is_available === false).length
    const invalidPrice = restaurantItems.filter((i) => Number(i.price) <= 0).length

    const nameCounts = new Map<string, number>()
    for (const i of restaurantItems) {
      const key = i.name.trim().toLowerCase()
      nameCounts.set(key, (nameCounts.get(key) ?? 0) + 1)
    }
    const duplicateNames = Array.from(nameCounts.entries()).filter(([, c]) => c > 1).map(([n]) => n)

    const issueScore = missingImage * 2 + missingDescription * 2 + invalidPrice * 3 + duplicateNames.length * 4

    summaries.push({
      restaurant_id: restaurantId,
      restaurant_name: restaurantNames.get(restaurantId) ?? 'Unknown',
      item_count: restaurantItems.length,
      missing_image: missingImage,
      missing_description: missingDescription,
      unavailable,
      invalid_price: invalidPrice,
      duplicate_names: duplicateNames,
      issue_score: issueScore,
    })
  }

  return summaries.sort((a, b) => b.issue_score - a.issue_score)
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return handleOptions()
  try {
    const admin = await requireAdmin(req)

    const { data: agentRow } = await serviceClient
      .from('ai_agents')
      .select('status')
      .eq('slug', 'menu_intelligence')
      .maybeSingle()
    if (agentRow?.status === 'paused') return json({ error: 'Menu Intelligence Agent is paused.' }, 403)

    const summaries = await computeMenuIssues()

    let narrative = ''
    if (OPENAI_API_KEY && summaries.length > 0) {
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: { Authorization: `Bearer ${OPENAI_API_KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          messages: [
            {
              role: 'system',
              content: `You are the 7Dash Menu Intelligence Agent. You're given menu quality data per restaurant, ranked by issue_score (higher = more issues). Write a short briefing (100-150 words) naming the 1-3 restaurants with the most menu quality issues and what specifically is wrong (missing images, missing descriptions, invalid prices, or duplicate item names — cite the actual counts). Restaurants with 0 issues don't need mentioning. All fixes require the restaurant or an admin to actually edit the menu — you are reporting only, never invent an issue not in the data. Plain text, no markdown.`,
            },
            { role: 'user', content: JSON.stringify(summaries) },
          ],
          temperature: 0.3,
        }),
      })
      if (res.ok) {
        const completion = await res.json()
        narrative = completion.choices?.[0]?.message?.content ?? ''
      }
    }

    await serviceClient.from('ai_agent_runs').insert({
      agent_name: 'menu_intelligence',
      entity_type: 'menu_report',
      entity_id: crypto.randomUUID(),
      related_entities: summaries.map((s) => ({ type: 'restaurant', id: s.restaurant_id })),
      input: {},
      output: { summaries, narrative },
      model: 'gpt-4o-mini',
      status: 'completed',
      created_by: admin.id,
    })

    return json({ success: true, summaries, narrative })
  } catch (e) {
    return errorResponse(e)
  }
})

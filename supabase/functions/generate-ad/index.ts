// generate-ad — AI-powered promotional popup generator
// Accepts: { restaurant_name, brief }
// Returns: { title, description, cta_text }

import { corsHeaders } from '../_shared/cors.ts'

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY') ?? ''

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const body = await req.json()
    const restaurantName: string = String(body.restaurant_name ?? '').trim()
    const brief: string = String(body.brief ?? '').trim()

    if (!restaurantName || !brief) {
      return new Response(
        JSON.stringify({ error: 'restaurant_name and brief are required' }),
        { status: 400, headers: corsHeaders },
      )
    }

    const systemPrompt = `You are an expert food delivery app copywriter for 7DASH, a food delivery platform.
You write short, punchy, emoji-rich promotional popups that appear to customers on the home screen.
Popups must be exciting, clear, and action-oriented. Always respond with valid JSON only — no markdown.`

    const userPrompt = `Create a promotional popup ad based on the following:

Restaurant: ${restaurantName}
Brief: ${brief}

Return JSON with exactly these three keys:
{
  "title": "Punchy headline with 1-2 relevant emojis (max 60 chars total)",
  "description": "2-3 sentences of compelling copy. Include key offer details like prices, promo codes, or deadlines.",
  "cta_text": "Short action button label (e.g. Order Now, Claim Offer, Get It Now)"
}`

    const openaiRes = await fetch('https://api.openai.com/v1/chat/completions', {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${OPENAI_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'gpt-4o-mini',
        messages: [
          { role: 'system', content: systemPrompt },
          { role: 'user', content: userPrompt },
        ],
        temperature: 0.85,
        response_format: { type: 'json_object' },
        max_tokens: 300,
      }),
    })

    if (!openaiRes.ok) {
      const err = await openaiRes.text()
      return new Response(
        JSON.stringify({ error: `OpenAI error: ${err}` }),
        { status: 500, headers: corsHeaders },
      )
    }

    const openaiData = await openaiRes.json()
    const content = openaiData.choices?.[0]?.message?.content ?? '{}'
    const generated = JSON.parse(content) as Record<string, string>

    return new Response(
      JSON.stringify({
        title: generated.title ?? '',
        description: generated.description ?? '',
        cta_text: generated.cta_text ?? 'Order Now',
      }),
      { headers: corsHeaders },
    )
  } catch (e) {
    return new Response(
      JSON.stringify({ error: String(e) }),
      { status: 500, headers: corsHeaders },
    )
  }
})

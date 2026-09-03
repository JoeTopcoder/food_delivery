// concierge-classify-menu
//
// One-time (and re-runnable) backfill that gives every menu item the structured
// dietary/flavour attributes the AI Food Concierge filters on.
//
// Why this exists: spice_level was populated on 0 of 211 items and there was no
// pork column at all, so "spicy, no pork" could only ever be answered by
// keyword-guessing a description. Guessing is acceptable for "spicy" and not
// acceptable for "no pork", which is usually a religious or medical constraint.
// Classifying once into real columns makes every later query a fast indexed SQL
// filter, keeps the answer stable between runs, and leaves an auditable
// provenance trail (dietary_source = 'ai') that a restaurant can override.
//
// Admin-only. Idempotent: by default it only touches rows nobody has classified
// yet, and it never overwrites a 'restaurant' or 'admin' assertion.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

// Small batches keep each completion well inside the model's reliable range and
// mean a single bad batch costs little to retry.
const BATCH_SIZE = 20;

const SYSTEM_PROMPT = `You classify restaurant menu items for a food delivery app's dietary filter.

For each item you receive (id, name, description) return structured attributes.

RULES:
- Judge ONLY from the name and description. Never invent ingredients.
- COMMIT TO false WHEN THE DISH IS IDENTIFIABLE. "Grilled Salmon with rice" is
  contains_pork:false — salmon and rice are not pork. "Beef Burger" is
  contains_pork:false. Do not return null merely because the text does not say
  the words "no pork". Most dishes have a knowable answer and returning null for
  all of them makes the customer's dietary filter useless.
- Reserve null for genuinely opaque items ONLY: unspecified assortments and
  chef's choice ("Mixed Platter", "Chef's Special", "Combo #3"), or a dish whose
  named components could routinely go either way (a "Full Breakfast" or a
  "Supreme Pizza" may or may not include bacon/ham).
- contains_pork covers pork, bacon, ham, prosciutto, pancetta, chorizo, lard and
  pork sausage. A dish that is plainly beef, chicken, fish or vegetarian is
  false, not null.
- contains_shellfish covers shrimp, prawn, crab, lobster, clam, mussel, oyster,
  scallop, squid, calamari, octopus.
- is_halal / is_kosher: only true when the text explicitly says so. Otherwise
  null. Never infer these from the absence of pork — certification is a claim
  only the restaurant can make.
- spice_rating: 0 not spicy, 1 mild, 2 medium, 3 hot, 4 very hot. Jerk, curry,
  scotch bonnet, chilli, buffalo, arrabbiata and similar imply 2+. Give a plainly
  non-spicy dish (pancakes, salad, cheesecake, plain grilled fish) 0 rather than
  null — "not spicy" is a real, useful answer. Use null only when the dish could
  reasonably arrive at any heat level and the text gives no clue at all.
- flavor_tags: 0-4 from exactly this set: spicy, mild, savoury, sweet, fresh,
  rich, comfort, light, smoky, tangy.

WORKED EXAMPLES — match this level of confidence:

"Iced Latte — double-shot espresso over ice with milk"
  -> contains_pork:false, contains_dairy:true, spice_rating:0, is_vegetarian:true
"Key Lime Pie — classic Key lime pie with whipped cream"
  -> contains_pork:false, contains_dairy:true, spice_rating:0, is_vegetarian:true
"Butter Chicken — slow-cooked chicken in a velvety tomato sauce"
  -> contains_pork:false, contains_dairy:true, spice_rating:2, is_vegetarian:false
"Coconut Shrimp Plate — coconut-crusted shrimp with fries and slaw"
  -> contains_pork:false, contains_shellfish:true, spice_rating:0
"Beef Tacos — seasoned ground beef, lettuce, pico de gallo, cheddar"
  -> contains_pork:false, contains_beef:true, spice_rating:1
"Caprese Salad — buffalo mozzarella, tomato, basil, balsamic"
  -> contains_pork:false, contains_dairy:true, spice_rating:0, is_vegetarian:true
"Jerk Pork Belly — scotch bonnet glazed pork belly"
  -> contains_pork:true, spice_rating:3
"Pizza box — love pizza"
  -> contains_pork:null  (no toppings stated; genuinely unknowable)
"Chef's Mixed Platter — selection of the chef's favourites"
  -> contains_pork:null  (unspecified assortment)

Note how only the last two are null. Everything else commits.

Return JSON: {"items":[{"id":"...","contains_pork":bool|null,"contains_shellfish":bool|null,"contains_beef":bool|null,"contains_dairy":bool|null,"contains_egg":bool|null,"contains_alcohol":bool|null,"is_vegetarian":bool|null,"is_vegan":bool|null,"is_halal":bool|null,"is_kosher":bool|null,"spice_rating":0-4|null,"flavor_tags":["..."]}]}

Return every id you were given, exactly once.`;

interface MenuRow {
  id: string;
  name: string;
  description: string | null;
}

async function classifyBatch(rows: MenuRow[]): Promise<Record<string, unknown>[]> {
  const res = await fetch('https://api.openai.com/v1/chat/completions', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${OPENAI_API_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'gpt-4o-mini',
      temperature: 0, // deterministic: the same menu must classify the same way
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        {
          role: 'user',
          content: JSON.stringify(
            rows.map((r) => ({
              id: r.id,
              name: r.name,
              description: r.description ?? '',
            })),
          ),
        },
      ],
    }),
  });

  if (!res.ok) {
    throw new Error(`OpenAI ${res.status}: ${await res.text()}`);
  }

  const json = await res.json();
  const parsed = JSON.parse(json.choices[0].message.content);
  return Array.isArray(parsed.items) ? parsed.items : [];
}

/** Only ever accept the shapes the columns allow; anything else becomes null. */
function bool(v: unknown): boolean | null {
  return typeof v === 'boolean' ? v : null;
}

function spice(v: unknown): number | null {
  return typeof v === 'number' && Number.isInteger(v) && v >= 0 && v <= 4
    ? v
    : null;
}

const ALLOWED_TAGS = new Set([
  'spicy', 'mild', 'savoury', 'sweet', 'fresh',
  'rich', 'comfort', 'light', 'smoky', 'tangy',
]);

function tags(v: unknown): string[] {
  if (!Array.isArray(v)) return [];
  return v
    .filter((t): t is string => typeof t === 'string')
    .map((t) => t.toLowerCase().trim())
    .filter((t) => ALLOWED_TAGS.has(t))
    .slice(0, 4);
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

    // Admin gate. Decode the caller's JWT the same way the other functions in
    // this project do, then confirm the role in the database rather than
    // trusting any claim in the token itself.
    const authHeader = req.headers.get('Authorization') ?? '';
    const token = authHeader.replace('Bearer ', '');
    if (!token) {
      return new Response(JSON.stringify({ error: 'Not authenticated' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }
    let claims: { sub?: string; role?: string };
    try {
      claims = JSON.parse(atob(token.split('.')[1]));
    } catch {
      return new Response(JSON.stringify({ error: 'Malformed token' }), {
        status: 401,
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      });
    }

    // Two legitimate callers: the service role (backend/ops tooling running the
    // backfill, which already holds full database rights so there is nothing to
    // escalate) or a signed-in user whose role is admin IN THE DATABASE — the
    // token's own claims are never taken as proof of that.
    const isServiceRole = claims.role === 'service_role';
    if (!isServiceRole) {
      if (!claims.sub) {
        return new Response(JSON.stringify({ error: 'Not authenticated' }), {
          status: 401,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
      const { data: caller } = await admin
        .from('users')
        .select('role')
        .eq('id', claims.sub)
        .single();
      if (caller?.role !== 'admin') {
        return new Response(JSON.stringify({ error: 'Admin only' }), {
          status: 403,
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        });
      }
    }

    const body = await req.json().catch(() => ({}));
    // reclassify:true re-runs items previously done by the AI. It still never
    // touches rows a restaurant or admin has asserted.
    const reclassify = body.reclassify === true;
    const limit = Math.min(Number(body.limit) || 250, 500);

    let query = admin
      .from('menus')
      .select('id, name, description')
      .eq('is_available', true)
      // Least-recently-classified first, so repeated calls march through the
      // whole menu instead of re-selecting the same arbitrary page. Without the
      // ordering an unordered LIMIT kept handing back the same 40 rows and a
      // six-call reclassify loop only ever touched 47 of 211 items.
      .order('dietary_classified_at', { ascending: true, nullsFirst: true })
      .limit(limit);

    query = reclassify
      ? query.or('dietary_source.is.null,dietary_source.eq.ai')
      : query.is('dietary_source', null);

    const { data: rows, error } = await query;
    if (error) throw error;

    const items = (rows ?? []) as MenuRow[];
    if (items.length === 0) {
      return new Response(
        JSON.stringify({ classified: 0, message: 'Nothing left to classify' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
      );
    }

    let classified = 0;
    const failures: string[] = [];

    for (let i = 0; i < items.length; i += BATCH_SIZE) {
      const batch = items.slice(i, i + BATCH_SIZE);
      let results: Record<string, unknown>[];
      try {
        results = await classifyBatch(batch);
      } catch (e) {
        // One bad batch must not abandon the rest of the menu.
        failures.push(`batch ${i / BATCH_SIZE}: ${(e as Error).message}`);
        continue;
      }

      const byId = new Map(batch.map((b) => [b.id, b]));
      for (const r of results) {
        const id = typeof r.id === 'string' ? r.id : null;
        if (!id || !byId.has(id)) continue; // never write an id we didn't send

        const { error: upErr } = await admin
          .from('menus')
          .update({
            contains_pork: bool(r.contains_pork),
            contains_shellfish: bool(r.contains_shellfish),
            contains_beef: bool(r.contains_beef),
            contains_dairy: bool(r.contains_dairy),
            contains_egg: bool(r.contains_egg),
            contains_alcohol: bool(r.contains_alcohol),
            is_vegetarian: bool(r.is_vegetarian),
            is_vegan: bool(r.is_vegan),
            is_halal: bool(r.is_halal),
            is_kosher: bool(r.is_kosher),
            spice_rating: spice(r.spice_rating),
            flavor_tags: tags(r.flavor_tags),
            dietary_source: 'ai',
            dietary_classified_at: new Date().toISOString(),
          })
          .eq('id', id)
          // Belt and braces: never clobber a human assertion, even if the
          // selection above somehow returned one.
          .or('dietary_source.is.null,dietary_source.eq.ai');

        if (upErr) failures.push(`${id}: ${upErr.message}`);
        else classified++;
      }
    }

    return new Response(
      JSON.stringify({
        classified,
        considered: items.length,
        failures: failures.slice(0, 10),
        failure_count: failures.length,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: (e as Error).message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

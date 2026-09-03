// ai-concierge — the AI Food Concierge
//
// "I have $30 and I need dinner for two. Something spicy, no pork, and I want
// it here before 7."
//
// Understand -> search -> compare -> check availability -> recommend ->
// build cart -> apply promotion -> hand off to the existing checkout.
//
// DESIGN RULES (these are load-bearing, not style):
//
// 1. THE MODEL NEVER FILTERS. It says what the customer wants; the SERVER
//    re-applies every dietary/price/time constraint in SQL. A model that
//    "remembers" to exclude pork is not a dietary filter, it is a hazard.
// 2. THE MODEL NEVER SEES OR SETS PRICES. Every figure returned to the client
//    is read from the database and computed here, in integer cents.
// 3. THE MODEL NEVER PLACES AN ORDER. The furthest it can go is a finalized
//    cart plus a handoff to the checkout screen the customer already knows.
// 4. UNKNOWN IS NOT SAFE. An exclusion filter rejects NULL as well as TRUE:
//    "we haven't classified this" can never satisfy "no pork".
// 5. Location is server-injected from the customer's profile. The model cannot
//    supply lat/lng, so it cannot make the app query somewhere else.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
};

const OPENAI_API_KEY = Deno.env.get('OPENAI_API_KEY')!;
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!;
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;

const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

// ── money ───────────────────────────────────────────────────────────────────
// The menus table stores price as double precision. Everything past this
// boundary is integer cents, per the contract, so no float ever reaches an
// arithmetic path that a customer will be charged from.
const toCents = (n: number | null | undefined) => Math.round((n ?? 0) * 100);

// ── dietary mapping ─────────────────────────────────────────────────────────
// Maps a contract exclusion onto the column that answers it. Anything not in
// this map is not a filter we can honour, and is reported as unsupported rather
// than silently ignored — silently ignoring "no shellfish" is how people get
// hurt.
const EXCLUSION_COLUMN: Record<string, string> = {
  pork: 'contains_pork',
  shellfish: 'contains_shellfish',
  beef: 'contains_beef',
  dairy: 'contains_dairy',
  egg: 'contains_egg',
  alcohol: 'contains_alcohol',
  nuts: 'contains_nuts',
  gluten: 'contains_gluten',
};

const REQUIREMENT_COLUMN: Record<string, string> = {
  vegetarian: 'is_vegetarian',
  vegan: 'is_vegan',
  halal: 'is_halal',
  kosher: 'is_kosher',
};

interface Ctx {
  userId: string;
  lat: number | null;
  lng: number | null;
}

// Every query that can return a dish routes through these two helpers, so
// "no pork" is implemented exactly once. Adding a new search path without them
// would be the way a dietary constraint quietly stops being enforced.

/** Applies exclusions/requirements to any menus query. */
// deno-lint-ignore no-explicit-any
function applyDietary(q: any, a: Record<string, unknown>) {
  for (const ex of (a.dietary_exclusions as string[]) ?? []) {
    const col = EXCLUSION_COLUMN[ex?.toLowerCase?.()];
    // Explicitly FALSE only: NULL means "unclassified", and unknown can never
    // satisfy an exclusion.
    if (col) q = q.eq(col, false);
  }
  for (const req of (a.dietary_requirements as string[]) ?? []) {
    const col = REQUIREMENT_COLUMN[req?.toLowerCase?.()];
    if (col) q = q.eq(col, true);
  }
  return q;
}

/** Spice is the one flavour customers mean literally, so it gates rather than ranks. */
function applyFlavorGate(
  rows: Record<string, unknown>[],
  a: Record<string, unknown>,
) {
  const flavors = ((a.flavor_tags as string[]) ?? []).map((f) =>
    String(f).toLowerCase(),
  );
  let out = rows;
  if (flavors.includes('spicy')) {
    out = out.filter((i) => ((i.spice_rating as number) ?? -1) >= 2);
  }
  if (flavors.includes('mild')) {
    out = out.filter((i) => ((i.spice_rating as number) ?? 99) <= 1);
  }
  return out;
}

// ════════════════════════════════════════════════════════════════════════════
// TOOLS
// ════════════════════════════════════════════════════════════════════════════

/**
 * Find dishes BY NAME across every restaurant.
 *
 * This is the tool a request like "jerk chicken and rice and peas" or "soup"
 * actually needs, and its absence was the concierge's biggest accuracy bug: with
 * only cuisine-based restaurant search available, the model guessed at cuisine
 * labels, matched nothing, and told customers that dishes plainly present in the
 * database did not exist (9 jerk dishes and 2 soups were all reported missing).
 *
 * Dietary filtering is applied here exactly as everywhere else — searching by
 * name never becomes a way around an exclusion.
 */
async function searchDishes(ctx: Ctx, a: Record<string, unknown>) {
  const raw = String(a.query ?? '').trim();
  if (!raw) return { dishes: [] };
  // Smaller default than the caller might ask for: every returned dish is
  // tokens the model must read before it can answer, and latency the customer
  // feels. Eight strong matches is plenty to choose one from.
  const limit = Math.min(Number(a.limit) || 8, 15);

  // Match on any significant word rather than the whole phrase: a customer
  // asking for "jerk chicken and rice and peas" is describing a meal, not a
  // single row, and an exact-phrase match finds nothing.
  const stop = new Set([
    'and', 'the', 'with', 'for', 'some', 'any', 'need', 'want', 'a', 'an',
    'me', 'my', 'i', 'of', 'please', 'get', 'order', 'have',
  ]);
  const words = raw
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .filter((w) => w.length >= 3 && !stop.has(w))
    .slice(0, 6);
  if (!words.length) return { dishes: [] };

  const ors = words
    .flatMap((w) => [`name.ilike.%${w}%`, `description.ilike.%${w}%`])
    .join(',');

  let q = admin
    .from('menus')
    .select(
      'id, name, description, price, restaurant_id, spice_rating, flavor_tags, dietary_source, preparation_time, is_available, contains_pork, contains_shellfish, contains_beef, contains_dairy, contains_egg, contains_alcohol, contains_nuts, contains_gluten, is_vegetarian, is_vegan, is_halal, is_kosher, restaurants!inner(id, name, is_open, rating, estimated_delivery_time, delivery_fee, price_tier, is_verified)',
    )
    .eq('is_available', true)
    .eq('restaurants.is_verified', true)
    .or(ors)
    .limit(80);

  q = applyDietary(q, a);
  if (typeof a.max_item_price_cents === 'number') {
    q = q.lte('price', (a.max_item_price_cents as number) / 100);
  }

  const { data, error } = await q;
  if (error) throw error;

  let items = applyFlavorGate(data ?? [], a);

  // Rank by how many of the customer's words the dish actually matches, so
  // "jerk chicken" puts Jerk Chicken above Jerk Fish.
  const scored = items.map((i) => {
    const hay = `${i.name} ${i.description ?? ''}`.toLowerCase();
    const hits = words.filter((w) => hay.includes(w)).length;
    const nameHits = words.filter((w) =>
      String(i.name).toLowerCase().includes(w),
    ).length;
    return { i, score: hits + nameHits * 2 };
  });
  scored.sort((x, y) => y.score - x.score);

  return {
    dishes: scored.slice(0, limit).map(({ i }) => {
      const r = i.restaurants as Record<string, unknown>;
      return {
        ...shapeItem(i),
        restaurant_id: r?.id,
        restaurant_name: r?.name,
        restaurant_is_open: r?.is_open === true,
        eta_minutes: r?.estimated_delivery_time ?? 40,
      };
    }),
  };
}

async function searchRestaurants(ctx: Ctx, a: Record<string, unknown>) {
  const limit = Math.min(Number(a.limit) || 10, 20);

  // Single grouped query rather than a per-restaurant probe. The previous
  // version fetched every approved restaurant then ran one filtered menu query
  // EACH — 38 sequential round trips per search, which was the bulk of the
  // latency customers were feeling.
  let q = admin
    .from('menus')
    .select(
      'id, price, spice_rating, contains_pork, contains_shellfish, contains_beef, contains_dairy, contains_egg, contains_alcohol, contains_nuts, contains_gluten, is_vegetarian, is_vegan, is_halal, is_kosher, restaurants!inner(id, name, rating, price_tier, cuisine_type, is_open, latitude, longitude, estimated_delivery_time, is_verified)',
    )
    .eq('is_available', true)
    .eq('restaurants.is_verified', true)
    .limit(1200);

  q = applyDietary(q, a);
  if (typeof a.max_price_tier === 'number') {
    q = q.lte('restaurants.price_tier', a.max_price_tier);
  }
  if (Array.isArray(a.cuisines) && a.cuisines.length) {
    q = q.in('restaurants.cuisine_type', a.cuisines as string[]);
  }

  const { data, error } = await q;
  if (error) throw error;

  const rows = applyFlavorGate(data ?? [], a);

  // A restaurant only qualifies if it still has a matching available item, so
  // we never recommend somewhere whose only spicy dish contains pork.
  const byRestaurant = new Map<string, Record<string, unknown>>();
  for (const row of rows) {
    const r = row.restaurants as Record<string, unknown>;
    if (!r?.id) continue;
    const id = r.id as string;
    const existing = byRestaurant.get(id);
    if (existing) {
      existing.matching_item_count = (existing.matching_item_count as number) + 1;
      continue;
    }
    byRestaurant.set(id, {
      id,
      name: r.name,
      rating: r.rating,
      price_tier: r.price_tier,
      cuisines: r.cuisine_type ? [r.cuisine_type] : [],
      badges: [] as string[],
      is_open: r.is_open === true,
      eta_minutes: r.estimated_delivery_time ?? 40,
      distance_km:
        ctx.lat != null && ctx.lng != null && r.latitude && r.longitude
          ? haversineKm(ctx.lat, ctx.lng, r.latitude as number, r.longitude as number)
          : null,
      matching_item_count: 1,
    });
  }

  const results = [...byRestaurant.values()];
  // Open first, then closest, then best rated.
  results.sort((x, y) => {
    if (x.is_open !== y.is_open) return x.is_open ? -1 : 1;
    const dx = x.distance_km as number | null;
    const dy = y.distance_km as number | null;
    if (dx != null && dy != null) return dx - dy;
    return ((y.rating as number) ?? 0) - ((x.rating as number) ?? 0);
  });

  return { restaurants: results.slice(0, limit) };
}

function haversineKm(a: number, b: number, c: number, d: number) {
  const R = 6371;
  const dLat = ((c - a) * Math.PI) / 180;
  const dLon = ((d - b) * Math.PI) / 180;
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos((a * Math.PI) / 180) *
      Math.cos((c * Math.PI) / 180) *
      Math.sin(dLon / 2) ** 2;
  return Math.round(2 * R * Math.asin(Math.sqrt(s)) * 10) / 10;
}

async function checkDeliveryEta(ctx: Ctx, a: Record<string, unknown>) {
  const { data: r, error } = await admin
    .from('restaurants')
    .select('id, name, is_open, estimated_delivery_time, latitude, longitude')
    .eq('id', a.restaurant_id as string)
    .single();
  if (error || !r) {
    return { delivery_available: false, reason: 'Restaurant not found' };
  }
  if (!r.is_open) {
    return {
      eta_minutes: null,
      arrives_by_local: null,
      delivery_available: false,
      reason: `${r.name} is currently closed`,
    };
  }

  // Prep time is per-item; the restaurant's own estimate already folds in
  // travel, so this is a floor rather than a promise.
  const eta = r.estimated_delivery_time ?? 40;
  const arrives = new Date(Date.now() + eta * 60_000);

  return {
    eta_minutes: eta,
    arrives_by_local: arrives.toISOString(),
    delivery_available: true,
  };
}

/**
 * The single place dietary/flavour filtering happens. Every tool that returns
 * items routes through here, so there is exactly one implementation of "no
 * pork" to get right — and the model can never bypass it.
 */
async function filterMenuItemsRaw(
  restaurantId: string,
  a: Record<string, unknown>,
) {
  let q = admin
    .from('menus')
    .select(
      'id, name, description, price, tags, spice_rating, flavor_tags, contains_pork, contains_shellfish, contains_beef, contains_dairy, contains_egg, contains_alcohol, contains_nuts, contains_gluten, is_vegetarian, is_vegan, is_halal, is_kosher, dietary_source, is_available, preparation_time',
    )
    .eq('restaurant_id', restaurantId)
    .eq('is_available', true);

  q = applyDietary(q, a);

  if (typeof a.max_item_price_cents === 'number') {
    q = q.lte('price', (a.max_item_price_cents as number) / 100);
  }

  const { data, error } = await q.limit(120);
  if (error) throw error;

  return applyFlavorGate(data ?? [], a);
}

async function getMenu(_ctx: Ctx, a: Record<string, unknown>) {
  const items = await filterMenuItemsRaw(a.restaurant_id as string, {});
  return { items: items.map(shapeItem) };
}

async function filterMenuItems(_ctx: Ctx, a: Record<string, unknown>) {
  const items = await filterMenuItemsRaw(a.restaurant_id as string, a);
  const unsupported = ((a.dietary_exclusions as string[]) ?? []).filter(
    (e) => !EXCLUSION_COLUMN[e?.toLowerCase?.()],
  );
  return {
    items: items.map(shapeItem),
    // Never let an unhonoured constraint pass silently.
    unsupported_exclusions: unsupported,
  };
}

function shapeItem(i: Record<string, unknown>) {
  const allergens: string[] = [];
  for (const [key, col] of Object.entries(EXCLUSION_COLUMN)) {
    if (i[col] === true) allergens.push(key);
  }
  return {
    id: i.id,
    name: i.name,
    description: i.description,
    price_cents: toCents(i.price as number),
    currency: 'USD',
    tags: i.flavor_tags ?? [],
    allergens,
    spice_rating: i.spice_rating,
    // Provenance travels with the item so the UI can caveat an AI-inferred
    // dietary claim rather than presenting it as the restaurant's word.
    dietary_source: i.dietary_source,
    in_stock: i.is_available === true,
    prep_minutes: i.preparation_time,
  };
}

async function buildCartDraft(ctx: Ctx, a: Record<string, unknown>) {
  const restaurantId = a.restaurant_id as string;
  const requested = (a.items as Array<Record<string, unknown>>) ?? [];
  if (!requested.length) throw new Error('No items supplied');

  // Re-read every item from the database. The model supplies ids and
  // quantities only; names and prices come from the menu, never from the model.
  const ids = requested.map((r) => r.item_id as string);
  const { data: rows, error } = await admin
    .from('menus')
    .select('id, name, price, is_available, restaurant_id')
    .in('id', ids);
  if (error) throw error;

  const byId = new Map((rows ?? []).map((r) => [r.id, r]));
  const lineItems: Record<string, unknown>[] = [];
  const validationErrors: string[] = [];

  for (const r of requested) {
    const row = byId.get(r.item_id as string);
    const qty = Math.max(1, Math.min(Number(r.qty) || 1, 20));
    if (!row) {
      validationErrors.push(`Item ${r.item_id} not found`);
      continue;
    }
    if (row.restaurant_id !== restaurantId) {
      validationErrors.push(`${row.name} belongs to a different restaurant`);
      continue;
    }
    if (!row.is_available) {
      validationErrors.push(`${row.name} is unavailable`);
      continue;
    }
    lineItems.push({
      item_id: row.id,
      name: row.name,
      qty,
      unit_price_cents: toCents(row.price),
      modifiers: Array.isArray(r.modifiers) ? r.modifiers : [],
    });
  }

  if (!lineItems.length) {
    return { cart_draft_id: null, line_items: [], validation_errors: validationErrors };
  }

  // A stated budget is a constraint, not a hint. Storing it on the draft makes
  // it enforceable at finalize time rather than depending on the model to
  // check — which it demonstrably does not: asked for "$50" it assembled
  // $65.45, and for "under $40" it assembled $49.46.
  const budgetCents =
    typeof a.budget_cents === 'number' && a.budget_cents > 0
      ? Math.round(a.budget_cents)
      : null;

  const { data: draft, error: insErr } = await admin
    .from('concierge_cart_drafts')
    .insert({
      user_id: ctx.userId,
      restaurant_id: restaurantId,
      line_items: lineItems,
      constraints: {
        ...(a.constraints as Record<string, unknown> ?? {}),
        budget_cents: budgetCents,
      },
    })
    .select('id')
    .single();
  if (insErr) throw insErr;

  // Price immediately and report the budget verdict in the same breath, so the
  // model finds out it overspent while it can still fix it.
  const priced = await priceCart(ctx, { cart_draft_id: draft.id });

  return {
    cart_draft_id: draft.id,
    line_items: lineItems,
    total_cents: priced.total_cents,
    budget_cents: budgetCents,
    within_budget: priced.within_budget,
    over_budget_by_cents: priced.over_budget_by_cents,
    instruction: priced.within_budget === false
      ? 'OVER BUDGET. Rebuild with fewer or cheaper items before finalizing — finalize_cart will refuse this cart.'
      : undefined,
    validation_errors: validationErrors.length ? validationErrors : undefined,
  };
}

/** Loads a draft and proves the caller owns it. */
async function loadDraft(ctx: Ctx, draftId: string) {
  const { data, error } = await admin
    .from('concierge_cart_drafts')
    .select('*')
    .eq('id', draftId)
    .single();
  if (error || !data) throw new Error('Cart draft not found');
  if (data.user_id !== ctx.userId) throw new Error('Not your cart draft');
  return data;
}

async function priceCart(ctx: Ctx, a: Record<string, unknown>) {
  const draft = await loadDraft(ctx, a.cart_draft_id as string);
  const lines = (draft.line_items as Record<string, unknown>[]) ?? [];

  // Re-price from the live menu rather than trusting the snapshot: a draft may
  // be minutes old and a price may have moved. The customer is never shown a
  // total computed from a stale number.
  const ids = lines.map((l) => l.item_id as string);
  const { data: fresh } = await admin
    .from('menus')
    .select('id, price, is_available')
    .in('id', ids);
  const priceById = new Map((fresh ?? []).map((f) => [f.id, f]));

  let subtotal = 0;
  const stale: string[] = [];
  for (const l of lines) {
    const live = priceById.get(l.item_id as string);
    if (!live || !live.is_available) {
      stale.push(l.name as string);
      continue;
    }
    const cents = toCents(live.price);
    if (cents !== l.unit_price_cents) stale.push(l.name as string);
    subtotal += cents * (l.qty as number);
  }

  const { data: r } = await admin
    .from('restaurants')
    .select('delivery_fee, service_fee, minimum_order_amount')
    .eq('id', draft.restaurant_id)
    .single();

  const delivery = toCents(r?.delivery_fee);
  const fees = toCents(r?.service_fee);
  const tip = Math.max(0, Number(a.tip_cents) || 0);

  // Discount is recomputed here from the stored code so it can never be
  // inflated by anything the model said.
  let discount = 0;
  if (draft.applied_promo_code) {
    discount = await computeDiscountCents(
      draft.applied_promo_code as string,
      subtotal,
      draft.restaurant_id as string,
    );
  }

  const total = Math.max(0, subtotal - discount) + fees + delivery + tip;

  // Budget covers the TOTAL the customer pays, not just the food — someone with
  // $40 does not have $40 plus fees.
  const budget = (draft.constraints as Record<string, unknown> | null)
    ?.budget_cents as number | null | undefined;
  const withinBudget = typeof budget === 'number' ? total <= budget : null;

  return {
    subtotal_cents: subtotal,
    discount_cents: discount,
    fees_cents: fees,
    tax_cents: 0, // this deployment prices tax inclusive; kept for contract shape
    delivery_cents: delivery,
    tip_cents: tip,
    total_cents: total,
    currency: 'USD',
    minimum_order_cents: toCents(r?.minimum_order_amount),
    meets_minimum: subtotal >= toCents(r?.minimum_order_amount),
    budget_cents: typeof budget === 'number' ? budget : undefined,
    within_budget: withinBudget,
    over_budget_by_cents:
      withinBudget === false ? total - (budget as number) : undefined,
    repriced_items: stale.length ? stale : undefined,
  };
}

/** Single source of truth for what a code is worth against a subtotal. */
async function computeDiscountCents(
  code: string,
  subtotalCents: number,
  restaurantId: string,
): Promise<number> {
  const { data: p } = await admin
    .from('promo_codes')
    .select('*')
    .ilike('code', code)
    .eq('is_active', true)
    .maybeSingle();
  if (!p) return 0;

  if (p.restaurant_id && p.restaurant_id !== restaurantId) return 0;
  if (p.min_order_amount && subtotalCents < toCents(p.min_order_amount)) return 0;
  const now = Date.now();
  if (p.valid_from && new Date(p.valid_from).getTime() > now) return 0;
  const expiry = p.valid_until ?? p.expires_at;
  if (expiry && new Date(expiry).getTime() < now) return 0;
  const limit = p.usage_limit ?? p.max_uses;
  if (limit != null && (p.usage_count ?? 0) >= limit) return 0;

  let d = 0;
  if (p.discount_type === 'percentage') {
    d = Math.round(subtotalCents * (Number(p.discount_value) / 100));
  } else {
    d = toCents(Number(p.discount_value));
  }
  if (p.max_discount_amount) {
    d = Math.min(d, toCents(p.max_discount_amount));
  }
  return Math.max(0, Math.min(d, subtotalCents));
}

async function getEligiblePromotions(ctx: Ctx, a: Record<string, unknown>) {
  const draft = await loadDraft(ctx, a.cart_draft_id as string);
  const lines = (draft.line_items as Record<string, unknown>[]) ?? [];
  const subtotal = lines.reduce(
    (s, l) => s + (l.unit_price_cents as number) * (l.qty as number),
    0,
  );

  const { data: codes } = await admin
    .from('promo_codes')
    .select('code, description, restaurant_id, min_order_amount')
    .eq('is_active', true)
    .or(`restaurant_id.is.null,restaurant_id.eq.${draft.restaurant_id}`)
    .limit(60);

  const promotions = [];
  for (const c of codes ?? []) {
    const savings = await computeDiscountCents(
      c.code,
      subtotal,
      draft.restaurant_id as string,
    );
    if (savings > 0) {
      promotions.push({
        code: c.code,
        description: c.description,
        savings_cents: savings,
        stackable: false,
      });
    }
  }

  // Best saving first — the concierge should never quietly apply a worse code.
  promotions.sort((x, y) => y.savings_cents - x.savings_cents);
  return { promotions: promotions.slice(0, 10) };
}

async function applyPromotion(ctx: Ctx, a: Record<string, unknown>) {
  const draft = await loadDraft(ctx, a.cart_draft_id as string);
  if (draft.status !== 'draft') {
    return { applied: false, reason: 'This cart is already finalized' };
  }
  const lines = (draft.line_items as Record<string, unknown>[]) ?? [];
  const subtotal = lines.reduce(
    (s, l) => s + (l.unit_price_cents as number) * (l.qty as number),
    0,
  );
  const code = String(a.code ?? '');
  const savings = await computeDiscountCents(
    code,
    subtotal,
    draft.restaurant_id as string,
  );
  if (savings <= 0) {
    return { applied: false, reason: 'That code is not valid for this order' };
  }

  await admin
    .from('concierge_cart_drafts')
    .update({ applied_promo_code: code, updated_at: new Date().toISOString() })
    .eq('id', draft.id);

  const priced = await priceCart(ctx, { cart_draft_id: draft.id });
  return { applied: true, new_total_cents: priced.total_cents, savings_cents: savings };
}

async function finalizeCart(ctx: Ctx, a: Record<string, unknown>) {
  const draft = await loadDraft(ctx, a.cart_draft_id as string);
  const priced = await priceCart(ctx, { cart_draft_id: draft.id });

  // Hard stop. The customer named a number; handing them a cart above it is a
  // failure of the request, not a detail to mention afterwards.
  if (priced.within_budget === false) {
    throw new Error(
      `Total $${(priced.total_cents / 100).toFixed(2)} exceeds the customer's ` +
        `budget of $${((priced.budget_cents as number) / 100).toFixed(2)}. ` +
        'Rebuild the cart with fewer or cheaper items.',
    );
  }

  if (!priced.meets_minimum) {
    throw new Error(
      `Order is below this restaurant's minimum of $${(priced.minimum_order_cents / 100).toFixed(2)}`,
    );
  }
  await admin
    .from('concierge_cart_drafts')
    .update({ status: 'finalized', updated_at: new Date().toISOString() })
    .eq('id', draft.id);
  return { cart_id: draft.id };
}

async function handoffToCheckout(ctx: Ctx, a: Record<string, unknown>) {
  const draft = await loadDraft(ctx, a.cart_id as string);
  if (draft.status === 'draft') throw new Error('Cart is not finalized yet');
  await admin
    .from('concierge_cart_drafts')
    .update({ status: 'consumed', updated_at: new Date().toISOString() })
    .eq('id', draft.id);
  // A route the app already owns — the customer lands on the existing cart and
  // completes the normal checkout. Nothing here charges anyone.
  return { checkout_url: '/cart' };
}

// ════════════════════════════════════════════════════════════════════════════
// MENU CLASSIFICATION (mode: "classify")
// ════════════════════════════════════════════════════════════════════════════

const BATCH_SIZE = 20;

const CLASSIFY_SYSTEM_PROMPT = `You classify restaurant menu items for a food delivery app's dietary filter.

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
        { role: 'system', content: CLASSIFY_SYSTEM_PROMPT },
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


/**
 * One-time (re-runnable) menu classification. Admin or service-role only.
 * Idempotent and never overwrites a restaurant/admin assertion.
 */
async function handleClassify(token: string, body: Record<string, unknown>) {
  let claims: { sub?: string; role?: string };
  try {
    claims = JSON.parse(atob(token.split('.')[1]));
  } catch {
    return json({ error: 'Malformed token' }, 401);
  }

  // Service role is backend/ops tooling and already holds full database rights.
  // Any other caller must be an admin ACCORDING TO THE DATABASE — the token's
  // own claims are never taken as proof of that.
  if (claims.role !== 'service_role') {
    if (!claims.sub) return json({ error: 'Not authenticated' }, 401);
    const { data: caller } = await admin
      .from('users').select('role').eq('id', claims.sub).single();
    if (caller?.role !== 'admin') return json({ error: 'Admin only' }, 403);
  }

  const reclassify = body.reclassify === true;
  const limit = Math.min(Number(body.limit) || 250, 500);

  let query = admin
    .from('menus')
    .select('id, name, description')
    .eq('is_available', true)
    // Least-recently-classified first, so repeated calls march through the
    // whole menu. Without this an unordered LIMIT kept handing back the same
    // rows and a six-call loop only ever touched 47 of 211 items.
    .order('dietary_classified_at', { ascending: true, nullsFirst: true })
    .limit(limit);

  query = reclassify
    ? query.or('dietary_source.is.null,dietary_source.eq.ai')
    : query.is('dietary_source', null);

  const { data: rows, error } = await query;
  if (error) throw error;

  const items = (rows ?? []) as MenuRow[];
  if (!items.length) return json({ classified: 0, message: 'Nothing left to classify' });

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
      if (!id || !byId.has(id)) continue; // never write an id we did not send

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
        .or('dietary_source.is.null,dietary_source.eq.ai');

      if (upErr) failures.push(`${id}: ${upErr.message}`);
      else classified++;
    }
  }

  return json({
    classified,
    considered: items.length,
    failures: failures.slice(0, 10),
    failure_count: failures.length,
  });
}

/**
 * Whisper transcription of a short recording. Audio arrives base64-encoded,
 * is forwarded straight to OpenAI, and is never written to storage or logged —
 * there is no reason to retain a customer's voice once it is text.
 */
async function handleTranscribe(body: Record<string, unknown>) {
  const b64 = String(body.audio_base64 ?? '');
  if (!b64) return json({ error: 'No audio supplied' }, 400);

  // ~10MB of base64 is far more than a spoken order needs; anything larger is
  // a bug or an abuse attempt rather than a request.
  if (b64.length > 10_000_000) return json({ error: 'Recording too long' }, 413);

  let bytes: Uint8Array;
  try {
    const bin = atob(b64);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch {
    return json({ error: 'Malformed audio' }, 400);
  }

  const form = new FormData();
  form.append('file', new Blob([bytes], { type: 'audio/m4a' }), 'audio.m4a');
  form.append('model', 'whisper-1');
  // The customer is ordering food, so nudge the decoder toward the domain and
  // away from generic near-silence hallucinations.
  form.append(
    'prompt',
    'A customer ordering food delivery, naming dishes, restaurants, a budget and dietary needs.',
  );

  const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${OPENAI_API_KEY}` },
    body: form,
  });
  if (!res.ok) {
    return json({ error: `Transcription failed (${res.status})` }, 502);
  }

  const out = await res.json();
  const text = String(out.text ?? '').trim();

  // Whisper emits a small set of stock phrases when handed near-silence.
  // Returning those as if the customer said them produces a baffling reply, so
  // treat them as "nothing was captured".
  const noise = new Set([
    'you', 'thank you', 'thanks for watching!', 'thank you.', 'bye.', '.', 'the',
  ]);
  if (!text || noise.has(text.toLowerCase())) {
    return json({ text: '', empty: true });
  }

  return json({ text });
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });
}

// ════════════════════════════════════════════════════════════════════════════
// ORCHESTRATION
// ════════════════════════════════════════════════════════════════════════════

const TOOL_IMPLS: Record<
  string,
  (ctx: Ctx, a: Record<string, unknown>) => Promise<unknown>
> = {
  search_dishes: searchDishes,
  search_restaurants: searchRestaurants,
  check_delivery_eta: checkDeliveryEta,
  get_menu: getMenu,
  filter_menu_items: filterMenuItems,
  build_cart_draft: buildCartDraft,
  price_cart: priceCart,
  get_eligible_promotions: getEligiblePromotions,
  apply_promotion: applyPromotion,
  finalize_cart: finalizeCart,
  handoff_to_checkout: handoffToCheckout,
};

const TOOLS = [
  {
    type: 'function',
    function: {
      name: 'search_dishes',
      description:
        'FIND DISHES BY NAME across all restaurants. Use this FIRST whenever the customer names a food ("jerk chicken", "soup", "burger", "rice and peas"). Returns matching dishes with their restaurant. Do not try to guess a cuisine and use search_restaurants instead — that will miss dishes that exist.',
      parameters: {
        type: 'object',
        properties: {
          query: {
            type: 'string',
            description: 'The food the customer named, in their words.',
          },
          dietary_exclusions: { type: 'array', items: { type: 'string' } },
          dietary_requirements: { type: 'array', items: { type: 'string' } },
          flavor_tags: { type: 'array', items: { type: 'string' } },
          max_item_price_cents: { type: 'integer' },
          limit: { type: 'integer' },
        },
        required: ['query'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'search_restaurants',
      description:
        'Find restaurants that can actually serve this request. Returns only restaurants with at least one available item passing the dietary filters.',
      parameters: {
        type: 'object',
        properties: {
          cuisines: { type: 'array', items: { type: 'string' } },
          flavor_tags: { type: 'array', items: { type: 'string' } },
          dietary_exclusions: { type: 'array', items: { type: 'string' } },
          dietary_requirements: { type: 'array', items: { type: 'string' } },
          max_price_tier: { type: 'integer', minimum: 1, maximum: 4 },
          open_at_local: { type: 'string' },
          limit: { type: 'integer' },
        },
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'check_delivery_eta',
      description: 'Whether a restaurant can deliver and by when.',
      parameters: {
        type: 'object',
        properties: { restaurant_id: { type: 'string' } },
        required: ['restaurant_id'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'filter_menu_items',
      description:
        'Menu items for a restaurant with dietary/flavour filters re-applied server-side. Use this rather than get_menu whenever the customer stated a constraint.',
      parameters: {
        type: 'object',
        properties: {
          restaurant_id: { type: 'string' },
          dietary_exclusions: { type: 'array', items: { type: 'string' } },
          dietary_requirements: { type: 'array', items: { type: 'string' } },
          flavor_tags: { type: 'array', items: { type: 'string' } },
          max_item_price_cents: { type: 'integer' },
        },
        required: ['restaurant_id'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_menu',
      description: 'Full available menu for a restaurant.',
      parameters: {
        type: 'object',
        properties: { restaurant_id: { type: 'string' } },
        required: ['restaurant_id'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'build_cart_draft',
      description:
        'Assemble a proposed cart. Supply item ids and quantities only — names and prices are read from the database.',
      parameters: {
        type: 'object',
        properties: {
          restaurant_id: { type: 'string' },
          items: {
            type: 'array',
            items: {
              type: 'object',
              properties: {
                item_id: { type: 'string' },
                qty: { type: 'integer' },
              },
              required: ['item_id', 'qty'],
            },
          },
          budget_cents: {
            type: 'integer',
            description:
              "The customer's stated budget in cents, if they gave one. ALWAYS pass this when a number was mentioned — it is enforced, and finalize_cart will refuse a cart above it.",
          },
        },
        required: ['restaurant_id', 'items'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'price_cart',
      description: 'Authoritative totals in integer cents.',
      parameters: {
        type: 'object',
        properties: {
          cart_draft_id: { type: 'string' },
          tip_cents: { type: 'integer' },
        },
        required: ['cart_draft_id'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'get_eligible_promotions',
      description: 'Promotions this cart actually qualifies for, best first.',
      parameters: {
        type: 'object',
        properties: { cart_draft_id: { type: 'string' } },
        required: ['cart_draft_id'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'apply_promotion',
      description: 'Apply a promo code to the draft.',
      parameters: {
        type: 'object',
        properties: {
          cart_draft_id: { type: 'string' },
          code: { type: 'string' },
        },
        required: ['cart_draft_id', 'code'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'finalize_cart',
      description: 'Lock the draft. Still not an order.',
      parameters: {
        type: 'object',
        properties: { cart_draft_id: { type: 'string' } },
        required: ['cart_draft_id'],
      },
    },
  },
  {
    type: 'function',
    function: {
      name: 'handoff_to_checkout',
      description:
        'Hand the finalized cart to the checkout screen for the customer to confirm and pay.',
      parameters: {
        type: 'object',
        properties: { cart_id: { type: 'string' } },
        required: ['cart_id'],
      },
    },
  },
];

const SYSTEM_PROMPT = `You are the 7Dash Food Concierge. You turn a natural request into a ready-to-confirm cart.

WHAT YOU DO
Understand the request, find real dishes, choose the best ones, build a cart draft, price it, apply the best eligible promotion, finalize, and hand off to checkout.

HOW TO SEARCH — THIS MATTERS
- If the customer NAMES A FOOD ("jerk chicken", "soup", "burger", "rice and peas"), call search_dishes with their words. That searches every menu by name.
- Only use search_restaurants when they describe a KIND of place rather than a dish ("somewhere cheap", "Italian", "something spicy") with no specific food named.
- NEVER conclude a dish is unavailable after a single search. If search_dishes returns nothing, try the core noun alone ("jerk chicken" -> "jerk", "chicken"; "rice and peas" -> "rice"). Only say something is unavailable once a simplified search has also come back empty.
- Do not guess cuisine labels. Guessing a cuisine and finding nothing is not evidence the food is missing.

FINISH THE JOB — ONE ANSWER, NOT A MENU
Hand back ONE built cart. Never present options 1/2/3 and ask which they prefer; they asked you to handle it, and a numbered list is you refusing to decide. Pick the single best match, build it, price it, finalize it, hand off.

Only ask a question when a genuine blocker stops you: nothing viable within budget, or a stated dietary need cannot be met.

If the customer gives no constraints ("anything", "something nice"), that is permission to choose. Pick something well rated and get on with it.

BE FAST
Do not browse. One search, pick from those results, build. Do not call get_menu or filter_menu_items to "double check" a dish that search_dishes already returned — it came from the same database and is already filtered. Do not call check_delivery_eta when the search result already carries eta_minutes. Every extra call is seconds the customer waits.

WRITING THE REPLY
2-3 sentences. Name the restaurant, the dishes, the total from price_cart, and the ETA. Do not write markdown links or URLs of any kind — the app renders its own checkout button.

HARD RULES
- You do not invent restaurants, dishes, prices, or ids. Everything comes from tool results.
- You never state a price you were not given by price_cart or a tool result.
- You never filter dietary constraints yourself. Pass them to the tools; the server enforces them. If you "remember" to avoid pork instead of passing dietary_exclusions, you have failed.
- Always pass the customer's stated exclusions to EVERY item-returning call.
- If a tool reports unsupported_exclusions, tell the customer plainly that you could not honour that constraint. Never let it pass silently.
- If an item's dietary_source is "ai", the dietary flags were inferred from the menu description, not confirmed by the restaurant. When the customer's request was dietary (pork, shellfish, allergens), say so in one short sentence so they can check.
- You never place an order or take payment. handoff_to_checkout is as far as you go; the customer confirms and pays there.

BUDGET — ENFORCED, NOT ADVISORY
If the customer names any amount, pass it as budget_cents to build_cart_draft. It covers the TOTAL including delivery and fees, not just the food. build_cart_draft tells you immediately whether you are within it, and finalize_cart will REFUSE a cart that is over. If you are over, rebuild with fewer or cheaper items — do not finalize and mention the overspend afterwards.

STYLE
Be brief and concrete. Name the restaurant and the dishes, give the total once you have it from price_cart, and say when it should arrive. No filler.`;

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  const started = Date.now();
  let ctx: Ctx | null = null;
  const toolTrace: unknown[] = [];

  try {
    const token = (req.headers.get('Authorization') ?? '').replace('Bearer ', '');
    if (!token) throw new Error('Not authenticated');

    // The menu classifier lives here as a mode rather than as its own function:
    // this project is at its edge-function quota, and classification is
    // squarely part of the concierge's domain (it exists so the concierge can
    // filter on real columns instead of guessing from descriptions).
    const peek = await req.clone().json().catch(() => ({}));
    if (peek?.mode === 'classify') {
      return await handleClassify(token, peek);
    }
    // Voice input for the concierge. Transcription is server-side so the
    // OpenAI key never ships in the client, and Whisper is the ONLY transcript
    // — the on-device recogniser is not consulted at all. On this project's own
    // test hardware its offline language pack is broken and listen() hangs
    // indefinitely rather than erroring, which previously stalled the entire
    // capture on an engine whose output wasn't trusted anyway.
    if (peek?.mode === 'transcribe') {
      return await handleTranscribe(peek);
    }

    let claims: { sub?: string; role?: string };
    try {
      claims = JSON.parse(atob(token.split('.')[1]));
    } catch {
      throw new Error('Malformed token');
    }
    if (!claims.sub || claims.role === 'anon') throw new Error('Not authenticated');

    // Location is read from the profile, never accepted from the caller or the
    // model — otherwise either could point the search somewhere else.
    const { data: profile } = await admin
      .from('user_addresses')
      .select('latitude, longitude')
      .eq('user_id', claims.sub)
      .order('is_default', { ascending: false })
      .limit(1)
      .maybeSingle();

    ctx = {
      userId: claims.sub,
      lat: profile?.latitude ?? null,
      lng: profile?.longitude ?? null,
    };

    const body = await req.json();
    const messages: Record<string, unknown>[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      ...(Array.isArray(body.history) ? body.history : []),
      { role: 'user', content: String(body.message ?? '') },
    ];

    let finalText = '';
    let draftId: string | null = null;
    let checkoutUrl: string | null = null;

    // Bounded agent loop. The cap is a safety rail, not a target: a runaway
    // model must not be able to spend unbounded tokens or hammer the database.
    for (let turn = 0; turn < 8; turn++) {
      const res = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${OPENAI_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          temperature: 0.2,
          messages,
          tools: TOOLS,
        }),
      });
      if (!res.ok) throw new Error(`OpenAI ${res.status}: ${await res.text()}`);

      const json = await res.json();
      const msg = json.choices[0].message;
      messages.push(msg);

      const calls = msg.tool_calls ?? [];
      if (calls.length === 0) {
        finalText = msg.content ?? '';
        break;
      }

      for (const call of calls) {
        const name = call.function.name;
        let args: Record<string, unknown> = {};
        try {
          args = JSON.parse(call.function.arguments || '{}');
        } catch { /* fall through with empty args */ }

        let result: unknown;
        try {
          const impl = TOOL_IMPLS[name];
          result = impl
            ? await impl(ctx, args)
            : { error: `Unknown tool ${name}` };
        } catch (e) {
          // Tool failures are returned to the model as data so it can adapt
          // (pick another restaurant, drop an item) rather than the whole
          // request dying.
          result = { error: (e as Error).message };
        }

        const r = result as Record<string, unknown>;
        if (r?.cart_draft_id) draftId = r.cart_draft_id as string;
        if (r?.cart_id) draftId = r.cart_id as string;
        if (r?.checkout_url) checkoutUrl = r.checkout_url as string;

        toolTrace.push({ name, args });
        messages.push({
          role: 'tool',
          tool_call_id: call.id,
          content: JSON.stringify(result),
        });
      }
    }

    // Always return the server's own numbers alongside the prose, so the client
    // renders totals from the database rather than parsing them out of text.
    let pricing: unknown = null;
    if (draftId) {
      try {
        pricing = await priceCart(ctx, { cart_draft_id: draftId });
      } catch { /* draft may already be consumed */ }
    }

    // The loop exits on either "no more tool calls" or the turn cap. Hitting
    // the cap mid-sequence leaves no prose at all — the work is done and priced
    // but the customer is shown nothing. One final completion with the tools
    // withheld forces a summary of what was actually assembled.
    if (!finalText.trim()) {
      const wrap = await fetch('https://api.openai.com/v1/chat/completions', {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${OPENAI_API_KEY}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          model: 'gpt-4o-mini',
          temperature: 0.2,
          messages: [
            ...messages,
            {
              role: 'user',
              content:
                'Summarise for the customer in 2-3 sentences what you put in their cart and what it costs, using only figures from the tool results above. Do not call any more tools.',
            },
          ],
        }),
      });
      if (wrap.ok) {
        const wj = await wrap.json();
        finalText = wj.choices?.[0]?.message?.content ?? '';
      }
    }

    await admin.from('concierge_sessions').insert({
      user_id: ctx.userId,
      request_text: String(body.message ?? '').slice(0, 2000),
      tool_calls: toolTrace,
      cart_draft_id: draftId,
      outcome: checkoutUrl ? 'handoff' : draftId ? 'draft' : 'reply',
      latency_ms: Date.now() - started,
    });

    return new Response(
      JSON.stringify({
        message: finalText,
        cart_draft_id: draftId,
        pricing,
        checkout_url: checkoutUrl,
      }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } },
    );
  } catch (e) {
    const message = (e as Error).message;
    if (ctx) {
      await admin.from('concierge_sessions').insert({
        user_id: ctx.userId,
        tool_calls: toolTrace,
        outcome: 'error',
        error: message,
        latency_ms: Date.now() - started,
      });
    }
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    });
  }
});

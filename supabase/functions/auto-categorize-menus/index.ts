// auto-categorize-menus — Supabase Edge Function
//
// Scans every food menu item and re-tags it with the closest canonical
// home-screen category (Breakfast, Pizza, Coffee, etc.) using a deterministic
// keyword "brain". Designed to run once a day via pg_cron so any newly added
// dish automatically shows up under the right category chip on the customer
// home screen, even if the restaurant typed something custom (e.g. "espresso"
// → "Coffee", "Margherita" → "Pizza").
//
// Auth: invoke with the service role key OR call from inside Supabase via
// pg_cron / net.http_post (which inherits the project URL + service role).
//
// Deploy: supabase functions deploy auto-categorize-menus --no-verify-jwt
//
// Manual run:
//   curl -X POST <project>/functions/v1/auto-categorize-menus \
//        -H "Authorization: Bearer <service_role_key>"
//
// Body (optional):
//   { "force": true }  // re-tag everything, even items already on a canonical category
//   { "dryRun": true } // log proposed changes but don't write
//
// Returns: { scanned, updated, skipped, byCategory }
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });

// Canonical home-screen categories — must stay aligned with
// `AppConstants.homeFoodCategories` in lib/config/app_constants.dart.
const CANONICAL = [
  "Breakfast",
  "Fast Food",
  "Pizza",
  "Chicken",
  "Mexican",
  "Chinese",
  "Sushi",
  "Healthy",
  "Dessert",
  "Coffee",
  "Drinks",
  "Vegan",
];
const CANONICAL_LOWER = new Set(CANONICAL.map((c) => c.toLowerCase()));

// Keyword brain: ordered by specificity. First strong hit wins, ties break by
// score. Each keyword scores +2 (token), +1 (substring).
const RULES: Array<{ category: string; tokens: string[] }> = [
  {
    category: "Pizza",
    tokens: [
      "pizza",
      "margherita",
      "pepperoni",
      "calzone",
      "stromboli",
      "flatbread",
    ],
  },
  {
    category: "Sushi",
    tokens: [
      "sushi",
      "sashimi",
      "maki",
      "nigiri",
      "tempura",
      "ramen",
      "udon",
      "miso",
      "teriyaki",
      "bento",
      "poke",
    ],
  },
  {
    category: "Mexican",
    tokens: [
      "taco",
      "burrito",
      "quesadilla",
      "nacho",
      "fajita",
      "enchilada",
      "guacamole",
      "salsa",
      "chimichanga",
      "tostada",
      "tortilla",
      "churro",
    ],
  },
  {
    category: "Chinese",
    tokens: [
      "chow mein",
      "lo mein",
      "fried rice",
      "kung pao",
      "general tso",
      "sweet and sour",
      "egg roll",
      "spring roll",
      "wonton",
      "dumpling",
      "dim sum",
      "szechuan",
      "hunan",
      "peking",
      "moo shu",
      "chop suey",
      "bao",
    ],
  },
  {
    category: "Chicken",
    tokens: [
      "chicken",
      "wings",
      "drumstick",
      "tender",
      "nugget",
      "rotisserie",
      "fried chicken",
      "jerk chicken",
      "chicken sandwich",
    ],
  },
  {
    category: "Breakfast",
    tokens: [
      "breakfast",
      "pancake",
      "waffle",
      "omelet",
      "omelette",
      "bagel",
      "toast",
      "french toast",
      "bacon",
      "sausage",
      "hash brown",
      "ackee",
      "saltfish",
      "porridge",
      "oatmeal",
      "granola",
      "muffin",
      "croissant",
      "egg",
      "eggs",
    ],
  },
  {
    category: "Coffee",
    tokens: [
      "coffee",
      "espresso",
      "latte",
      "cappuccino",
      "americano",
      "macchiato",
      "mocha",
      "cold brew",
      "frappuccino",
      "frappe",
      "cortado",
      "flat white",
    ],
  },
  {
    category: "Drinks",
    tokens: [
      "smoothie",
      "juice",
      "lemonade",
      "soda",
      "milkshake",
      "shake",
      "boba",
      "bubble tea",
      "tea",
      "iced tea",
      "kombucha",
      "water",
      "soft drink",
      "drink",
      "beverage",
      "cocktail",
    ],
  },
  {
    category: "Dessert",
    tokens: [
      "dessert",
      "cake",
      "cheesecake",
      "brownie",
      "cookie",
      "ice cream",
      "gelato",
      "sorbet",
      "donut",
      "doughnut",
      "pastry",
      "pie",
      "cupcake",
      "tart",
      "pudding",
      "tiramisu",
      "sundae",
      "candy",
      "chocolate",
    ],
  },
  {
    category: "Vegan",
    tokens: [
      "vegan",
      "plant based",
      "plant-based",
      "tofu",
      "tempeh",
      "seitan",
      "vegetable bowl",
      "impossible",
      "beyond",
      "jackfruit",
    ],
  },
  {
    category: "Healthy",
    tokens: [
      "salad",
      "bowl",
      "quinoa",
      "kale",
      "wrap",
      "grain bowl",
      "buddha bowl",
      "acai",
      "lean",
      "protein bowl",
      "low carb",
      "low-carb",
      "keto",
      "fresh",
    ],
  },
  {
    category: "Fast Food",
    tokens: [
      "burger",
      "cheeseburger",
      "hamburger",
      "fries",
      "fried",
      "hot dog",
      "sandwich",
      "sub",
      "combo",
      "meal deal",
      "milkshake",
    ],
  },
];

function scoreCategory(text: string): { category: string | null; score: number } {
  const t = ` ${text.toLowerCase()} `;
  let best: { category: string; score: number } | null = null;
  for (const rule of RULES) {
    let s = 0;
    for (const kw of rule.tokens) {
      const k = kw.toLowerCase();
      // word-boundary token match scores higher than a loose substring
      const tokenRe = new RegExp(`\\b${k.replace(/[.*+?^${}()|[\\]\\\\]/g, "\\\\$&")}\\b`);
      if (tokenRe.test(t)) {
        s += 2;
      } else if (t.includes(` ${k} `) || t.includes(k)) {
        s += 1;
      }
    }
    if (s > 0 && (best === null || s > best.score)) {
      best = { category: rule.category, score: s };
    }
  }
  return best ?? { category: null, score: 0 };
}

interface MenuRow {
  id: string;
  name: string | null;
  description: string | null;
  category: string | null;
  tags: string[] | null;
  is_vegan: boolean | null;
  is_vegetarian: boolean | null;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRole = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRole) {
    return json({ error: "Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY" }, 500);
  }
  const admin = createClient(supabaseUrl, serviceRole);

  let body: { force?: boolean; dryRun?: boolean } = {};
  if (req.method !== "GET") {
    try {
      const text = await req.text();
      if (text) body = JSON.parse(text);
    } catch (_) {
      /* ignore */
    }
  }
  const { force = false, dryRun = false } = body;

  // Pull all food menu items in pages.
  const PAGE = 1000;
  let from = 0;
  const updates: Array<{ id: string; category: string }> = [];
  const byCategory: Record<string, number> = {};
  let scanned = 0;
  let skipped = 0;

  while (true) {
    const { data, error } = await admin
      .from("menus")
      .select("id, name, description, category, tags, is_vegan, is_vegetarian")
      .or("product_type.eq.food,product_type.is.null")
      .range(from, from + PAGE - 1);
    if (error) {
      return json({ error: "Failed to read menus", details: error.message }, 500);
    }
    const rows = (data ?? []) as MenuRow[];
    if (rows.length === 0) break;

    for (const row of rows) {
      scanned++;

      const currentLower = (row.category ?? "").toLowerCase().trim();
      const alreadyCanonical = CANONICAL_LOWER.has(currentLower);
      if (alreadyCanonical && !force) {
        skipped++;
        continue;
      }

      // Compose the text the brain looks at: name + description + tags.
      const tagText = Array.isArray(row.tags) ? row.tags.join(" ") : "";
      const text = [row.name ?? "", row.description ?? "", tagText].join(" ");
      const { category } = scoreCategory(text);

      // Vegan boost: explicit DB flags override keyword brain when nothing
      // stronger has been picked.
      let chosen = category;
      if (!chosen && row.is_vegan === true) chosen = "Vegan";
      // Default bucket so meals at least show up somewhere.
      chosen ??= "Fast Food";

      if (chosen.toLowerCase() === currentLower) {
        skipped++;
        continue;
      }

      updates.push({ id: row.id, category: chosen });
      byCategory[chosen] = (byCategory[chosen] ?? 0) + 1;
    }

    if (rows.length < PAGE) break;
    from += PAGE;
  }

  let updated = 0;
  if (!dryRun && updates.length > 0) {
    // Update in chunks to keep payloads small.
    const CHUNK = 200;
    for (let i = 0; i < updates.length; i += CHUNK) {
      const chunk = updates.slice(i, i + CHUNK);
      // Group by target category to issue a small number of UPDATEs.
      const grouped = new Map<string, string[]>();
      for (const u of chunk) {
        const arr = grouped.get(u.category) ?? [];
        arr.push(u.id);
        grouped.set(u.category, arr);
      }
      for (const [cat, ids] of grouped) {
        const { error } = await admin
          .from("menus")
          .update({ category: cat })
          .in("id", ids);
        if (error) {
          console.error("update error", cat, error.message);
        } else {
          updated += ids.length;
        }
      }
    }
  }

  return json({
    scanned,
    updated: dryRun ? 0 : updated,
    proposed: updates.length,
    skipped,
    dryRun,
    force,
    byCategory,
  });
});

// Daily stock sync for the Master Mac Food grocery store.
//
// Master Mac's HotBite catalogue was imported from their own WooCommerce site
// (stonyhill.mastermacfood.com), which marks sold-out products with an
// `outofstock` CSS class. Their REST API is disabled, so we scrape the category
// pages, read each product's stock status, match by (normalised) name to the
// store's HotBite products, and set `menus.is_available` accordingly:
//   out of stock on the site  -> is_available = false (hidden from customers)
//   back in stock on the site -> is_available = true  (shown again)
//
// The grocery surfaces already filter is_available = true, so a hidden product
// simply disappears from HotBite. Runs daily via pg_cron; can also be invoked
// manually (admin/service-role) for an on-demand refresh.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BASE = "https://stonyhill.mastermacfood.com";
const STORE_NAME = "Master Mac Food";
const CATS = [
  "beverages", "groceries", "general-food", "general-item", "liquor",
  "baby-item", "snacks-sweet", "meat-bulk", "meat", "pet-products", "water",
];
const UA =
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0 Safari/537.36";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (b: unknown, s = 200) =>
  new Response(JSON.stringify(b), { status: s, headers: { ...cors, "Content-Type": "application/json" } });

// Normalise a product name so the site and the DB match despite entity encoding
// and irregular spacing (both came from the same source, so names line up well).
function norm(s: string): string {
  return s
    .replace(/&#0?38;/g, "&")
    .replace(/&amp;/g, "&")
    .replace(/&#0?39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&nbsp;/g, " ")
    .replace(/ /g, " ")
    .replace(/\s+/g, " ")
    .trim()
    .toUpperCase();
}

const LI = /<li[^>]*class="([^"]*product[^"]*)"[^>]*>([\s\S]*?)<\/li>/gi;
const TITLE = /woocommerce-loop-product__title">([^<]+)</i;

async function fetchPage(url: string): Promise<string | null> {
  try {
    const r = await fetch(url, { headers: { "User-Agent": UA, "Accept": "text/html" } });
    if (!r.ok) return null;
    return await r.text();
  } catch {
    return null;
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") ?? "",
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "",
  );

  // ── 1. Scrape every category for stock status ───────────────────────────
  const status = new Map<string, boolean>(); // norm name -> inStock
  let pagesFetched = 0;
  for (const cat of CATS) {
    for (let paged = 1; paged <= 400; paged++) {
      const doc = await fetchPage(`${BASE}/?product_cat=${cat}&paged=${paged}`);
      if (!doc) break;
      pagesFetched++;
      let found = 0;
      for (const m of doc.matchAll(LI)) {
        const cls = m[1].toLowerCase();
        const t = TITLE.exec(m[2]);
        if (!t) continue;
        found++;
        const name = norm(t[1]);
        const inStock = !cls.includes("outofstock");
        // A product may appear in several categories; it's out of stock only if
        // every listing says so.
        status.set(name, status.has(name) ? (status.get(name)! && inStock) : inStock);
      }
      if (found === 0) break;
    }
  }

  if (status.size === 0) {
    return json({ ok: false, error: "No products scraped (site blocked or layout changed)" }, 502);
  }

  // ── 2. Load the store's HotBite products ────────────────────────────────
  const { data: store } = await supabase
    .from("restaurants").select("id").eq("name", STORE_NAME).maybeSingle();
  if (!store) return json({ ok: false, error: "Master Mac Food store not found" }, 404);
  const storeId = store.id as string;

  const products: Array<{ id: string; name: string; is_available: boolean }> = [];
  const PAGE = 1000;
  for (let off = 0; ; off += PAGE) {
    const { data, error } = await supabase
      .from("menus").select("id, name, is_available")
      .eq("restaurant_id", storeId)
      .range(off, off + PAGE - 1);
    if (error) return json({ ok: false, error: error.message }, 500);
    if (!data || data.length === 0) break;
    products.push(...(data as typeof products));
    if (data.length < PAGE) break;
  }

  // ── 3. Decide which products to hide / show ─────────────────────────────
  const toHide: string[] = []; // currently available but out of stock on site
  const toShow: string[] = []; // currently hidden but back in stock on site
  let matched = 0;
  for (const p of products) {
    const inStock = status.get(norm(p.name));
    if (inStock === undefined) continue; // not found on the site this run — leave as-is
    matched++;
    if (!inStock && p.is_available) toHide.push(p.id);
    if (inStock && !p.is_available) toShow.push(p.id);
  }

  // ── 4. Apply in chunks ──────────────────────────────────────────────────
  async function setAvailability(ids: string[], value: boolean) {
    for (let i = 0; i < ids.length; i += 500) {
      const chunk = ids.slice(i, i + 500);
      const { error } = await supabase
        .from("menus").update({ is_available: value }).in("id", chunk);
      if (error) throw new Error(error.message);
    }
  }
  try {
    await setAvailability(toHide, false);
    await setAvailability(toShow, true);
  } catch (e) {
    return json({ ok: false, error: String((e as Error).message) }, 500);
  }

  return json({
    ok: true,
    pages_fetched: pagesFetched,
    site_products: status.size,
    site_out_of_stock: [...status.values()].filter((v) => !v).length,
    hotbite_products: products.length,
    matched,
    hidden_now: toHide.length,
    shown_now: toShow.length,
  });
});

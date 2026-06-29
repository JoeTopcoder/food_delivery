'use strict';

/**
 * Artillery processor — MealHub load test helpers
 * ────────────────────────────────────────────────────────────────────────────
 * KEY CHANGE from previous version:
 *   Auth scenarios now pick from a pool of 200 SEEDED users instead of
 *   generating random fake emails.  This eliminates the 400-invalid-credentials
 *   failures that inflated the "failure" rate to 40% in the ramp test.
 *
 *   Before seeding: 60.1% success (28k client errors from fake logins)
 *   After seeding:  target ≥85% auth / ≥95% public
 *
 * SEED USERS FIRST:
 *   Option A (SQL): Supabase Dashboard → SQL Editor → run seed-load-test-users.sql
 *   Option B (JS):  ENABLE_LOAD_TEST_SEED=true SUPABASE_SERVICE_ROLE_KEY=<key>
 *                   node load_tests/seed-load-test-users.js
 * ────────────────────────────────────────────────────────────────────────────
 */

const crypto = require('crypto');

// ── Seeded user pool ──────────────────────────────────────────────────────────
// Must match what seed-load-test-users.sql / seed-load-test-users.js created.
const SEEDED_USER_COUNT = 200;
const SEEDED_PASSWORD   = 'LoadTest123!Secure';

function seededEmail(n) {
  return `loadtest_${String(n).padStart(3, '0')}@test.mealhub.dev`;
}

// Pre-build the full pool so we don't format on every call.
const SEEDED_USERS = Array.from({ length: SEEDED_USER_COUNT }, (_, i) => ({
  email:    seededEmail(i + 1),
  password: SEEDED_PASSWORD,
}));

function randomSeededUser() {
  return SEEDED_USERS[Math.floor(Math.random() * SEEDED_USERS.length)];
}

// ── Runtime caches (populated during test run) ────────────────────────────────
const RESTAURANT_IDS = [];
const MENU_ITEM_IDS  = [];

// ── Misc pools ────────────────────────────────────────────────────────────────
const SEARCH_TERMS = [
  'pizza', 'burger', 'sushi', 'chicken', 'jerk', 'roti',
  'pasta', 'tacos', 'curry', 'rice', 'wings', 'lobster',
];
const ADDRESSES = [
  'George Town, Grand Cayman',
  'West Bay, Grand Cayman',
  'Bodden Town, Grand Cayman',
  'East End, Grand Cayman',
  'North Side, Grand Cayman',
];

// ── Context builders ──────────────────────────────────────────────────────────

/**
 * generateUserContext — called before every scenario.
 * For PUBLIC scenarios: injects a unique VU identity (used in logs only).
 * For AUTH scenarios:   picks a random SEEDED user so login will succeed.
 */
function generateUserContext(userContext, events, done) {
  const uid  = crypto.randomUUID();
  const user = randomSeededUser();

  // Public identity (unique per VU for tracing / idempotency keys)
  userContext.vars.uid         = uid;

  // Auth credentials — real seeded user, not a fake random email
  userContext.vars.email       = user.email;
  userContext.vars.password    = user.password;

  // Token starts empty; extractAuthToken fills it after login
  userContext.vars.authToken   = '';
  userContext.vars.userId      = '';

  // Misc
  userContext.vars.searchQuery = SEARCH_TERMS[Math.floor(Math.random() * SEARCH_TERMS.length)];
  userContext.vars.address     = ADDRESSES[Math.floor(Math.random() * ADDRESSES.length)];
  userContext.vars.restaurantId = RESTAURANT_IDS.length
    ? RESTAURANT_IDS[Math.floor(Math.random() * RESTAURANT_IDS.length)]
    : null;

  return done();
}

/**
 * extractAuthToken — afterResponse hook on POST /auth/v1/token.
 * Stores access_token and user_id in VU context.
 * Emits a counter on failure so the report can separate auth failures
 * from real backend errors.
 */
function extractAuthToken(requestParams, response, context, ee, next) {
  try {
    const body = JSON.parse(response.body);

    if (response.statusCode === 200 && body.access_token) {
      context.vars.authToken = body.access_token;
      context.vars.userId    = body.user?.id ?? '';
      ee.emit('counter', 'auth.login_success', 1);
    } else {
      // Log the actual status so the analyst can distinguish 400 vs 401 vs 429
      const code = response.statusCode;
      ee.emit('counter', `auth.login_failed_${code}`, 1);

      if (code === 400) {
        // 400 = invalid credentials.  After seeding this should NOT happen.
        // If you see this counter rising, the seed script hasn't been run.
        console.warn(`[auth] 400 Invalid credentials for ${context.vars.email}` +
          ' — have you run seed-load-test-users.sql?');
      } else if (code === 429) {
        console.warn('[auth] 429 Rate-limited on /auth/v1/token — reduce arrivalRate');
      }
    }
  } catch (e) {
    ee.emit('counter', 'auth.login_parse_error', 1);
  }
  return next();
}

/**
 * cacheRestaurantIds — afterResponse hook on GET /rest/v1/restaurants.
 * Builds a runtime pool of real IDs so later steps can reference them.
 */
function cacheRestaurantIds(requestParams, response, context, ee, next) {
  try {
    const body = JSON.parse(response.body);
    if (Array.isArray(body) && body.length > 0) {
      body.forEach(r => {
        if (r.id && !RESTAURANT_IDS.includes(r.id)) RESTAURANT_IDS.push(r.id);
        // Opportunistically set restaurantId for THIS VU
        if (!context.vars.restaurantId) context.vars.restaurantId = r.id;
      });
    }
  } catch (_) { /* non-JSON — ignore */ }
  return next();
}

/**
 * cacheMenuItemIds — afterResponse hook on GET /rest/v1/menus.
 */
function cacheMenuItemIds(requestParams, response, context, ee, next) {
  try {
    const body = JSON.parse(response.body);
    if (Array.isArray(body) && body.length > 0) {
      body.forEach(item => {
        if (item.id && !MENU_ITEM_IDS.includes(item.id)) MENU_ITEM_IDS.push(item.id);
      });
      // Set cheapest item on context for order simulation
      const first = body[0];
      if (first) {
        context.vars.menuItemId    = first.id;
        context.vars.menuItemPrice = first.price || 10.00;
        context.vars.menuItemName  = first.name  || 'Test Item';
      }
    }
  } catch (_) { /* ignore */ }
  return next();
}

/**
 * buildOrderPayload — called before POST to place-order edge function.
 * Uses real restaurant/menu IDs from the runtime cache when available.
 */
function buildOrderPayload(userContext, events, done) {
  const itemId = MENU_ITEM_IDS.length
    ? MENU_ITEM_IDS[Math.floor(Math.random() * MENU_ITEM_IDS.length)]
    : 'placeholder-item-id';
  const restId = RESTAURANT_IDS.length
    ? RESTAURANT_IDS[Math.floor(Math.random() * RESTAURANT_IDS.length)]
    : 'placeholder-restaurant-id';
  const price  = userContext.vars.menuItemPrice || 10.00;

  userContext.vars.orderPayload = JSON.stringify({
    user_id:            userContext.vars.userId || 'test-user',
    restaurant_id:      restId,
    items: [{
      menu_item_id: itemId,
      quantity:     1 + Math.floor(Math.random() * 2),
      unit_price:   price,
      item_name:    userContext.vars.menuItemName || 'Test Item',
    }],
    subtotal:           price,
    delivery_fee:       3.50,
    tax_amount:         parseFloat((price * 0.10).toFixed(2)),
    total_amount:       parseFloat((price + 3.50 + price * 0.10).toFixed(2)),
    delivery_address:   userContext.vars.address,
    delivery_latitude:  19.2869 + (Math.random() * 0.1 - 0.05),
    delivery_longitude: -81.3674 + (Math.random() * 0.1 - 0.05),
    payment_method:     'cash',
    is_pickup:          false,
    // Idempotency key — stable for this VU's order attempt
    idempotency_key:    crypto.randomUUID(),
  });
  return done();
}

/**
 * logSlowResponse — afterResponse hook for latency-sensitive steps.
 * Emits named counters that appear in the Artillery JSON report.
 */
function logSlowResponse(requestParams, response, context, ee, next) {
  const latency = response.timings?.phases?.firstByte ?? 0;
  if (latency > 2000) ee.emit('counter', 'perf.slow_over_2s', 1);
  if (latency > 5000) ee.emit('counter', 'perf.very_slow_over_5s', 1);
  return next();
}

/**
 * ignoreCloudflareCookies — strips __cf_bm Set-Cookie headers that
 * Artillery's tough-cookie rejects because "supabase.co" is a public suffix.
 * The underlying HTTP request still succeeds (200 OK) — this is purely
 * a tooling workaround.
 */
function ignoreCloudflareCookies(requestParams, response, context, ee, next) {
  try {
    if (response.headers) delete response.headers['set-cookie'];
  } catch (_) { /* non-critical */ }
  return next();
}

// ── Combined hooks (avoids duplicate YAML key errors) ─────────────────────────
// Artillery 2.x rejects duplicate mapping keys, so steps that need two hooks
// use these combined variants instead of repeating afterResponse.

function cacheRestaurantsAndLog(requestParams, response, context, ee, next) {
  cacheRestaurantIds(requestParams, response, context, ee, () => {});
  logSlowResponse(requestParams, response, context, ee, next);
}

function cacheMenusAndLog(requestParams, response, context, ee, next) {
  cacheMenuItemIds(requestParams, response, context, ee, () => {});
  logSlowResponse(requestParams, response, context, ee, next);
}

module.exports = {
  generateUserContext,
  extractAuthToken,
  cacheRestaurantIds,
  cacheMenuItemIds,
  cacheRestaurantsAndLog,
  cacheMenusAndLog,
  buildOrderPayload,
  logSlowResponse,
  ignoreCloudflareCookies,
};

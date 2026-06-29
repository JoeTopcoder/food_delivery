#!/usr/bin/env node
/**
 * seed-load-test-users.js
 * ────────────────────────────────────────────────────────────────────────────
 * Creates 200 Supabase auth users for Artillery load testing via the
 * Supabase Admin API (service-role key).  Much faster than the SQL approach
 * because it avoids 200 bcrypt rounds in the DB.
 *
 * USAGE:
 *   ENABLE_LOAD_TEST_SEED=true \
 *   SUPABASE_URL=https://yharweliruemjexmuuxn.supabase.co \
 *   SUPABASE_SERVICE_ROLE_KEY=<your-service-role-key> \
 *   node load_tests/seed-load-test-users.js
 *
 * To also clean up:
 *   node load_tests/seed-load-test-users.js --cleanup
 *
 * ⚠️  NEVER run against production without explicit ENABLE_LOAD_TEST_SEED=true.
 * ────────────────────────────────────────────────────────────────────────────
 */

'use strict';

const SUPABASE_URL      = process.env.SUPABASE_URL      || 'https://yharweliruemjexmuuxn.supabase.co';
const SERVICE_ROLE_KEY  = process.env.SUPABASE_SERVICE_ROLE_KEY || '';
const ENABLE_SEED       = process.env.ENABLE_LOAD_TEST_SEED === 'true';
const CLEANUP_MODE      = process.argv.includes('--cleanup');
const TOTAL_USERS       = 200;
const TEST_PASSWORD     = 'LoadTest123!Secure';
const EMAIL_DOMAIN      = '@test.mealhub.dev';
const CONCURRENCY       = 10;  // max parallel API calls

// ── Safety guard ─────────────────────────────────────────────────────────────
if (!ENABLE_SEED) {
  console.error('❌  Aborted. Set ENABLE_LOAD_TEST_SEED=true to proceed.');
  console.error('    This guard prevents accidental runs against production.');
  process.exit(1);
}

if (!SERVICE_ROLE_KEY) {
  console.error('❌  SUPABASE_SERVICE_ROLE_KEY is not set.');
  console.error('    Get it from: Supabase Dashboard → Settings → API → service_role key');
  process.exit(1);
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function email(n) {
  return `loadtest_${String(n).padStart(3, '0')}${EMAIL_DOMAIN}`;
}

async function adminRequest(method, path, body) {
  const res = await fetch(`${SUPABASE_URL}/auth/v1${path}`, {
    method,
    headers: {
      'Authorization': `Bearer ${SERVICE_ROLE_KEY}`,
      'apikey': SERVICE_ROLE_KEY,
      'Content-Type': 'application/json',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  try { return { status: res.status, data: JSON.parse(text) }; }
  catch { return { status: res.status, data: text }; }
}

async function createUser(n) {
  const { status, data } = await adminRequest('POST', '/admin/users', {
    email: email(n),
    password: TEST_PASSWORD,
    email_confirm: true,
    user_metadata: {
      name: `Load Test User ${n}`,
      role: 'customer',
      is_load_test: true,
    },
    app_metadata: {
      is_load_test: true,
    },
  });

  if (status === 201 || status === 200) return { n, ok: true };
  if (status === 422 && JSON.stringify(data).includes('already been registered')) {
    return { n, ok: true, skipped: true };  // already exists — idempotent
  }
  return { n, ok: false, status, error: data?.msg || data?.message || JSON.stringify(data) };
}

async function listLoadTestUsers() {
  // Admin users list — paginate through to find load test users
  const ids = [];
  let page  = 1;
  while (true) {
    const { data } = await adminRequest('GET', `/admin/users?page=${page}&per_page=1000`);
    if (!Array.isArray(data?.users) || data.users.length === 0) break;
    for (const u of data.users) {
      if (u.email && u.email.endsWith(EMAIL_DOMAIN)) ids.push(u.id);
    }
    if (data.users.length < 1000) break;
    page++;
  }
  return ids;
}

async function deleteUser(id) {
  const { status } = await adminRequest('DELETE', `/admin/users/${id}`);
  return status === 200 || status === 204;
}

async function runInBatches(items, batchSize, fn) {
  const results = [];
  for (let i = 0; i < items.length; i += batchSize) {
    const batch = items.slice(i, i + batchSize);
    results.push(...await Promise.all(batch.map(fn)));
  }
  return results;
}

// ── Main ──────────────────────────────────────────────────────────────────────

async function seed() {
  console.log(`\n🌱  Seeding ${TOTAL_USERS} load test users → ${EMAIL_DOMAIN}`);
  console.log(`    Password: ${TEST_PASSWORD}`);
  console.log(`    Concurrency: ${CONCURRENCY} parallel API calls\n`);

  const nums    = Array.from({ length: TOTAL_USERS }, (_, i) => i + 1);
  const results = await runInBatches(nums, CONCURRENCY, createUser);

  const created = results.filter(r => r.ok && !r.skipped).length;
  const skipped = results.filter(r => r.skipped).length;
  const failed  = results.filter(r => !r.ok);

  console.log(`✅  Created : ${created}`);
  console.log(`⏭️   Skipped : ${skipped} (already existed)`);
  console.log(`❌  Failed  : ${failed.length}`);

  if (failed.length > 0) {
    console.log('\nFailed users:');
    failed.forEach(f => console.log(`  [${f.n}] ${f.status} — ${f.error}`));
  }

  console.log('\n📋  Artillery processor.js will pick users at random from this pool.');
  console.log('    Update SEEDED_USER_COUNT in processor.js if you change TOTAL_USERS.\n');
}

async function cleanup() {
  console.log('\n🧹  Cleanup mode — deleting load test users only.');
  console.log(`    Domain filter: *${EMAIL_DOMAIN}\n`);

  const ids = await listLoadTestUsers();
  if (ids.length === 0) {
    console.log('   No load test users found. Nothing to delete.');
    return;
  }

  console.log(`   Found ${ids.length} users to delete…`);
  const results = await runInBatches(ids, CONCURRENCY, deleteUser);
  const ok      = results.filter(Boolean).length;
  console.log(`✅  Deleted ${ok} / ${ids.length} load test users.\n`);
}

(CLEANUP_MODE ? cleanup() : seed()).catch(err => {
  console.error('Fatal error:', err.message);
  process.exit(1);
});

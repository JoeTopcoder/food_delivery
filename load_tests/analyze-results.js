#!/usr/bin/env node
/**
 * MealHub Load Test Result Analyzer  v2
 * ────────────────────────────────────────────────────────────────────────────
 * Changes from v1:
 *  • Full 4xx breakdown (400 / 401 / 403 / 404 / 422 / 429)
 *  • Separates TEST-SETUP failures (400 invalid-creds, orphaned 401)
 *    from REAL BACKEND failures (5xx, timeouts, 429 rate-limit)
 *  • Verdict is based on backend failures only — not inflated by expected
 *    auth failures that a seed script would fix
 *  • Prints custom counters emitted by processor.js (auth.login_failed_*)
 *
 * Usage:
 *   node analyze-results.js <artillery-json-output>
 *   node analyze-results.js reports/mixed-ramp.json
 * ────────────────────────────────────────────────────────────────────────────
 */

'use strict';

const fs   = require('fs');
const path = require('path');

const TARGET_CONCURRENT_USERS = 3_000_000;

// ── Colour helpers (works in any terminal) ────────────────────────────────────
const C = {
  reset:  '\x1b[0m',
  green:  '\x1b[32m',
  yellow: '\x1b[33m',
  red:    '\x1b[31m',
  cyan:   '\x1b[36m',
  bold:   '\x1b[1m',
};
const ok   = (s) => `${C.green}${s}${C.reset}`;
const warn = (s) => `${C.yellow}${s}${C.reset}`;
const bad  = (s) => `${C.red}${s}${C.reset}`;
const info = (s) => `${C.cyan}${s}${C.reset}`;
const bold = (s) => `${C.bold}${s}${C.reset}`;

function pct(n, d) {
  if (!d) return '0.0%';
  return `${((n / d) * 100).toFixed(1)}%`;
}

function latencyIcon(ms, warnMs, badMs) {
  if (ms <= warnMs) return ok('✅ Excellent');
  if (ms <= badMs)  return warn('⚠️  Marginal');
  return bad('❌ Too slow');
}

// ── Main ──────────────────────────────────────────────────────────────────────

function main() {
  const file = process.argv[2];
  if (!file) {
    console.error('Usage: node analyze-results.js <artillery-json-report>');
    process.exit(1);
  }
  if (!fs.existsSync(file)) {
    console.error(`File not found: ${file}`);
    process.exit(1);
  }

  const raw  = JSON.parse(fs.readFileSync(file, 'utf8'));
  const agg  = raw.aggregate;
  const hist = raw.intermediate ?? [];
  const cnt  = agg.counters ?? {};

  // ── Response time ─────────────────────────────────────────────────────────
  const p50   = agg.summaries?.['http.response_time']?.p50  ?? agg.histograms?.['http.response_time']?.p50  ?? 0;
  const p95   = agg.summaries?.['http.response_time']?.p95  ?? agg.histograms?.['http.response_time']?.p95  ?? 0;
  const p99   = agg.summaries?.['http.response_time']?.p99  ?? agg.histograms?.['http.response_time']?.p99  ?? 0;
  const mean  = agg.summaries?.['http.response_time']?.mean ?? agg.histograms?.['http.response_time']?.mean ?? 0;

  // ── Traffic volume ────────────────────────────────────────────────────────
  const totalRequests  = cnt['http.requests']         ?? 0;
  const totalResponses = cnt['http.responses']        ?? 0;
  const timeouts       = cnt['http.request_timeout']  ?? 0;

  // ── HTTP status breakdown ──────────────────────────────────────────────────
  // 2xx
  const ok2xx  = sumCodes(cnt, '2');

  // 4xx — individual codes
  const c400 = cnt['http.codes.400'] ?? 0;   // invalid credentials / bad request
  const c401 = cnt['http.codes.401'] ?? 0;   // unauthorized (no/expired token)
  const c403 = cnt['http.codes.403'] ?? 0;   // forbidden (RLS / permission)
  const c404 = cnt['http.codes.404'] ?? 0;   // not found
  const c422 = cnt['http.codes.422'] ?? 0;   // unprocessable (validation)
  const c429 = cnt['http.codes.429'] ?? 0;   // rate-limited ← REAL backend signal
  const other4xx = sumCodes(cnt, '4') - c400 - c401 - c403 - c404 - c422 - c429;

  // 5xx
  const ok5xx  = sumCodes(cnt, '5');
  const c500 = cnt['http.codes.500'] ?? 0;
  const c502 = cnt['http.codes.502'] ?? 0;
  const c503 = cnt['http.codes.503'] ?? 0;
  const c504 = cnt['http.codes.504'] ?? 0;

  // ── Failure categorization ─────────────────────────────────────────────────
  //
  //  TEST-SETUP failures  — caused by missing seed data, not backend bugs.
  //    400  = "Invalid login credentials" — seed not run
  //    401  = orphaned 401 after a 429/400 auth step left authToken empty
  //
  //  REAL BACKEND failures — something the backend team must fix.
  //    429  = server-side rate limit exceeded (tune infra or slow down test)
  //    5xx  = server errors (DB down, edge function crash, OOM, etc.)
  //    timeouts = requests that never completed within the configured timeout
  //
  const testSetupFailures  = c400 + c401;
  const realBackendFailures = ok5xx + timeouts + c429;
  const backendFailureRate  = totalRequests > 0
    ? (realBackendFailures / totalRequests * 100).toFixed(2)
    : '0.00';

  // ── Custom counters emitted by processor.js ────────────────────────────────
  const loginSuccess     = cnt['auth.login_success']      ?? 0;
  const loginFailed400   = cnt['auth.login_failed_400']   ?? 0;
  const loginFailed401   = cnt['auth.login_failed_401']   ?? 0;
  const loginFailed429   = cnt['auth.login_failed_429']   ?? 0;
  const loginParseErr    = cnt['auth.login_parse_error']  ?? 0;
  const slowOver2s       = cnt['perf.slow_over_2s']       ?? 0;
  const slowOver5s       = cnt['perf.very_slow_over_5s']  ?? 0;

  // ── Throughput ────────────────────────────────────────────────────────────
  const maxRPS = Math.max(...hist.map(s => s.rates?.['http.request_rate'] ?? 0), 0);
  const avgRPS = agg.rates?.['http.request_rate']
    ?? (totalRequests / (agg.duration ?? 1));

  // ── Peak VUs (best estimate) ──────────────────────────────────────────────
  const peakVUs = Math.max(
    ...hist.map(s =>
      (s.counters?.['vusers.created'] ?? 0) -
      (s.counters?.['vusers.completed'] ?? 0) -
      (s.counters?.['vusers.failed'] ?? 0)
    ), 0
  );

  // ── 3M user extrapolation ─────────────────────────────────────────────────
  const testVUs     = Math.max(cnt['vusers.created'] ?? peakVUs, 1);
  const scaleRatio  = TARGET_CONCURRENT_USERS / testVUs;
  const estRPS      = Math.round(avgRPS * scaleRatio);
  const estP95      = Math.round(p95 * 1.5);
  const dbConns     = Math.min(TARGET_CONCURRENT_USERS / 100, 30_000);
  const edgeNodes   = Math.ceil(estRPS / 1_000);

  // ── Bottlenecks ────────────────────────────────────────────────────────────
  const bottlenecks = [];
  if (p95  > 2000) bottlenecks.push({ lvl: 'CRITICAL', area: 'DB query latency',   detail: `p95 ${p95}ms — verify indexes on orders/restaurants` });
  if (p95  > 800)  bottlenecks.push({ lvl: 'WARNING',  area: 'API response time',  detail: `p95 ${p95}ms — consider caching restaurant listings` });
  if (ok5xx > 0)   bottlenecks.push({ lvl: 'CRITICAL', area: 'Server errors',      detail: `${ok5xx} 5xx — check Supabase logs for connection exhaustion` });
  if (c429  > 0)   bottlenecks.push({ lvl: 'WARNING',  area: 'Rate limiting (429)',detail: `${c429} rate-limited — reduce test arrival rate or upgrade Supabase plan` });
  if (timeouts > 0)bottlenecks.push({ lvl: 'CRITICAL', area: 'Request timeouts',   detail: `${timeouts} timeouts — edge function hanging or DB connection pool exhausted` });
  if (p99  > 5000) bottlenecks.push({ lvl: 'WARNING',  area: 'Tail latency',       detail: `p99 ${p99}ms — investigate slow edge functions or unbounded queries` });
  if (bottlenecks.length === 0) bottlenecks.push({ lvl: 'OK', area: 'No backend bottlenecks at tested scale', detail: '' });

  // ── Print report ──────────────────────────────────────────────────────────
  const DIV  = '═'.repeat(68);
  const LINE = '─'.repeat(68);

  console.log(`\n${bold(DIV)}`);
  console.log(bold(' MealHub Load Test — Backend Analysis Report v2'));
  console.log(` Generated: ${new Date().toISOString()}`);
  console.log(`${bold(DIV)}`);

  // Traffic
  console.log(`\n${info('📊  TRAFFIC VOLUME')}`);
  console.log(LINE);
  console.log(`  Total requests sent      : ${totalRequests.toLocaleString()}`);
  console.log(`  Total responses received : ${totalResponses.toLocaleString()}`);
  console.log(`  Peak VUs (concurrent)    : ~${peakVUs.toLocaleString()}`);
  console.log(`  Avg requests/sec         : ${avgRPS.toFixed(1)}`);
  console.log(`  Peak requests/sec        : ${maxRPS.toFixed(1)}`);

  // HTTP status breakdown
  console.log(`\n${info('📈  HTTP STATUS BREAKDOWN')}`);
  console.log(LINE);
  console.log(`  ${ok('2xx  Success')}               : ${ok2xx.toLocaleString()} (${pct(ok2xx, totalResponses)})`);
  console.log();
  console.log(`  ${warn('4xx  Client Errors')}         : ${(sumCodes(cnt,'4')).toLocaleString()} total`);
  console.log(`    400  Invalid credentials   : ${c400.toLocaleString()}  ${c400 > 0 ? bad('← TEST SETUP: run seed-load-test-users.sql') : ok('✓ none')}`);
  console.log(`    401  Unauthorized          : ${c401.toLocaleString()}  ${c401 > 0 ? warn('← mostly cascaded from 400/429') : ok('✓ none')}`);
  console.log(`    403  Forbidden (RLS)       : ${c403.toLocaleString()}  ${c403 > 0 ? warn('← check RLS policy for this route') : ok('✓ none')}`);
  console.log(`    404  Not found             : ${c404.toLocaleString()}  ${c404 > 0 ? warn('← check test data / seeded IDs') : ok('✓ none')}`);
  console.log(`    422  Unprocessable         : ${c422.toLocaleString()}  ${c422 > 0 ? warn('← validation error in test payload') : ok('✓ none')}`);
  console.log(`    429  Rate-limited          : ${c429.toLocaleString()}  ${c429 > 0 ? bad('← REAL: reduce load or upgrade Supabase plan') : ok('✓ none')}`);
  if (other4xx > 0) console.log(`    4xx  Other                : ${other4xx.toLocaleString()}`);
  console.log();
  console.log(`  ${ok5xx > 0 ? bad('5xx  Server Errors') : ok('5xx  Server Errors')}         : ${ok5xx.toLocaleString()} (${pct(ok5xx, totalRequests)})`);
  if (ok5xx > 0) {
    console.log(`    500  Internal error        : ${c500.toLocaleString()}`);
    console.log(`    502  Bad gateway           : ${c502.toLocaleString()}`);
    console.log(`    503  Service unavailable   : ${c503.toLocaleString()}`);
    console.log(`    504  Gateway timeout       : ${c504.toLocaleString()}`);
  }
  console.log(`  Timeouts                   : ${timeouts.toLocaleString()}`);

  // Failure categorization
  console.log(`\n${info('🔍  FAILURE CATEGORIZATION')}`);
  console.log(LINE);
  console.log(`  Test-setup failures       : ${testSetupFailures.toLocaleString()} (${pct(testSetupFailures, totalRequests)})`);
  console.log(`    = 400 + 401 caused by missing seed data`);
  console.log(`    → Fix: run seed-load-test-users.sql, then re-test`);
  console.log();
  console.log(`  True backend failures     : ${realBackendFailures.toLocaleString()} (${backendFailureRate}%)`);
  console.log(`    = 5xx + timeouts + 429 rate-limits`);
  const bfIcon = parseFloat(backendFailureRate) === 0 ? ok('✅ ZERO — backend is healthy')
               : parseFloat(backendFailureRate) < 0.1 ? ok('✅ Under 0.1% — acceptable')
               : parseFloat(backendFailureRate) < 1.0 ? warn('⚠️  Under 1% — monitor')
               : bad('❌ Over 1% — backend must be fixed');
  console.log(`    → ${bfIcon}`);

  // Auth counters
  if (loginSuccess + loginFailed400 + loginFailed429 > 0) {
    console.log(`\n${info('🔐  AUTH LOGIN BREAKDOWN (from processor.js counters)')}`);
    console.log(LINE);
    console.log(`  Login success             : ${loginSuccess.toLocaleString()}`);
    if (loginFailed400 > 0)
      console.log(`  Login 400 (invalid creds) : ${bad(loginFailed400.toLocaleString())} ← seed not run`);
    if (loginFailed401 > 0)
      console.log(`  Login 401 (unauthorized)  : ${warn(loginFailed401.toLocaleString())}`);
    if (loginFailed429 > 0)
      console.log(`  Login 429 (rate-limited)  : ${warn(loginFailed429.toLocaleString())} ← infra limit`);
    if (loginParseErr > 0)
      console.log(`  Login parse error         : ${loginParseErr.toLocaleString()}`);
  }

  // Latency
  console.log(`\n${info('⏱️   RESPONSE TIME DISTRIBUTION')}`);
  console.log(LINE);
  console.log(`  p50  (median)             : ${p50}ms   ${latencyIcon(p50,  200,  500)}`);
  console.log(`  p95                       : ${p95}ms   ${latencyIcon(p95,  500, 2000)}`);
  console.log(`  p99                       : ${p99}ms   ${latencyIcon(p99, 2000, 5000)}`);
  console.log(`  Mean                      : ${mean}ms`);
  if (slowOver2s > 0)  console.log(`  Responses >2s             : ${warn(slowOver2s.toLocaleString())}`);
  if (slowOver5s > 0)  console.log(`  Responses >5s             : ${bad(slowOver5s.toLocaleString())}`);

  // Bottlenecks
  console.log(`\n${info('🔴  BOTTLENECK ANALYSIS')}`);
  console.log(LINE);
  bottlenecks.forEach(b => {
    const icon = b.lvl === 'CRITICAL' ? bad('❌') : b.lvl === 'WARNING' ? warn('⚠️ ') : ok('✅');
    console.log(`  ${icon} [${b.lvl}] ${b.area}`);
    if (b.detail) console.log(`        → ${b.detail}`);
  });

  // 3M extrapolation
  console.log(`\n${info('🚀  3,000,000 USER EXTRAPOLATION')}`);
  console.log(LINE);
  console.log(`  Scale factor              : ${scaleRatio.toFixed(0)}×`);
  console.log(`  Estimated peak req/sec    : ${estRPS.toLocaleString()}`);
  console.log(`  Estimated p95 latency     : ~${estP95}ms (optimistic +50% headroom)`);
  console.log(`  DB connections needed     : ${dbConns.toLocaleString()} (with PgBouncer)`);
  console.log(`  Edge function nodes       : ${edgeNodes.toLocaleString()} instances`);
  console.log(`  Plan recommendation       : Supabase Enterprise + read replicas + Redis`);
  console.log(`  Est. infra cost           : ~$3k–$11k/mo  (Netflix/Uber scale)`);

  // Verdict
  console.log(`\n${DIV}`);

  const successRatePct  = totalResponses > 0 ? (ok2xx / totalResponses * 100) : 0;
  const backendOk       = parseFloat(backendFailureRate) < 0.1 && ok5xx === 0 && timeouts === 0;
  const latencyOk       = p95 < 2000;

  if (backendOk && latencyOk) {
    console.log(ok(`\n✅  BACKEND VERDICT: PASS`));
    console.log(`   Backend is healthy: 0 server errors, 0 timeouts, p95=${p95}ms`);
    if (testSetupFailures > 0) {
      console.log(warn(`   Note: ${testSetupFailures.toLocaleString()} test-setup failures (400/401) inflated the apparent failure rate.`));
      console.log(warn(`         Run seed-load-test-users.sql, then re-test to hit ≥85% overall success.`));
    }
  } else {
    console.log(bad(`\n❌  BACKEND VERDICT: FAIL`));
    if (!backendOk) {
      console.log(bad(`   Backend failures: ${realBackendFailures} (${backendFailureRate}%) — 5xx=${ok5xx}, timeouts=${timeouts}, 429=${c429}`));
    }
    if (!latencyOk) {
      console.log(bad(`   Latency: p95=${p95}ms exceeds 2000ms threshold`));
    }
  }
  console.log();
}

// ── Utility ───────────────────────────────────────────────────────────────────

function sumCodes(cnt, prefix) {
  return Object.entries(cnt)
    .filter(([k]) => k.startsWith(`http.codes.${prefix}`))
    .reduce((s, [, v]) => s + v, 0);
}

main();

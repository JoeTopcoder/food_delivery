# Private Telephone Fallback (alongside Agora)

Bridges a driver and customer over their real phone numbers when the Agora
in-app call can't connect/recover — **without ever exposing the customer's
number to the driver**. Agora remains primary and is unchanged.

## Status
- **Feature flag `call_fallback_enabled` = OFF by default.** Agora is unaffected.
- **Provider = `mock` by default** (no real/paid calls) until Twilio is provisioned.
- Backend + edge + cron + Flutter + admin log: implemented & tested (mock).

## How it works
1. Driver app calls via Agora as today. Three app-level triggers (configurable):
   - accepted call not connected in **15s** → auto fallback (`connect_timeout`)
   - established call drops, no recovery in **10s** → auto fallback (`reconnect_failed`)
   - invite unanswered **30s** → driver sees a **“Connect by phone”** button (`no_answer_manual`)
   Declines / cancels / intentional hangups never auto-trigger. If Agora connects
   first, a pending fallback is cancelled (atomic race handling). The Agora attempt
   is torn down before switching so no stale invite can be answered.
2. App → edge fn **`call-fallback-request`** with only `{order_id, call_session_id, reason}`.
   Never a phone number (the edge fn rejects any phone-like field).
3. Backend authorizes (driver assigned to the order, order eligible incl. a 15-min
   post-delivery grace, feature on, attempt/cooldown limits), atomically creates one
   `call_fallback_sessions` row (unique index dedupes duplicates), resolves both
   phones **server-side**, and dials the **driver** first via the provider.
4. Driver answers → TwiML: *“HotBite is connecting your customer call. Press 1 to
   continue.”* Only on **press 1** is the customer dialed (prevents voicemail
   auto-dial), with the **HotBite caller ID** on both legs. Bridged on answer.
5. `cf_reconcile_deadlines()` (pg_cron, every minute) is the durable worker that
   expires abandoned/stuck sessions and enforces the 5-min max bridge duration —
   survives edge-function/app restarts.

## Privacy & security guarantees
- Phone numbers are **never** stored in the driver-readable row, returned to the
  driver, pushed, or logged. Resolved at dial time by `cf_resolve_phones`
  (service-role only), which **re-checks authorization** immediately before dialing.
- Drivers read only a sanitized status via `get_call_fallback_status` (no phones,
  no provider SIDs). Base table RLS = admin/service only.
- Provider SIDs + sanitized failure codes are admin/service-only.
- Twilio webhooks are **signature-verified** (`X-Twilio-Signature`).
- Limits (admin-configurable in `app_config`): max 2 attempts/order/driver, 60s
  cooldown, 5-min max duration, 15-min post-delivery grace, allowed countries
  (`JM,US,CA`). No recording. No auto-redial loops.

## Admin
- `app_config` keys: `call_fallback_enabled`, `call_fallback_connect_timeout_s`,
  `call_fallback_reconnect_grace_s`, `call_fallback_no_answer_s`,
  `call_fallback_max_attempts`, `call_fallback_cooldown_s`,
  `call_fallback_max_duration_s`, `call_fallback_grace_minutes`,
  `call_fallback_service_countries`, `call_fallback_provider`.
- Call log: Admin → **Phone Fallback** (`/admin-call-fallback-log`) → order, driver,
  reason, outcome, duration, time, sanitized error, cost. No phone numbers.

## Going live with Twilio
1. Buy a Twilio number (or provision/approve a caller ID). For **Jamaica**, confirm
   Twilio Geographic Permissions allow dialing `+1876`/`+1658`, and only claim a JM
   local caller ID if Twilio has provisioned and approved one.
2. Set secrets (see `functions/call-fallback-request/.env.example`):
   `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `TWILIO_CALLER_ID`,
   `CALL_FALLBACK_PROVIDER=twilio`.
3. Ensure driver + customer `users.phone` (and `drivers.phone_number`) are stored
   in **E.164**.
4. Flip `call_fallback_enabled=true` in Admin.
5. Twilio voice webhook + status callback are set automatically by the request fn
   to `…/functions/v1/call-fallback-voice` (verify_jwt=false, signature-checked).

## Files
- Migrations: `20261003010000_call_fallback.sql` (table/flag/RLS),
  `20261003020000_call_fallback_rpcs.sql` (authz/transition/reconcile/admin-log),
  `20261003030000_call_fallback_cron.sql` (durable worker).
- Edge: `functions/call-fallback-request`, `functions/call-fallback-voice`,
  `functions/_shared/telephony.ts` (Twilio + mock, isolated).
- Flutter: `lib/services/call/call_fallback_service.dart`,
  hooks in `lib/screens/shared/call_screen.dart`,
  `callFallbackEnabledProvider` in `lib/providers/feature_providers.dart`,
  admin `lib/screens/admin/admin_call_fallback_log_screen.dart`.

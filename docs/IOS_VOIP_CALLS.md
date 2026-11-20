# iOS VoIP Calling (PushKit → CallKit) — Setup & Finish Guide

Agora carries the call **audio**; this pipeline is the **signaling** that wakes a
backgrounded/locked iPhone and makes it **ring** via CallKit. Everything in the
codebase is already wired — the only remaining work is Apple credentials + a
macOS/Xcode build. Bundle id: **`com.sevendash.app`** → VoIP topic
**`com.sevendash.app.voip`**.

---

## ⚠️ PREREQUISITE — iOS push is NOT configured at all (do this FIRST)

Diagnostic run on the live DB: **0 of 4 iOS users have any push token**, while
Android is 14/14. Root cause: **`ios/Runner/GoogleService-Info.plist` is missing**
(Android's `google-services.json` is present). Without it, `FirebaseApp.configure()`
on iOS can't start Firebase Messaging, so **no FCM token is ever issued** → iOS
gets **no push at all** — not calls, not the daily admin broadcast. The app code
is correct (it awaits the APNs token and logs the cause); this is pure config.

Until the steps below are done, **nothing in the VoIP sections further down will
work**, because even basic FCM doesn't reach iOS.

### P1. Register the iOS app in Firebase + add the config file
- Firebase Console → your project → **Add app → iOS**, bundle id
  **`com.sevendash.app`** (skip if the iOS app already exists).
- **Download `GoogleService-Info.plist`**, put it at
  **`ios/Runner/GoogleService-Info.plist`**, and add it to the **Runner** target
  in Xcode (check "Copy items if needed" + Runner target membership) so it's
  bundled. (Do NOT fabricate this file — it must come from the console.)

### P2. Upload the APNs Auth Key to Firebase (lets Firebase mint iOS FCM tokens)
- Firebase Console → **Project Settings → Cloud Messaging → Apple app
  configuration → APNs Authentication Key → Upload**.
- Use the **same `.p8`** you create for VoIP below, plus its **Key ID** and your
  **Team ID**. (One APNs key serves both FCM alerts and VoIP pushes.)

### P3. Xcode capabilities + APNs environment
- Runner target → **Signing & Capabilities → + Push Notifications**.
- `ios/Runner/Runner.entitlements` has `aps-environment` = **`production`**.
  - TestFlight / App Store build → `production` ✅ (leave as-is).
  - Direct Xcode **debug/dev** build to a device → must be **`development`**, or
    the device won't get an APNs token. (Switch it for local testing, switch back
    for release — or let Xcode's "Automatically manage signing" handle it.)

### P4. Verify FCM registration before touching VoIP
```bash
cd ios && pod install && cd ..
flutter run        # on a REAL iPhone; grant the notification prompt
```
```sql
SELECT count(*) FROM users WHERE device_platform='ios' AND fcm_token IS NOT NULL;
```
This must climb above **0**. Once it does, iOS receives the **daily admin
broadcast** immediately. Only then proceed to the VoIP steps for call ringing.

> If `fcm_token` stays null, read the Xcode console — the app logs
> `APNs token unavailable — iOS push cannot register (check APNs key in Firebase
> + Push capability provisioning)`, which points at P1–P3.

---

## What's already done (in this repo)
- `ios/Runner/Info.plist` — `UIBackgroundModes` includes **`voip`** + `audio`.
- `ios/Runner/AppDelegate.swift` — registers **PushKit**, forwards the VoIP token
  to `flutter_callkit_incoming`, and on an incoming VoIP push calls
  `showCallkitIncoming(..., fromPushKit: true)` so iOS rings.
- Dart (`notification_service.dart`) — saves the PushKit token to
  `users.voip_token`, and the existing `FlutterCallkitIncoming.onEvent` listener
  already handles **Accept** (→ opens `/call`, which joins the Agora channel) and
  **Decline/End**.
- DB — `users.voip_token` column (migration `20261120020000`).
- Backend — `send-call-notification` now sends an **APNs VoIP push** when the
  recipient has a `voip_token` and the Apple key is configured; otherwise it
  falls back to the FCM/alert path. `initiateCall` already calls this function,
  so **no call-flow changes are needed**.

## What YOU must do (needs a Mac + Apple Developer account)

### 1. Create an Apple APNs Auth Key (works for VoIP)
Apple Developer → **Certificates, Identifiers & Profiles → Keys → +**
- Enable **Apple Push Notifications service (APNs)**.
- Download the **`AuthKey_XXXXXXXXXX.p8`** (you can only download once).
- Note the **Key ID** (10 chars) and your **Team ID** (top-right of the portal).

> One APNs auth key handles both normal and VoIP pushes. You do **not** need a
> separate legacy VoIP certificate.

### 2. Set the Supabase secrets (from your machine, project linked)
```bash
supabase secrets set APNS_KEY_ID=XXXXXXXXXX
supabase secrets set APNS_TEAM_ID=YYYYYYYYYY
supabase secrets set APNS_BUNDLE_ID=com.sevendash.app
supabase secrets set APNS_PRODUCTION=true   # true for TestFlight/App Store; false for a dev/debug build
# Paste the whole .p8 (including the BEGIN/END lines):
supabase secrets set APNS_VOIP_KEY="$(cat AuthKey_XXXXXXXXXX.p8)"
# Then redeploy so the function picks up the secrets:
supabase functions deploy send-call-notification --no-verify-jwt
```
`APNS_PRODUCTION=true` → `api.push.apple.com`; `false` → `api.sandbox.push.apple.com`.
A device build signed with a **development** profile uses the sandbox; TestFlight/
App Store use production. Mismatch = `BadDeviceToken`.

### 3. Xcode capabilities (on the Mac)
Open `ios/Runner.xcworkspace` → Runner target → **Signing & Capabilities**:
- **+ Capability → Push Notifications**.
- **+ Capability → Background Modes** → tick **Voice over IP** (and **Audio**).
  (Info.plist already lists them; this makes sure the entitlement/UI matches.)

### 4. Build
```bash
cd ios && pod install && cd ..
flutter build ios          # or open Runner.xcworkspace and Run on a real device
```
VoIP/CallKit **does not work on the iOS Simulator** — use a real iPhone.

## Verify it works
1. Launch on the iPhone, sign in, grant notification permission.
2. Confirm the token saved:
   ```sql
   SELECT id, name, voip_token IS NOT NULL AS has_voip FROM users WHERE id = '<that user>';
   ```
   `has_voip` must be `true`. (The token is issued a moment after launch.)
3. Background the app / lock the phone. From admin (or a driver), place an in-app
   call to that user. The iPhone should **ring with the CallKit screen**.
4. Accept → the app opens the call screen and joins the Agora channel.

## Troubleshooting
- **`has_voip` stays null** → the PushKit token event didn't fire. Check the
  Push Notifications capability + that it's a real device (not Simulator).
- **`BadDeviceToken` / `403` in function logs** → `APNS_PRODUCTION` doesn't match
  the build's provisioning (dev build ⇒ `false`, TestFlight/App Store ⇒ `true`).
- **`TopicDisallowed`** → `APNS_BUNDLE_ID` wrong; topic must be `<bundle>.voip`.
- **No ring but a banner shows** → VoIP key not set yet, so it fell back to the
  FCM alert path. Finish step 2.
- **Rings but no audio on answer** → Agora side (token/channel), unrelated to
  PushKit; check the `/call` join and the `audio` background mode.

## Note on the plugin API
`AppDelegate.swift` uses `flutter_callkit_incoming`'s
`SwiftFlutterCallkitIncomingPlugin` / `Data(...)` / `setDevicePushTokenVoIP` /
`showCallkitIncoming(_:fromPushKit:)`. These match 3.0.x. If Xcode flags a name,
check the symbol against your installed plugin version (open the pod in Xcode) —
across versions the plugin class is occasionally `FlutterCallkitIncomingPlugin`
and `Data`'s parameters shift slightly. Fixing is a one-line rename Xcode points at.

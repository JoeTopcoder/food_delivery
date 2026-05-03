# AAB Analysis Report - 7DASH v1.0.1+4

## Build Information
- **Build Date**: April 30, 2026
- **Version**: 1.0.1
- **Version Code**: 4
- **Build Type**: Release (Signed)
- **Compiler SDK**: 36 (Android 16)
- **Min SDK**: 24 (Android 7.0)
- **Target SDK**: 36 (Android 16)

## Package & Branding
- **Package Name**: `sevendash.app`
- **App Display Name**: `7DASH`
- **Main Activity**: `sevendash.app.MainActivity`
- **Screen Orientation**: Portrait-only (android:screenOrientation="1")
- **Launch Theme**: `@style/LaunchTheme`

## File Sizes
- **AAB Bundle Size**: 177.2 MB
- **Universal APKS Size**: 278.7 MB
- **Estimated Download Size**: ~156.9 MB (149.5 MB)
- **Size Reduction**: Yes (Build included icon tree-shaking optimization)

## Compilation & Optimization
- **Icon Tree-Shaking**: 96.4% reduction on MaterialIcons-Regular.otf
  - Original: 1.6 MB → Optimized: 60 KB
- **MinifyEnabled**: true (ProGuard/R8 enabled)
- **ShrinkResources**: true (Unused resources removed)
- **ProGuard Rules**: Applied (proguard-rules.pro)

## Permissions Summary
✅ **Verified Clean Permissions**:
- INTERNET (required for API calls)
- ACCESS_FINE_LOCATION (GPS tracking for delivery)
- ACCESS_COARSE_LOCATION (alternative location)
- FOREGROUND_SERVICE (background delivery tracking)
- POST_NOTIFICATIONS (delivery notifications)
- READ_MEDIA_IMAGES (photo uploads)
- RECORD_AUDIO (call recording in driver calls)
- USE_FULL_SCREEN_INTENT (incoming calls)
- WAKE_LOCK (keep screen on during delivery)
- VIBRATE (haptic feedback)
- RECEIVE_BOOT_COMPLETED (auto-start on device reboot)
- MODIFY_AUDIO_SETTINGS (audio routing)
- BLUETOOTH (device connectivity)
- BLUETOOTH_CONNECT (device pairing)
- DISABLE_KEYGUARD (lock screen control)
- ACCESS_NOTIFICATION_POLICY (notification handling)
- MANAGE_OWN_CALLS (VoIP integration)
- FOREGROUND_SERVICE_PHONE_CALL (call service)
- READ_PHONE_STATE (call state detection)
- CAMERA (video/photo capture)
- ACCESS_WIFI_STATE (network detection)
- ACCESS_NETWORK_STATE (connectivity checks)
- RECEIVE (Firebase Cloud Messaging)
- FOREGROUND_SERVICE_MEDIA_PROJECTION (media projection)

## Configuration & Querying
**Intent Queries** (Android 11+ compliance):
- PROCESS_TEXT (text processing apps)
- Maps (google.navigation, geo schemes)
- Chrome (HTTPS browsing)
- Google Maps (navigation)

**Custom Permissions**:
- `sevendash.app.PERMISSION_CALL` (call permission for flutter_callkit)
- `sevendash.app.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION` (export protection)

## Components
**Activities**:
- MainActivity (LAUNCHER, main entry point)
- CallkitIncomingActivity (incoming call UI)
- TransparentActivity (call transparency overlay)

**Services**:
- CallkitNotificationService (call notifications, foreground type: 0x04)
- CallkitConnectionService (telecom integration)

**Receivers**:
- CallkitIncomingBroadcastReceiver (call events)

**OAuth Integration**:
- Callback Scheme: `sevendash.app://login-callback`
- Handler: Intent filter for auth redirection

## Firebase Configuration
- **Project**: fooddelivery-bebe2
- **Default Notification Channel**: food_driver_notifications_v3
- **Default Sound**: @raw/order_alert
- **Messaging Enabled**: Yes

## Hardware Requirements
- **OpenGL ES**: 2.0 (minimum required)
- **Extract Native Libs**: false (embedded in APK)
- **Enable Back Invoked Callback**: true (gesture navigation support)

## Play Store Readiness Checklist
✅ Package ID correctly set to sevendash.app
✅ App branding updated to 7DASH
✅ Version code/name properly configured (1.0.1+4)
✅ Permissions audited and justified
✅ Orientation locked to portrait (prevents GPU allocation errors)
✅ Icons generated for all platforms (mdpi-xxxhdpi, iOS, web)
✅ ProGuard minification enabled
✅ Resource shrinking enabled
✅ Signing configuration present
✅ Min SDK = 24 (supports Android 7.0+)
✅ Target SDK = 36 (compliant with Play Store requirements)
✅ App display name = 7DASH
✅ Bundle structure valid

## Next Steps
1. **Before Upload**:
   - Add release keystore SHA-1 and SHA-256 fingerprints to Firebase Console
   - Re-download google-services.json if SHA keys are added
   - Prepare release notes mentioning branding update (MealHub → 7DASH)

2. **Upload Process**:
   - Upload AAB to Play Console internal testing track
   - Verify APK generation for target devices (Android 7.0+)
   - Move to closed beta for testing if successful

3. **Post-Upload**:
   - Monitor crash reports and ANR logs
   - Verify notification delivery through Firebase
   - Test Google Sign-In with release certificates in Firebase

## Build Artifacts
- **AAB**: `build/app/outputs/bundle/release/app-release.aab` (177.2 MB)
- **APKS** (generated): `app-release.apks` (278.7 MB)
- **Signing**: Release keystore from `android/key.properties`

---
Generated: April 30, 2026 | Build Code: 4 | Version: 1.0.1

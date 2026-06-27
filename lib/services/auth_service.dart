import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';
import '../utils/app_logger.dart';

class AuthService {
  final SupabaseClient _supabaseClient;

  AuthService(this._supabaseClient);

  // Sign up with email and password
  Future<AuthResponse> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    try {
      AppLogger.info('Signing up user: $email with role: $role');

      final response = await _supabaseClient.auth.signUp(
        email: email,
        password: password,
        data: {'name': name, 'role': role},
      );

      if (response.user != null) {
        // Create user profile in database
        await _createUserProfile(
          userId: response.user!.id,
          email: email,
          name: name,
          role: role,
        );
        AppLogger.info('User signed up successfully: $email');
      }

      return response;
    } catch (e) {
      AppLogger.error('Sign up error: $e');
      rethrow;
    }
  }

  // Sign in with email and password
  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    try {
      AppLogger.info('Signing in user: $email');

      final response = await _supabaseClient.auth.signInWithPassword(
        email: email,
        password: password,
      );

      AppLogger.info('User signed in successfully: $email');
      return response;
    } catch (e) {
      AppLogger.error('Sign in error: $e');
      rethrow;
    }
  }

  // Sign out
  Future<void> signOut() async {
    try {
      AppLogger.info('Signing out user');
      await _supabaseClient.auth.signOut();
      AppLogger.info('User signed out successfully');
    } catch (e) {
      AppLogger.error('Sign out error: $e');
      rethrow;
    }
  }

  // Delete account — removes all user data then the auth record
  Future<void> deleteAccount() async {
    final user = _supabaseClient.auth.currentUser;
    if (user == null) throw Exception('No authenticated user');
    final userId = user.id;
    AppLogger.info('Deleting account for user: $userId');
    try {
      // Try SECURITY DEFINER RPC that deletes auth.users (cascades to data).
      await _supabaseClient.rpc('delete_my_account');
      AppLogger.info('Account deleted via RPC');
    } catch (rpcError) {
      AppLogger.error('RPC delete_my_account failed ($rpcError) — falling back to data deletion');
      // Fallback: delete user profile row (cascades to related rows via FK).
      // The auth.users record stays but the profile is gone.
      try {
        await _supabaseClient
            .from(AppConstants.tableUsers)
            .delete()
            .eq('id', userId);
        AppLogger.info('User profile row deleted');
      } catch (e) {
        AppLogger.error('Error deleting user profile: $e');
        rethrow;
      }
    }
    // Always sign out after deletion.
    try {
      await _supabaseClient.auth.signOut();
    } catch (_) {}
  }

  // Reset password
  Future<void> resetPassword(String email) async {
    try {
      AppLogger.info('Requesting password reset for: $email');
      await _supabaseClient.auth.resetPasswordForEmail(email);
      AppLogger.info('Password reset email sent');
    } catch (e) {
      AppLogger.error('Password reset error: $e');
      rethrow;
    }
  }

  // Update password
  Future<void> updatePassword(String newPassword) async {
    try {
      AppLogger.info('Updating password');
      await _supabaseClient.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      AppLogger.info('Password updated successfully');
    } catch (e) {
      AppLogger.error('Update password error: $e');
      rethrow;
    }
  }

  // Get current user
  User? getCurrentUser() {
    return _supabaseClient.auth.currentUser;
  }

  // Get current user session
  Session? getCurrentSession() {
    return _supabaseClient.auth.currentSession;
  }

  // Check if user is authenticated
  bool isAuthenticated() {
    return _supabaseClient.auth.currentUser != null;
  }

  // Get authentication state stream
  Stream<AuthState> onAuthStateChanged() {
    return _supabaseClient.auth.onAuthStateChange;
  }

  // Sign in with Google (native SDK → Supabase signInWithIdToken)
  Future<AuthResponse> signInWithGoogle() async {
    // This MUST be the Web Application OAuth client ID (not the Android or iOS one).
    // Android/iOS client IDs are only for native platform auth; the web client ID
    // is what Supabase uses to verify the id_token.
    const webClientId =
        '379314267431-qg34f9rs5ms8bkpq298o1cn7prnqv7eu.apps.googleusercontent.com';

    AppLogger.info('[Google] sign-in started — platform: $defaultTargetPlatform');

    GoogleSignIn? googleSignIn;
    try {
      googleSignIn = GoogleSignIn(serverClientId: webClientId);

      // Silently clear any stale cached account so the account picker always shows.
      try {
        await googleSignIn.signOut();
      } catch (_) {}

      AppLogger.info('[Google] presenting account picker');
      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        // User dismissed the picker — not a crash, not an error.
        AppLogger.info('[Google] sign-in cancelled by user');
        throw Exception('Google sign-in was cancelled');
      }

      AppLogger.info('[Google] account selected: ${googleUser.email}, fetching tokens');
      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        AppLogger.error(
          '[Google] idToken is null — check that the iOS/Android OAuth client is '
          'configured in Google Cloud Console and GoogleService-Info.plist is present.',
        );
        throw Exception(
          'Google did not return an ID token. '
          'Ensure GoogleService-Info.plist is included in the Xcode project '
          'and the iOS OAuth client ID is configured in Google Cloud Console.',
        );
      }

      AppLogger.info('[Google] token received — exchanging with Supabase');
      final response = await _supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      AppLogger.info('[Google] Supabase token exchange result — user: ${response.user?.id}');

      if (response.user != null) {
        AppLogger.info('[Google] ensuring user profile exists');
        await _ensureUserProfile(
          userId: response.user!.id,
          email: response.user!.email ?? googleUser.email,
          name: googleUser.displayName ?? 'User',
        );
        AppLogger.info('[Google] sign-in complete — uid: ${response.user!.id}');
      }

      return response;
    } on PlatformException catch (e, stackTrace) {
      AppLogger.error('[Google] PlatformException: ${e.code} — ${e.message}\n$stackTrace');
      // Treat user-cancel codes gracefully (no scary error message).
      if (e.code == 'sign_in_canceled' || e.code == 'sign_in_failed') {
        throw Exception('Google sign-in was cancelled');
      }
      throw Exception('Google sign-in failed: ${e.message ?? e.code}');
    } catch (e, stackTrace) {
      AppLogger.error('[Google] sign-in error: $e\n$stackTrace');

      final raw = e.toString().toLowerCase();
      // Already a friendly message from above — rethrow as-is.
      if (raw.contains('cancelled')) rethrow;

      if (raw.contains('unacceptable audience') ||
          raw.contains('invalid id token') ||
          raw.contains('id_token')) {
        throw Exception(
          'Google token rejected by Supabase. '
          'Verify the Web OAuth client ID in auth_service.dart matches '
          'the "Authorized client IDs" setting in your Supabase Google provider.',
        );
      }
      if (raw.contains('provider is not enabled') ||
          raw.contains('unsupported provider')) {
        throw Exception(
          'Google sign-in is disabled. Enable the Google provider in '
          'your Supabase Auth dashboard and try again.',
        );
      }
      rethrow;
    } finally {
      // Always release the GoogleSignIn instance to avoid state leaks
      // if the widget is disposed before the future completes.
      try {
        await googleSignIn?.disconnect().timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
      } catch (_) {}
    }
  }

  // Sign in with Apple
  Future<AuthResponse> signInWithApple() async {
    AppLogger.info('[Apple] sign-in started');
    try {
      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      AppLogger.info('[Apple] requesting credential from Apple');
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      AppLogger.info(
        '[Apple] credential received — '
        'authCode present: ${credential.authorizationCode.isNotEmpty}, '
        'identityToken present: ${credential.identityToken != null}, '
        'email: ${credential.email ?? "(not returned — subsequent login)"}',
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        AppLogger.error('[Apple] identityToken is null — Apple did not return a token');
        throw Exception(
          'Apple did not return an identity token. '
          'This can happen if the Apple Sign-In service is temporarily unavailable '
          'or the app bundle ID is not registered in App Store Connect.',
        );
      }

      AppLogger.info('[Apple] exchanging token with Supabase');
      final response = await _supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );
      AppLogger.info('[Apple] Supabase token exchange result — user: ${response.user?.id}');

      if (response.user != null) {
        // Apple only returns name and email on the FIRST login.
        // On subsequent logins these fields are null — use existing profile.
        final givenName = credential.givenName;
        final familyName = credential.familyName;
        final nameParts = [givenName, familyName].whereType<String>().toList();
        final name = nameParts.isNotEmpty ? nameParts.join(' ') : null;
        final email = response.user!.email ?? credential.email ?? '';

        AppLogger.info('[Apple] ensuring user profile — name: ${name ?? "(not returned)"}, email: $email');
        await _ensureUserProfile(
          userId: response.user!.id,
          email: email,
          name: name ?? 'User',
        );
        AppLogger.info('[Apple] sign-in complete — uid: ${response.user!.id}');
      }

      return response;
    } on SignInWithAppleAuthorizationException catch (e) {
      AppLogger.info('[Apple] authorization exception: ${e.code} — ${e.message}');
      if (e.code == AuthorizationErrorCode.canceled) {
        // User deliberately cancelled — not an error worth showing.
        throw Exception('Apple sign-in was cancelled');
      }
      // Unknown / failed authorisation code.
      throw Exception('Apple sign-in failed: ${e.message}');
    } catch (e, stackTrace) {
      AppLogger.error('[Apple] sign-in error: $e\n$stackTrace');
      final raw = e.toString().toLowerCase();
      if (raw.contains('cancelled')) rethrow; // already friendly
      rethrow;
    }
  }

  /// Generate a random nonce string for Apple Sign-In
  String _generateNonce([int length = 32]) {
    const charset =
        '0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._';
    final random = Random.secure();
    return List.generate(
      length,
      (_) => charset[random.nextInt(charset.length)],
    ).join();
  }

  /// Create user profile if it doesn't already exist (for social logins)
  /// Uses a SECURITY DEFINER RPC to bypass RLS.
  Future<void> _ensureUserProfile({
    required String userId,
    required String email,
    required String name,
  }) async {
    try {
      await _supabaseClient.rpc(
        'ensure_user_profile',
        params: {
          'p_user_id': userId,
          'p_email': email,
          'p_name': name.isNotEmpty ? name : 'User',
          'p_role': 'user',
        },
      );
      AppLogger.info('User profile ensured via RPC');
    } catch (e) {
      AppLogger.error('Error ensuring user profile via RPC: $e');
      // Fallback: try direct insert (works if RLS INSERT policy exists)
      try {
        final existing = await _supabaseClient
            .from(AppConstants.tableUsers)
            .select('id')
            .eq('id', userId)
            .maybeSingle();

        if (existing == null) {
          await _createUserProfile(
            userId: userId,
            email: email,
            name: name.isNotEmpty ? name : 'User',
            role: 'user',
          );
        }
      } catch (fallbackError) {
        AppLogger.error(
          'Fallback profile creation also failed: $fallbackError',
        );
      }
    }
  }

  // Create user profile in database
  Future<void> _createUserProfile({
    required String userId,
    required String email,
    required String name,
    required String role,
  }) async {
    // The CHECK constraint on users.role allows
    // ('customer','driver','restaurant','admin'). Map any legacy 'user'
    // value to 'customer' so signup never violates the constraint.
    final safeRole = role == 'user' ? 'customer' : role;
    try {
      await _supabaseClient.from(AppConstants.tableUsers).upsert({
        'id': userId,
        'email': email,
        'name': name,
        'role': safeRole,
        'is_active': true,
        'updated_at': DateTime.now().toIso8601String(),
      });
      AppLogger.info('User profile created successfully');
    } catch (e) {
      // Do NOT rethrow — auth signup already succeeded, and the
      // onboarding service will retry with resilient fallbacks.
      AppLogger.error('Error creating user profile (non-fatal): $e');
    }
  }
}

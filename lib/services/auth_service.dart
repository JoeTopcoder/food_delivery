import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
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
    try {
      AppLogger.info('Signing in with Google');

      // This MUST be the Web Application OAuth client ID (not Android)
      const webClientId =
          '379314267431-qg34f9rs5ms8bkpq298o1cn7prnqv7eu.apps.googleusercontent.com';

      final googleSignIn = GoogleSignIn(serverClientId: webClientId);

      // Clear any stale session
      await googleSignIn.signOut();

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) {
        throw Exception('Google sign-in was cancelled');
      }

      final googleAuth = await googleUser.authentication;
      final idToken = googleAuth.idToken;
      final accessToken = googleAuth.accessToken;

      if (idToken == null) {
        throw Exception('No ID token from Google — check OAuth client config');
      }

      final response = await _supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
      );

      if (response.user != null) {
        await _ensureUserProfile(
          userId: response.user!.id,
          email: response.user!.email ?? googleUser.email,
          name: googleUser.displayName ?? 'User',
        );
      }

      AppLogger.info('Google sign-in successful');
      return response;
    } catch (e, stackTrace) {
      AppLogger.error('Google sign-in error: $e\n$stackTrace');
      rethrow;
    }
  }

  // Sign in with Apple
  Future<AuthResponse> signInWithApple() async {
    try {
      AppLogger.info('Signing in with Apple');

      final rawNonce = _generateNonce();
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce,
      );

      final idToken = credential.identityToken;
      if (idToken == null) {
        throw Exception('No identity token received from Apple');
      }

      final response = await _supabaseClient.auth.signInWithIdToken(
        provider: OAuthProvider.apple,
        idToken: idToken,
        nonce: rawNonce,
      );

      if (response.user != null) {
        final name = [
          credential.givenName,
          credential.familyName,
        ].where((n) => n != null).join(' ');

        await _ensureUserProfile(
          userId: response.user!.id,
          email: response.user!.email ?? credential.email ?? '',
          name: name.isNotEmpty ? name : 'User',
        );
      }

      AppLogger.info('Apple sign-in successful');
      return response;
    } catch (e) {
      AppLogger.error('Apple sign-in error: $e');
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
    try {
      await _supabaseClient.from(AppConstants.tableUsers).insert({
        'id': userId,
        'email': email,
        'name': name,
        'role': role,
        'is_active': true,
        'created_at': DateTime.now().toIso8601String(),
      });
      AppLogger.info('User profile created successfully');
    } catch (e) {
      AppLogger.error('Error creating user profile: $e');
      rethrow;
    }
  }
}

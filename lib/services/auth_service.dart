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

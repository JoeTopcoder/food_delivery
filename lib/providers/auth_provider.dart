import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../services/user_service.dart';
import '../utils/app_logger.dart';

// Auth Service Provider
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService(SupabaseConfig.client);
});

// User Service Provider
final userServiceProvider = Provider<UserService>((ref) {
  return UserService(SupabaseConfig.client);
});

// Current Supabase User Provider
final currentSupabaseUserProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);

  return authService.onAuthStateChanged().asyncMap((event) async {
    if (event.session != null) {
      final userService = ref.watch(userServiceProvider);
      try {
        final user = await userService.getUserById(event.session!.user.id);
        return user;
      } catch (e) {
        AppLogger.error('Error fetching user: $e');
        return null;
      }
    }
    return null;
  });
});

// Current User Provider (for easy access)
final currentUserProvider = Provider<User?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.user;
});

// Current User ID Provider — reactive to auth state changes
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.user?.id;
});

// Current User Role Provider
final currentUserRoleProvider = FutureProvider<String?>((ref) async {
  final user = await ref.watch(currentSupabaseUserProvider.future);
  return user?.role;
});

// Auth State Provider
class AuthState {
  final bool isLoading;
  final User? user;
  final String? error;
  final bool isAuthenticated;
  final bool emailConfirmationPending;

  AuthState({
    this.isLoading = false,
    this.user,
    this.error,
    this.isAuthenticated = false,
    this.emailConfirmationPending = false,
  });

  AuthState copyWith({
    bool? isLoading,
    User? user,
    String? error,
    bool? isAuthenticated,
    bool? emailConfirmationPending,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error ?? this.error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
      emailConfirmationPending:
          emailConfirmationPending ?? this.emailConfirmationPending,
    );
  }
}

// Auth State Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final UserService _userService;
  final NotificationService _notificationService = NotificationService();
  StreamSubscription? _authStateSub;

  AuthNotifier(this._authService, this._userService) : super(AuthState()) {
    _initializeAuth();
    _listenToAuthChanges();
  }

  /// Subscribe to FCM topics based on user role (all in parallel).
  Future<void> _subscribeToUserTopics(User user) async {
    try {
      final futures = <Future<void>>[
        _notificationService.subscribeToTopic('customer_${user.id}'),
      ];
      switch (user.role) {
        case 'driver':
          futures.add(
            _notificationService.subscribeToTopic('driver_${user.id}'),
          );
          break;
        case 'restaurant':
          futures.add(
            _notificationService.subscribeToTopic('restaurant_${user.id}'),
          );
          break;
        case 'admin':
          futures.add(_notificationService.subscribeToTopic('admins'));
          break;
      }
      await Future.wait(futures);
      AppLogger.info('Subscribed to FCM topics for role: ${user.role}');
    } catch (e) {
      AppLogger.error('Error subscribing to FCM topics: $e');
    }
  }

  /// Unsubscribe from all FCM topics on logout (all in parallel).
  Future<void> _unsubscribeFromAllTopics(User user) async {
    try {
      await Future.wait([
        _notificationService.unsubscribeFromTopic('customer_${user.id}'),
        _notificationService.unsubscribeFromTopic('driver_${user.id}'),
        _notificationService.unsubscribeFromTopic('restaurant_${user.id}'),
        _notificationService.unsubscribeFromTopic('admins'),
      ]);
    } catch (e) {
      AppLogger.error('Error unsubscribing from FCM topics: $e');
    }
  }

  Future<void> _initializeAuth() async {
    final supabaseUser = _authService.getCurrentUser();
    if (supabaseUser != null) {
      await _hydrateUserFromAuth(
        supabaseUser.id,
        fallbackEmail: supabaseUser.email,
      );
    }
  }

  void _listenToAuthChanges() {
    _authStateSub = _authService.onAuthStateChanged().listen((event) async {
      final session = event.session;

      if (session == null) {
        final previousUser = state.user;
        if (previousUser != null) {
          _unsubscribeFromAllTopics(previousUser);
        }
        state = AuthState(isLoading: false);
        return;
      }

      await _hydrateUserFromAuth(
        session.user.id,
        fallbackEmail: session.user.email,
      );
    });
  }

  /// Re-fetches the current user from the database so any role/profile
  /// updates made during onboarding are reflected in the in-memory state.
  Future<void> refreshUser() async {
    final supabaseUser = _authService.getCurrentUser();
    if (supabaseUser == null) return;
    await _hydrateUserFromAuth(
      supabaseUser.id,
      fallbackEmail: supabaseUser.email,
    );
  }

  Future<void> _hydrateUserFromAuth(
    String userId, {
    String? fallbackEmail,
  }) async {
    try {
      User? user = await _userService.getUserById(userId);
      if (user == null) {
        final supabaseUser = _authService.getCurrentUser();
        final meta = supabaseUser?.userMetadata ?? {};
        user = User(
          id: userId,
          email: fallbackEmail ?? supabaseUser?.email ?? '',
          name: meta['name'] as String?,
          role: meta['role'] as String? ?? 'user',
          createdAt: DateTime.now(),
        );
      }

      final previousUserId = state.user?.id;
      state = state.copyWith(
        isLoading: false,
        user: user,
        isAuthenticated: true,
        error: null,
      );

      if (previousUserId != user.id) {
        _subscribeToUserTopics(user);
      }
    } catch (e) {
      AppLogger.error('Error hydrating auth user: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> signUp({
    required String email,
    required String password,
    required String name,
    required String role,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _authService.signUp(
        email: email,
        password: password,
        name: name,
        role: role,
      );
      AppLogger.info('Sign up successful');
      if (response.user != null) {
        // If Supabase has "Confirm email" enabled, signUp returns a user
        // but NO session. Try signing in immediately so the onboarding
        // flow has an authenticated session to work with.
        if (response.session == null) {
          try {
            await _authService.signIn(email: email, password: password);
          } catch (e) {
            final msg = e.toString().toLowerCase();
            if (msg.contains('email_not_confirmed') ||
                msg.contains('email not confirmed')) {
              AppLogger.info('Email confirmation required for $email');
              state = state.copyWith(
                isLoading: false,
                emailConfirmationPending: true,
              );
              // Don't rethrow — this is expected flow, not an error
              return;
            }
            AppLogger.error('Auto sign-in after signup failed: $e');
            state = state.copyWith(
              isLoading: false,
              error:
                  'Account created. Please check your email to confirm, then sign in.',
            );
            throw Exception(
              'Account created. Please check your email to confirm your address before continuing.',
            );
          }
        }

        User? user = await _userService.getUserById(response.user!.id);
        // Fallback: use the role passed directly since we just signed up
        user ??= User(
          id: response.user!.id,
          email: email,
          name: name,
          role: role,
          createdAt: DateTime.now(),
        );
        AppLogger.info('Sign up role: ${user.role}');
        state = state.copyWith(
          isLoading: false,
          user: user,
          isAuthenticated: true,
        );
        _subscribeToUserTopics(user); // fire-and-forget
      } else {
        state = state.copyWith(isLoading: false, isAuthenticated: true);
      }
    } catch (e) {
      AppLogger.error('Sign up error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _authService.signIn(
        email: email,
        password: password,
      );

      if (response.user != null) {
        User? user = await _userService.getUserById(response.user!.id);
        // Fallback: build user from auth metadata if DB lookup fails
        if (user == null) {
          final meta = response.user!.userMetadata ?? {};
          user = User(
            id: response.user!.id,
            email: email,
            name: meta['name'] as String?,
            role: meta['role'] as String? ?? 'user',
            createdAt: DateTime.now(),
          );
        }
        AppLogger.info('Sign in successful, role: ${user.role}');
        state = state.copyWith(
          isLoading: false,
          user: user,
          isAuthenticated: true,
        );
        _subscribeToUserTopics(
          user,
        ); // fire-and-forget — don't block navigation
      }
    } catch (e) {
      AppLogger.error('Sign in error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> signOut() async {
    final currentUser = state.user;

    // Clear local auth state FIRST so UI navigates to sign-in immediately
    state = AuthState(isLoading: false);

    // Then clean up in the background (non-blocking)
    try {
      if (currentUser != null) {
        _unsubscribeFromAllTopics(currentUser);
      }
      await _authService.signOut().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          AppLogger.error('Sign out timed out – local state already cleared');
        },
      );
      AppLogger.info('Sign out successful');
    } catch (e) {
      AppLogger.error('Sign out error: $e');
      // State already cleared above — user is not stuck
    }
  }

  Future<void> signInWithGoogle() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _authService.signInWithGoogle();

      if (response.user != null) {
        final authUser = response.user!;
        User? user;
        try {
          user = await _userService.getUserById(authUser.id);
        } catch (e) {
          AppLogger.error('getUserById failed after Google sign-in: $e');
        }
        user ??= User(
          id: authUser.id,
          email: authUser.email ?? '',
          name:
              authUser.userMetadata?['full_name'] as String? ??
              authUser.userMetadata?['name'] as String? ??
              'User',
          role: 'user',
          createdAt: DateTime.now(),
        );
        AppLogger.info('Google sign-in successful, role: ${user.role}');
        state = state.copyWith(
          isLoading: false,
          user: user,
          isAuthenticated: true,
        );
        _subscribeToUserTopics(user); // fire-and-forget
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Google sign-in returned no user',
        );
      }
    } catch (e) {
      AppLogger.error('Google sign-in error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> signInWithApple() async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final response = await _authService.signInWithApple();

      if (response.user != null) {
        final authUser = response.user!;
        User? user;
        try {
          user = await _userService.getUserById(authUser.id);
        } catch (e) {
          AppLogger.error('getUserById failed after Apple sign-in: $e');
        }
        user ??= User(
          id: authUser.id,
          email: authUser.email ?? '',
          name:
              authUser.userMetadata?['full_name'] as String? ??
              authUser.userMetadata?['name'] as String? ??
              'User',
          role: 'user',
          createdAt: DateTime.now(),
        );
        AppLogger.info('Apple sign-in successful, role: ${user.role}');
        state = state.copyWith(
          isLoading: false,
          user: user,
          isAuthenticated: true,
        );
        _subscribeToUserTopics(user); // fire-and-forget
      } else {
        state = state.copyWith(
          isLoading: false,
          error: 'Apple sign-in returned no user',
        );
      }
    } catch (e) {
      AppLogger.error('Apple sign-in error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> resetPassword(String email) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      await _authService.resetPassword(email);
      AppLogger.info('Password reset email sent');
      state = state.copyWith(isLoading: false);
    } catch (e) {
      AppLogger.error('Password reset error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> updateUserProfile({
    required String userId,
    String? name,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
    String? profileImageUrl,
  }) async {
    state = state.copyWith(isLoading: true, error: null);
    try {
      final updatedUser = await _userService.updateUserProfile(
        userId: userId,
        name: name,
        phone: phone,
        address: address,
        latitude: latitude,
        longitude: longitude,
        profileImageUrl: profileImageUrl,
      );

      state = state.copyWith(isLoading: false, user: updatedUser);
    } catch (e) {
      AppLogger.error('Update profile error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  @override
  void dispose() {
    _authStateSub?.cancel();
    super.dispose();
  }
}

// Auth State Notifier Provider
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  final authService = ref.watch(authServiceProvider);
  final userService = ref.watch(userServiceProvider);
  return AuthNotifier(authService, userService);
});

final authProvider = authNotifierProvider;

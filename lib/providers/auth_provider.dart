import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/supabase_config.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../services/cache_service.dart';
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
  ref.keepAlive();
  final authService = ref.watch(authServiceProvider);
  // Use ref.read for services inside async callbacks — ref.watch is not safe
  // inside asyncMap because the async closure outlives any single build cycle.
  final userService = ref.read(userServiceProvider);

  return authService.onAuthStateChanged().asyncMap((event) async {
    if (event.session != null) {
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

// Session-scoped user profile override — updated by profile-screen edits
// without touching authNotifierProvider (which triggers routing side-effects).
// Automatically ignored when the logged-in user changes (different ID).
final userSessionOverrideProvider = StateProvider<User?>((ref) => null);

// Current User Provider (for easy access)
final currentUserProvider = Provider<User?>((ref) {
  final authUser = ref.watch(authNotifierProvider).user;
  final override = ref.watch(userSessionOverrideProvider);
  // Only apply override if it belongs to the current user's session
  if (override != null && override.id == authUser?.id) return override;
  return authUser;
});

// Current User ID Provider — reactive to auth state changes
final currentUserIdProvider = Provider<String?>((ref) {
  final authState = ref.watch(authNotifierProvider);
  return authState.user?.id;
});

// Current User Role Provider
final currentUserRoleProvider = FutureProvider<String?>((ref) async {
  ref.keepAlive();
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

  AuthNotifier(this._authService, this._userService) : super(AuthState(isLoading: true)) {
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
        case 'laundry_provider':
          futures.add(
            _notificationService.subscribeToTopic(
              'laundry_provider_${user.id}',
            ),
          );
          break;
        case 'service_provider':
          futures.add(
            _notificationService.subscribeToTopic(
              'service_provider_${user.id}',
            ),
          );
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
        _notificationService.unsubscribeFromTopic(
          'laundry_provider_${user.id}',
        ),
        _notificationService.unsubscribeFromTopic(
          'service_provider_${user.id}',
        ),
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
    } else {
      // No active session — mark loading done so the gate shows auth screens.
      state = state.copyWith(isLoading: false);
    }
  }

  void _listenToAuthChanges() {
    _authStateSub = _authService.onAuthStateChanged().listen((event) async {
      final session = event.session;

      if (session == null) {
        // Guard against spurious null events during token refresh on resume.
        // Supabase can emit a null session event mid-refresh; if the SDK still
        // has a valid currentSession, treat this as a transient race and ignore.
        final currentSession = SupabaseConfig.client.auth.currentSession;
        if (currentSession != null) {
          AppLogger.info('[Auth] Null event but currentSession exists — ignoring stale event');
          return;
        }
        // Poll up to 3 seconds (10 × 300 ms) for the session to come back.
        // On slow networks the token refresh takes well over 600 ms, which
        // was the old single-delay guard — not enough on Android resume.
        for (int i = 0; i < 10; i++) {
          await Future.delayed(const Duration(milliseconds: 300));
          if (SupabaseConfig.client.auth.currentSession != null) {
            AppLogger.info('[Auth] Null event resolved after ${(i + 1) * 300}ms — ignoring');
            return;
          }
        }
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
    const cacheBox = 'user_profile';

    // Serve cached profile immediately so the app opens without waiting for DB.
    try {
      final raw = await CacheService.get(cacheBox, userId);
      if (raw != null) {
        final cached = User.fromJson(Map<String, dynamic>.from(raw as Map));
        if (state.user?.id != cached.id) {
          state = state.copyWith(
            isLoading: false,
            user: cached,
            isAuthenticated: true,
            error: null,
          );
          _subscribeToUserTopics(cached);
        } else {
          state = state.copyWith(isLoading: false);
        }
      }
    } catch (_) {}

    // Fetch fresh profile from DB in the background (or block if no cache yet).
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
      } else {
        // DB triggers often create users with default 'customer' role.
        // If auth metadata has a more specific role (set at signup), use it.
        final supabaseUser = _authService.getCurrentUser();
        final metaRole = supabaseUser?.userMetadata?['role'] as String?;
        if ((user.role == 'customer' || user.role == 'user') &&
            metaRole != null &&
            metaRole != 'customer' &&
            metaRole != 'user') {
          user = user.copyWith(role: metaRole);
        }
      }

      // Persist fresh profile for next launch.
      unawaited(CacheService.put(cacheBox, userId, user.toJson(), ttlSeconds: 3600));

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
      // Only show error if we have no cached user to fall back on.
      if (state.user == null) {
        state = state.copyWith(isLoading: false, error: e.toString());
      }
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
                msg.contains('email not confirmed') ||
                msg.contains('confirm') ||
                msg.contains('not confirmed') ||
                msg.contains('unconfirmed') ||
                msg.contains('verify')) {
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
        // DB triggers can create the user with a default role (e.g. 'customer').
        // Always honour the role that was explicitly requested at sign-up time.
        if (user.role != role) {
          user = user.copyWith(role: role);
        }
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
    // Do NOT set isLoading: true here — the auth gate screen watches
    // authNotifierProvider and treats isLoading:true as "still loading",
    // which resets the navigation stack to the home screen.
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

      state = state.copyWith(user: updatedUser);
    } catch (e) {
      AppLogger.error('Update profile error: $e');
      state = state.copyWith(error: e.toString());
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

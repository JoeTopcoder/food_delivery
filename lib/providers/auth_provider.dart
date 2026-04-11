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

  AuthState({
    this.isLoading = false,
    this.user,
    this.error,
    this.isAuthenticated = false,
  });

  AuthState copyWith({
    bool? isLoading,
    User? user,
    String? error,
    bool? isAuthenticated,
  }) {
    return AuthState(
      isLoading: isLoading ?? this.isLoading,
      user: user ?? this.user,
      error: error ?? this.error,
      isAuthenticated: isAuthenticated ?? this.isAuthenticated,
    );
  }
}

// Auth State Notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final UserService _userService;
  final NotificationService _notificationService = NotificationService();

  AuthNotifier(this._authService, this._userService) : super(AuthState()) {
    _initializeAuth();
  }

  /// Subscribe to FCM topics based on user role
  Future<void> _subscribeToUserTopics(User user) async {
    try {
      // Everyone subscribes to their personal topic
      await _notificationService.subscribeToTopic('customer_${user.id}');

      // Role-specific topics
      switch (user.role) {
        case 'driver':
          await _notificationService.subscribeToTopic('driver_${user.id}');
          break;
        case 'restaurant':
          await _notificationService.subscribeToTopic('restaurant_${user.id}');
          break;
        case 'admin':
          await _notificationService.subscribeToTopic('admins');
          break;
      }
      AppLogger.info('Subscribed to FCM topics for role: ${user.role}');
    } catch (e) {
      AppLogger.error('Error subscribing to FCM topics: $e');
    }
  }

  /// Unsubscribe from all FCM topics on logout
  Future<void> _unsubscribeFromAllTopics(User user) async {
    try {
      await _notificationService.unsubscribeFromTopic('customer_${user.id}');
      await _notificationService.unsubscribeFromTopic('driver_${user.id}');
      await _notificationService.unsubscribeFromTopic('restaurant_${user.id}');
      await _notificationService.unsubscribeFromTopic('admins');
    } catch (e) {
      AppLogger.error('Error unsubscribing from FCM topics: $e');
    }
  }

  Future<void> _initializeAuth() async {
    final supabaseUser = _authService.getCurrentUser();
    if (supabaseUser != null) {
      try {
        User? user = await _userService.getUserById(supabaseUser.id);
        // Fallback: build user from auth metadata if DB lookup fails
        if (user == null) {
          final meta = supabaseUser.userMetadata ?? {};
          user = User(
            id: supabaseUser.id,
            email: supabaseUser.email ?? '',
            name: meta['name'] as String?,
            role: meta['role'] as String? ?? 'user',
            createdAt: DateTime.now(),
          );
        }
        state = state.copyWith(user: user, isAuthenticated: true);
        await _subscribeToUserTopics(user);
      } catch (e) {
        AppLogger.error('Error initializing auth: $e');
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
        await _subscribeToUserTopics(user);
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
        await _subscribeToUserTopics(user);
      }
    } catch (e) {
      AppLogger.error('Sign in error: $e');
      state = state.copyWith(isLoading: false, error: e.toString());
      rethrow;
    }
  }

  Future<void> signOut() async {
    state = state.copyWith(isLoading: true);
    try {
      final currentUser = state.user;
      if (currentUser != null) {
        await _unsubscribeFromAllTopics(currentUser);
      }
      await _authService.signOut();
      AppLogger.info('Sign out successful');
      state = AuthState(isLoading: false);
    } catch (e) {
      AppLogger.error('Sign out error: $e');
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
}

// Auth State Notifier Provider
final authNotifierProvider = StateNotifierProvider<AuthNotifier, AuthState>((
  ref,
) {
  final authService = ref.watch(authServiceProvider);
  final userService = ref.watch(userServiceProvider);
  return AuthNotifier(authService, userService);
});

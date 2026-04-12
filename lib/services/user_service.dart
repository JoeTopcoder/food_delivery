import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import '../config/app_constants.dart';
import '../models/user_model.dart';
import '../utils/app_logger.dart';

class UserService {
  final SupabaseClient _supabaseClient;

  static String _sanitizeQuery(String q) =>
      q.replaceAll(RegExp(r'[%_(),.\\]'), '');

  UserService(this._supabaseClient);

  // Get user by ID
  Future<User?> getUserById(String userId) async {
    try {
      AppLogger.info('Fetching user: $userId');

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .eq('id', userId)
          .single();

      final user = User.fromJson(response);
      AppLogger.info('User fetched successfully');
      return user;
    } catch (e) {
      AppLogger.error('Error fetching user: $e');
      return null;
    }
  }

  // Update user profile
  Future<User?> updateUserProfile({
    required String userId,
    String? name,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
    String? profileImageUrl,
  }) async {
    try {
      AppLogger.info('Updating user profile: $userId');

      final updateData = <String, dynamic>{
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (name != null) updateData['name'] = name;
      if (phone != null) updateData['phone'] = phone;
      if (address != null) updateData['address'] = address;
      if (latitude != null) updateData['latitude'] = latitude;
      if (longitude != null) updateData['longitude'] = longitude;
      if (profileImageUrl != null) {
        updateData['profile_image_url'] = profileImageUrl;
      }

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .update(updateData)
          .eq('id', userId)
          .select()
          .single();

      final user = User.fromJson(response);
      AppLogger.info('User profile updated successfully');
      return user;
    } catch (e) {
      AppLogger.error('Error updating user profile: $e');
      rethrow;
    }
  }

  // Get all users (for admin)
  Future<List<User>> getAllUsers({int? limit, int offset = 0}) async {
    limit ??= AppConstants.pageSize;
    try {
      AppLogger.info('Fetching all users');

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .range(offset, offset + limit - 1);

      final users = (response as List)
          .map((user) => User.fromJson(user))
          .toList();

      AppLogger.info('Fetched ${users.length} users');
      return users;
    } catch (e) {
      AppLogger.error('Error fetching users: $e');
      rethrow;
    }
  }

  // Search users by email or name
  Future<List<User>> searchUsers(String query) async {
    try {
      AppLogger.info('Searching users: $query');

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .or('email.ilike.%${_sanitizeQuery(query)}%,name.ilike.%${_sanitizeQuery(query)}%');

      final users = (response as List)
          .map((user) => User.fromJson(user))
          .toList();

      AppLogger.info('Found ${users.length} users');
      return users;
    } catch (e) {
      AppLogger.error('Error searching users: $e');
      rethrow;
    }
  }

  // Delete user (for admin)
  Future<void> deleteUser(String userId) async {
    try {
      AppLogger.info('Deleting user: $userId');

      await _supabaseClient
          .from(AppConstants.tableUsers)
          .delete()
          .eq('id', userId);

      AppLogger.info('User deleted successfully');
    } catch (e) {
      AppLogger.error('Error deleting user: $e');
      rethrow;
    }
  }

  // Get users by role
  Future<List<User>> getUsersByRole(String role) async {
    try {
      AppLogger.info('Fetching users by role: $role');

      final response = await _supabaseClient
          .from(AppConstants.tableUsers)
          .select()
          .eq('role', role);

      final users = (response as List)
          .map((user) => User.fromJson(user))
          .toList();

      AppLogger.info('Fetched ${users.length} users with role: $role');
      return users;
    } catch (e) {
      AppLogger.error('Error fetching users by role: $e');
      rethrow;
    }
  }

  // Update user active status
  Future<void> updateUserActiveStatus(String userId, bool isActive) async {
    try {
      AppLogger.info('Updating user active status: $userId -> $isActive');

      await _supabaseClient
          .from(AppConstants.tableUsers)
          .update({
            'is_active': isActive,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      AppLogger.info('User active status updated');
    } catch (e) {
      AppLogger.error('Error updating user active status: $e');
      rethrow;
    }
  }
}

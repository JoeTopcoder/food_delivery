import 'dart:math';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/group_order_model.dart';
import '../utils/app_logger.dart';

class GroupOrderService {
  final SupabaseClient _client;
  GroupOrderService(this._client);

  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  // Create a group order
  Future<GroupOrder?> createGroupOrder({
    required String hostUserId,
    required String restaurantId,
    required String name,
    String? deliveryAddress,
    double? deliveryLatitude,
    double? deliveryLongitude,
    int deadlineMinutes = 60,
  }) async {
    try {
      final code = _generateInviteCode();
      final deadline = DateTime.now().add(Duration(minutes: deadlineMinutes));
      final response = await _client
          .from('group_orders')
          .insert({
            'host_user_id': hostUserId,
            'restaurant_id': restaurantId,
            'name': name,
            'invite_code': code,
            'deadline': deadline.toIso8601String(),
            'delivery_address': deliveryAddress,
            'delivery_latitude': deliveryLatitude,
            'delivery_longitude': deliveryLongitude,
          })
          .select('*, group_order_participants(*)')
          .single();

      // Also add host as participant
      await _client.from('group_order_participants').insert({
        'group_order_id': response['id'],
        'user_id': hostUserId,
      });

      return GroupOrder.fromJson(response);
    } catch (e) {
      AppLogger.error('Error creating group order: $e');
      return null;
    }
  }

  // Join by invite code
  Future<GroupOrder?> joinByCode({
    required String inviteCode,
    required String userId,
  }) async {
    try {
      final response = await _client
          .from('group_orders')
          .select('*, group_order_participants(*)')
          .eq('invite_code', inviteCode.toUpperCase())
          .eq('status', 'collecting')
          .single();

      final groupOrder = GroupOrder.fromJson(response);

      // Check if already joined
      final alreadyJoined = groupOrder.participants.any(
        (p) => p.userId == userId,
      );
      if (!alreadyJoined) {
        await _client.from('group_order_participants').insert({
          'group_order_id': groupOrder.id,
          'user_id': userId,
        });
      }

      return await getGroupOrder(groupOrder.id);
    } catch (e) {
      AppLogger.error('Error joining group order: $e');
      return null;
    }
  }

  // Get group order with participants
  Future<GroupOrder?> getGroupOrder(String groupOrderId) async {
    try {
      final response = await _client
          .from('group_orders')
          .select('*, group_order_participants(*)')
          .eq('id', groupOrderId)
          .single();
      return GroupOrder.fromJson(response);
    } catch (e) {
      AppLogger.error('Error fetching group order: $e');
      return null;
    }
  }

  // Get user's group orders
  Future<List<GroupOrder>> getUserGroupOrders(String userId) async {
    try {
      // Get as host
      final hostResponse = await _client
          .from('group_orders')
          .select('*, group_order_participants(*)')
          .eq('host_user_id', userId)
          .order('created_at', ascending: false);

      // Get as participant
      final participantIds = await _client
          .from('group_order_participants')
          .select('group_order_id')
          .eq('user_id', userId);

      final ids = (participantIds as List)
          .map((e) => e['group_order_id'] as String)
          .toSet();

      final hostIds = (hostResponse as List)
          .map((e) => e['id'] as String)
          .toSet();

      // Fetch any group orders where user is participant but not host
      final extraIds = ids.difference(hostIds);
      List<dynamic> participantResponse = [];
      if (extraIds.isNotEmpty) {
        participantResponse = await _client
            .from('group_orders')
            .select('*, group_order_participants(*)')
            .inFilter('id', extraIds.toList());
      }

      final all = [...hostResponse, ...participantResponse];
      return all
          .map((e) => GroupOrder.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('Error fetching group orders: $e');
      return [];
    }
  }

  // Update participant items
  Future<bool> updateParticipantItems({
    required String participantId,
    required List<Map<String, dynamic>> items,
    required double subtotal,
  }) async {
    try {
      await _client
          .from('group_order_participants')
          .update({'items': items, 'subtotal': subtotal})
          .eq('id', participantId);
      return true;
    } catch (e) {
      AppLogger.error('Error updating participant items: $e');
      return false;
    }
  }

  // Lock the group order (host only)
  Future<bool> lockGroupOrder(String groupOrderId) async {
    try {
      await _client
          .from('group_orders')
          .update({
            'status': 'locked',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', groupOrderId);
      return true;
    } catch (e) {
      AppLogger.error('Error locking group order: $e');
      return false;
    }
  }

  // Cancel group order
  Future<bool> cancelGroupOrder(String groupOrderId) async {
    try {
      await _client
          .from('group_orders')
          .update({
            'status': 'cancelled',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', groupOrderId);
      return true;
    } catch (e) {
      AppLogger.error('Error cancelling group order: $e');
      return false;
    }
  }

  // Mark group order as ordered (closed — cannot be used again)
  Future<bool> markAsOrdered(String groupOrderId) async {
    try {
      await _client
          .from('group_orders')
          .update({
            'status': 'ordered',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', groupOrderId);
      return true;
    } catch (e) {
      AppLogger.error('Error marking group order as ordered: $e');
      return false;
    }
  }
}

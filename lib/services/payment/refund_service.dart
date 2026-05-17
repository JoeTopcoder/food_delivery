import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/refund_model.dart';
import '../../utils/app_logger.dart';

class RefundService {
  final SupabaseClient _client;
  RefundService(this._client);

  // Request a refund
  Future<Refund?> requestRefund({
    required String orderId,
    required String userId,
    required double amount,
    required String reason,
  }) async {
    try {
      final response = await _client
          .from('refunds')
          .insert({
            'order_id': orderId,
            'user_id': userId,
            'amount': amount,
            'reason': reason,
          })
          .select()
          .single();
      return Refund.fromJson(response);
    } catch (e) {
      AppLogger.error('Error requesting refund: $e');
      return null;
    }
  }

  // Get refunds for user
  Future<List<Refund>> getUserRefunds(String userId) async {
    try {
      final response = await _client
          .from('refunds')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (response as List).map((e) => Refund.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching refunds: $e');
      return [];
    }
  }

  // Get all refunds (admin)
  Future<List<Refund>> getAllRefunds() async {
    try {
      final response = await _client
          .from('refunds')
          .select()
          .order('created_at', ascending: false);
      return (response as List).map((e) => Refund.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching all refunds: $e');
      return [];
    }
  }

  // Update refund status (admin)
  Future<bool> updateRefundStatus({
    required String refundId,
    required String status,
    String? adminNotes,
  }) async {
    try {
      await _client
          .from('refunds')
          .update({
            'status': status,
            'admin_notes': adminNotes,
            'updated_at': DateTime.now().toIso8601String(),
            if (status == 'processed')
              'processed_at': DateTime.now().toIso8601String(),
          })
          .eq('id', refundId);
      return true;
    } catch (e) {
      AppLogger.error('Error updating refund: $e');
      return false;
    }
  }

  // File a dispute
  Future<Dispute?> fileDispute({
    required String orderId,
    required String userId,
    required String type,
    required String description,
    List<String>? photoUrls,
  }) async {
    try {
      final response = await _client
          .from('disputes')
          .insert({
            'order_id': orderId,
            'user_id': userId,
            'type': type,
            'description': description,
            'photo_urls': ?photoUrls,
          })
          .select()
          .single();
      return Dispute.fromJson(response);
    } catch (e) {
      AppLogger.error('Error filing dispute: $e');
      return null;
    }
  }

  // Get user disputes
  Future<List<Dispute>> getUserDisputes(String userId) async {
    try {
      final response = await _client
          .from('disputes')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);
      return (response as List).map((e) => Dispute.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching disputes: $e');
      return [];
    }
  }

  // Get all disputes (admin)
  Future<List<Dispute>> getAllDisputes() async {
    try {
      final response = await _client
          .from('disputes')
          .select()
          .order('created_at', ascending: false);
      return (response as List).map((e) => Dispute.fromJson(e)).toList();
    } catch (e) {
      AppLogger.error('Error fetching all disputes: $e');
      return [];
    }
  }

  // Resolve dispute (admin)
  Future<bool> resolveDispute({
    required String disputeId,
    required String resolution,
    required String resolvedBy,
    String? refundId,
  }) async {
    try {
      await _client
          .from('disputes')
          .update({
            'status': 'resolved',
            'resolution': resolution,
            'resolved_by': resolvedBy,
            'refund_id': ?refundId,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', disputeId);
      return true;
    } catch (e) {
      AppLogger.error('Error resolving dispute: $e');
      return false;
    }
  }
}

import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_constants.dart';

class ComplianceService {
  final SupabaseClient _client;

  ComplianceService(this._client);

  // ── Support requests ──────────────────────────────────────────────────────

  Future<void> submitSupportRequest({
    String? userId,
    required String name,
    required String email,
    required String category,
    required String message,
    String? orderId,
  }) async {
    await _client.from(AppConstants.tableSupportRequests).insert({
      'user_id': userId,
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'category': category,
      'message': message.trim(),
      'order_id': orderId?.trim().isEmpty == true ? null : orderId?.trim(),
      'status': 'open',
    });
  }

  // ── Account deletion requests ─────────────────────────────────────────────

  Future<void> requestAccountDeletion({
    String? userId,
    required String email,
    String? reason,
  }) async {
    await _client.from(AppConstants.tableUserDeletionRequests).insert({
      'user_id': userId,
      'email': email.trim().toLowerCase(),
      'reason': reason?.trim().isEmpty == true ? null : reason?.trim(),
      'status': 'pending',
    });
  }

  // ── Chat / user reports ───────────────────────────────────────────────────

  Future<void> submitChatReport({
    required String reporterId,
    String? reportedUserId,
    String? messageId,
    String? orderId,
    required String reason,
    String? details,
  }) async {
    await _client.from(AppConstants.tableChatReports).insert({
      'reporter_id': reporterId,
      'reported_user_id': reportedUserId,
      'message_id': messageId,
      'order_id': orderId,
      'reason': reason,
      'details': details?.trim().isEmpty == true ? null : details?.trim(),
      'status': 'open',
    });
  }

  // ── Admin reads ───────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> fetchSupportRequests({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client
        .from(AppConstants.tableSupportRequests)
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    if (status != null) {
      query = _client
          .from(AppConstants.tableSupportRequests)
          .select()
          .eq('status', status)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
    }
    final data = await query;
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> fetchDeletionRequests({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client
        .from(AppConstants.tableUserDeletionRequests)
        .select()
        .order('requested_at', ascending: false)
        .range(offset, offset + limit - 1);
    if (status != null) {
      query = _client
          .from(AppConstants.tableUserDeletionRequests)
          .select()
          .eq('status', status)
          .order('requested_at', ascending: false)
          .range(offset, offset + limit - 1);
    }
    final data = await query;
    return List<Map<String, dynamic>>.from(data);
  }

  Future<List<Map<String, dynamic>>> fetchChatReports({
    String? status,
    int limit = 50,
    int offset = 0,
  }) async {
    var query = _client
        .from(AppConstants.tableChatReports)
        .select()
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    if (status != null) {
      query = _client
          .from(AppConstants.tableChatReports)
          .select()
          .eq('status', status)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
    }
    final data = await query;
    return List<Map<String, dynamic>>.from(data);
  }

  Future<void> updateSupportRequestStatus(
    String id,
    String status, {
    String? adminNotes,
  }) async {
    await _client.from(AppConstants.tableSupportRequests).update({
      'status': status,
      if (adminNotes != null) 'admin_notes': adminNotes,
    }).eq('id', id);
  }

  Future<void> updateDeletionRequestStatus(
    String id,
    String status, {
    String? adminNotes,
  }) async {
    await _client.from(AppConstants.tableUserDeletionRequests).update({
      'status': status,
      'processed_at': status == 'processed' ? DateTime.now().toIso8601String() : null,
      if (adminNotes != null) 'admin_notes': adminNotes,
    }).eq('id', id);
  }

  Future<void> updateChatReportStatus(
    String id,
    String status,
  ) async {
    await _client.from(AppConstants.tableChatReports).update({
      'status': status,
    }).eq('id', id);
  }
}

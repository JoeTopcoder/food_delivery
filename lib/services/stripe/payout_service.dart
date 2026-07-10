import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/stripe/payout_request_model.dart';

class StripePayoutService {
  StripePayoutService(this._client);
  final SupabaseClient _client;

  /// Request a payout for the current user.
  Future<PayoutRequest> requestPayout({
    required String role,
    required int amountCents,
    String currency = 'usd',
    String payoutMethod = 'standard',
  }) async {
    final res = await _client.functions.invoke(
      'request-payout',
      body: {
        'role': role,
        'amount_cents': amountCents,
        'currency': currency,
        'payout_method': payoutMethod,
      },
    );
    _checkError(res);
    return PayoutRequest.fromJson(
      (res.data as Map<String, dynamic>)['payout_request'] as Map<String, dynamic>,
    );
  }

  /// Fetch payout history for the current user from Supabase.
  Future<List<PayoutRequest>> getPayoutHistory({
    required String userId,
    required String role,
    int limit = 50,
  }) async {
    final rows = await _client
        .from('stripe_payout_requests')
        .select('*')
        .eq('user_id', userId)
        .eq('role', role)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((r) => PayoutRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  /// Admin: approve a payout request.
  Future<PayoutRequest> approvePayout({
    required String payoutRequestId,
    String? adminNote,
  }) async {
    final res = await _client.functions.invoke(
      'approve-payout-request',
      body: {
        'payout_request_id': payoutRequestId,
        'admin_note': adminNote,
      },
    );
    _checkError(res);
    return PayoutRequest.fromJson(
      (res.data as Map<String, dynamic>)['payout_request'] as Map<String, dynamic>,
    );
  }

  /// Admin: reject a payout request. admin_note is required.
  Future<void> rejectPayout({
    required String payoutRequestId,
    required String adminNote,
  }) async {
    final res = await _client.functions.invoke(
      'reject-payout-request',
      body: {
        'payout_request_id': payoutRequestId,
        'admin_note': adminNote,
      },
    );
    _checkError(res);
  }

  /// Admin: retry a failed payout.
  Future<PayoutRequest> retryPayout({required String payoutRequestId}) async {
    final res = await _client.functions.invoke(
      'retry-payout-request',
      body: {'payout_request_id': payoutRequestId},
    );
    _checkError(res);
    return PayoutRequest.fromJson(
      (res.data as Map<String, dynamic>)['payout_request'] as Map<String, dynamic>,
    );
  }

  /// Admin: fetch all payout requests, optionally filtered by status.
  Future<List<PayoutRequest>> getAllPayoutRequests({
    String? status,
    int limit = 100,
  }) async {
    dynamic query = _client.from('stripe_payout_requests').select('*');
    if (status != null) {
      query = (query as dynamic).eq('status', status);
    }
    final rows = await (query as dynamic)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((r) => PayoutRequest.fromJson(r as Map<String, dynamic>))
        .toList();
  }

  void _checkError(FunctionResponse res) {
    final data = res.data;
    if (data is Map && data.containsKey('error')) {
      throw Exception(data['error']);
    }
  }
}

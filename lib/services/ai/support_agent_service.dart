import 'package:supabase_flutter/supabase_flutter.dart';

/// Client for the AI Support Agent edge functions (support-agent-draft,
/// support-agent-approve). Both require an admin JWT — enforced server-side.
class SupportAgentService {
  final SupabaseClient _client;

  SupportAgentService(this._client);

  Future<Map<String, dynamic>> generateDraft(String supportRequestId) async {
    final res = await _client.functions.invoke(
      'support-agent-draft',
      body: {'support_request_id': supportRequestId},
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<Map<String, dynamic>> approve({
    required String supportRequestId,
    required String finalReply,
    bool executeCredit = false,
  }) async {
    final res = await _client.functions.invoke(
      'support-agent-approve',
      body: {
        'support_request_id': supportRequestId,
        'decision': 'approve',
        'final_reply': finalReply,
        'execute_credit': executeCredit,
      },
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
    return Map<String, dynamic>.from(data as Map);
  }

  Future<void> reject(String supportRequestId) async {
    final res = await _client.functions.invoke(
      'support-agent-approve',
      body: {'support_request_id': supportRequestId, 'decision': 'reject'},
    );
    final data = res.data;
    if (data is Map && data['error'] != null) {
      throw Exception(data['error'].toString());
    }
  }
}

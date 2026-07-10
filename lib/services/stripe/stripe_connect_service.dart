import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/stripe/connected_account_model.dart';

class StripeConnectService {
  StripeConnectService(this._client);
  final SupabaseClient _client;

  /// Create a new Stripe Express connected account for the user.
  /// If one already exists for this user+role, returns it without creating a duplicate.
  Future<ConnectedAccount> createConnectAccount({
    required String role,
    String country = 'US',
    String currency = 'usd',
  }) async {
    final res = await _client.functions.invoke(
      'create-connect-account',
      body: {'role': role, 'country': country, 'currency': currency},
    );
    _checkError(res);
    return ConnectedAccount.fromJson(
      (res.data as Map<String, dynamic>)['account'] as Map<String, dynamic>,
    );
  }

  /// Generate a Stripe Account Link URL for onboarding.
  Future<String> createAccountLink({required String role}) async {
    final res = await _client.functions.invoke(
      'create-account-link',
      body: {'role': role},
    );
    _checkError(res);
    return (res.data as Map<String, dynamic>)['url'] as String;
  }

  /// Refresh the connected account status from Stripe and persist to Supabase.
  Future<Map<String, dynamic>> refreshConnectAccount({required String role}) async {
    final res = await _client.functions.invoke(
      'refresh-connect-account',
      body: {'role': role},
    );
    _checkError(res);
    return res.data as Map<String, dynamic>;
  }

  /// Read the connected account row directly from Supabase (no Stripe API call).
  Future<ConnectedAccount?> getConnectedAccount({
    required String userId,
    required String role,
  }) async {
    final res = await _client
        .from('stripe_connected_accounts')
        .select('*')
        .eq('user_id', userId)
        .eq('role', role)
        .maybeSingle();
    if (res == null) return null;
    return ConnectedAccount.fromJson(res);
  }

  /// Subscribe to real-time changes for a connected account row.
  Stream<ConnectedAccount?> watchConnectedAccount({
    required String userId,
    required String role,
  }) {
    return _client
        .from('stripe_connected_accounts')
        .stream(primaryKey: ['id'])
        .eq('user_id', userId)
        .map((rows) {
          final match = rows.cast<Map<String, dynamic>>().where(
                (r) => r['role'] == role,
              );
          if (match.isEmpty) return null;
          return ConnectedAccount.fromJson(match.first);
        });
  }

  void _checkError(FunctionResponse res) {
    final data = res.data;
    if (data is Map && data.containsKey('error')) {
      throw Exception(data['error']);
    }
  }
}

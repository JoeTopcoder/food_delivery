import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/supabase_config.dart';

class DelayedStripeConnectService {
  DelayedStripeConnectService({SupabaseClient? client})
    : _client = client ?? SupabaseConfig.client;

  final SupabaseClient _client;

  Future<bool> ensureConnectedForDriverPayout() async {
    final response = await _client.functions.invoke(
      'stripe-connect',
      body: {'action': 'onboard'},
    );

    if (response.status >= 400) {
      throw Exception('Could not start Stripe onboarding');
    }

    final data = response.data as Map<String, dynamic>?;
    final url = data?['url'] as String?;
    if (url == null || url.isEmpty) {
      throw Exception('Missing onboarding URL');
    }

    final uri = Uri.parse(url);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool shouldPromptRestaurantPayoutSetup({
    required bool hasReceivedOrder,
    required String? stripeAccountId,
  }) {
    return hasReceivedOrder &&
        (stripeAccountId == null || stripeAccountId.isEmpty);
  }
}

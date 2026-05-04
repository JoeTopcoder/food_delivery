import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/loyalty_model.dart';
import '../services/loyalty_service.dart';

final loyaltyServiceProvider = Provider<LoyaltyService>((ref) {
  return LoyaltyService(Supabase.instance.client);
});

final loyaltyAccountProvider = FutureProvider.family<LoyaltyAccount?, String>((
  ref,
  userId,
) {
  return ref.watch(loyaltyServiceProvider).getAccount(userId);
});

final loyaltyTransactionsProvider =
    FutureProvider.family<List<LoyaltyTransaction>, String>((ref, userId) {
      return ref.watch(loyaltyServiceProvider).getTransactions(userId);
    });

/// How many points the user is choosing to redeem (0 = none)
final redeemPointsProvider = StateProvider<int>((ref) => 0);

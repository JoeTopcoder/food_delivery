import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/earning_model.dart';
import '../services/earning_service.dart';

/// Core service provider
final earningServiceProvider = Provider<EarningService>((ref) {
  return EarningService(Supabase.instance.client);
});

/// Earning account for the current user
final earningAccountProvider = FutureProvider.autoDispose.family<EarningAccount?, String>((
  ref,
  userId,
) async {
  return ref.watch(earningServiceProvider).getAccount(userId);
});

/// Earning transactions history
final earningTransactionsProvider =
    FutureProvider.autoDispose.family<List<EarningTransaction>, String>((
      ref,
      userId,
    ) async {
      return ref.watch(earningServiceProvider).getTransactions(userId);
    });

/// Direct referrals with order counts
final earningReferralsProvider =
    FutureProvider.autoDispose.family<List<Map<String, dynamic>>, String>((
      ref,
      userId,
    ) async {
      return ref.watch(earningServiceProvider).getDirectReferrals(userId);
    });

/// Admin: all earning accounts
final allEarningAccountsProvider = FutureProvider.autoDispose<List<EarningAccount>>((
  ref,
) async {
  return ref.watch(earningServiceProvider).getAllAccounts();
});

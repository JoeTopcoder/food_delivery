import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/promo_model.dart';
import '../services/promo_service.dart';

final promoServiceProvider = Provider<PromoService>((ref) {
  return PromoService(Supabase.instance.client);
});

/// All promo codes (admin)
final allPromosProvider = FutureProvider.autoDispose<List<PromoCode>>((ref) {
  return ref.watch(promoServiceProvider).listAll();
});

/// Notifier for the currently applied promo at checkout
class AppliedPromoNotifier extends StateNotifier<PromoCode?> {
  AppliedPromoNotifier() : super(null);
  void apply(PromoCode promo) => state = promo;
  void clear() => state = null;
}

final appliedPromoProvider =
    StateNotifierProvider<AppliedPromoNotifier, PromoCode?>((ref) {
      return AppliedPromoNotifier();
    });

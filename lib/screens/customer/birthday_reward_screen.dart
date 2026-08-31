import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../models/promo_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/promo_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_feedback_widgets.dart';

/// Deep-link target for the birthday push notification, and the destination
/// of the home-screen birthday banner. Shows the customer's birthday reward
/// code and its live status. Status (available/used/expired) is always read
/// live from the linked promo_codes row — nothing here duplicates that state.
class BirthdayRewardScreen extends ConsumerStatefulWidget {
  /// Pre-known code, e.g. passed straight from the notification payload.
  /// When null, the screen looks up the current user's most recent birthday
  /// reward itself (e.g. when opened from the home-screen banner).
  final String? promoCode;

  const BirthdayRewardScreen({super.key, this.promoCode});

  @override
  ConsumerState<BirthdayRewardScreen> createState() =>
      _BirthdayRewardScreenState();
}

class _BirthdayRewardScreenState extends ConsumerState<BirthdayRewardScreen> {
  late Future<PromoCode?> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<PromoCode?> _load() async {
    final promoService = ref.read(promoServiceProvider);
    if (widget.promoCode != null) {
      return promoService.getByCode(widget.promoCode!);
    }
    // Opened without a code (e.g. from the home banner) — find today's
    // birthday_rewards row for this user and follow it to the promo code.
    final userId = ref.read(currentUserIdProvider);
    if (userId == null) return null;
    final row = await Supabase.instance.client
        .from('birthday_rewards')
        .select('promo_codes(code)')
        .eq('user_id', userId)
        .order('birthday_date', ascending: false)
        .limit(1)
        .maybeSingle();
    final code = (row?['promo_codes'] as Map<String, dynamic>?)?['code'] as String?;
    if (code == null) return null;
    return promoService.getByCode(code);
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = ref.watch(currentUserProvider);
    final firstName = (currentUser?.name ?? 'there').split(' ').first;
    final c = AppConstants.currencySymbol;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: const Text('Birthday Reward'),
        elevation: 0,
      ),
      body: FutureBuilder<PromoCode?>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final promo = snapshot.data;
          if (promo == null) {
            return const AppErrorState(
              message: "We couldn't find a birthday reward for you right now.",
            );
          }

          final isUsed = promo.usedCount > 0;
          final isExpired =
              promo.expiresAt != null && DateTime.now().isAfter(promo.expiresAt!);
          final isAvailable = !isUsed && !isExpired && promo.isActive;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                const SizedBox(height: 12),
                const Text('🎂', style: TextStyle(fontSize: 56)),
                const SizedBox(height: 12),
                Text(
                  isUsed
                      ? 'Birthday Reward Used'
                      : isExpired
                      ? 'Birthday Reward Expired'
                      : 'Happy Birthday, $firstName!',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                Text(
                  isUsed
                      ? 'You already used your birthday reward. Happy Birthday from 7Dash ❤️'
                      : isExpired
                      ? 'This reward was only valid on your birthday.'
                      : 'Celebrate your special day with 7Dash ❤️',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [AppTheme.primaryColor, AppTheme.accentColor],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      Text(
                        promo.discountType == 'percentage'
                            ? '${promo.discountValue.toStringAsFixed(0)}% OFF'
                            : '$c${promo.discountValue.toStringAsFixed(0)} OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (promo.minOrderAmount != null && promo.minOrderAmount! > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Minimum order: $c${promo.minOrderAmount!.toStringAsFixed(0)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: isAvailable
                            ? () {
                                Clipboard.setData(ClipboardData(text: promo.code));
                                AppSnackbar.success(context, 'Code copied!');
                              }
                            : null,
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            children: [
                              Text(
                                promo.code,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 3,
                                ),
                              ),
                              if (isAvailable) ...[
                                const SizedBox(height: 4),
                                const Text(
                                  'Tap to copy',
                                  style: TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                      if (promo.expiresAt != null && isAvailable)
                        Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: Text(
                            'Valid today only',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.85),
                              fontSize: 12,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                if (isAvailable)
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).popUntil(
                        (route) => route.isFirst,
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryColor,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Order Now',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

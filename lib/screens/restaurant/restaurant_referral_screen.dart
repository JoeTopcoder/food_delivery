import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/earning_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/earning_provider.dart';
import '../../providers/premium_providers.dart';
import '../../utils/app_feedback_widgets.dart';

class RestaurantReferralScreen extends ConsumerWidget {
  const RestaurantReferralScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    if (user == null) return const SizedBox.shrink();

    final codeAsync = ref.watch(referralCodeProvider(user.id));
    final statsAsync = ref.watch(referralStatsProvider(user.id));
    final referredAsync = ref.watch(referredUsersProvider(user.id));
    final earningAsync = ref.watch(earningAccountProvider(user.id));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Refer a Restaurant'),
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Hero card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0891B2), Color(0xFF0E7490)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.storefront_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Refer Restaurants, Earn Credits!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Refer another restaurant and earn \$${EarningConfig.restaurantRefCredits.toStringAsFixed(0)} in ad credits plus a commission discount!',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Earning summary
            earningAsync.when(
              data: (account) {
                if (account == null) return const SizedBox.shrink();
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFF0891B2).withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0891B2).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.storefront_rounded,
                          color: Color(0xFF0891B2),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '\$${account.totalEarned.toStringAsFixed(2)} in credits earned',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              '\$${EarningConfig.restaurantRefCredits.toStringAsFixed(0)} ad credits + ${(EarningConfig.restaurantRefCommissionDiscount * 100).toStringAsFixed(0)}% commission discount per referral',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[700],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            // Referral code card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 10,
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    'Your Restaurant Referral Code',
                    style: TextStyle(fontSize: 14, color: Colors.grey[700]),
                  ),
                  const SizedBox(height: 8),
                  codeAsync.when(
                    data: (code) => Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          code ?? 'N/A',
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 4,
                            color: Color(0xFF0891B2),
                          ),
                        ),
                        if (code != null) ...[
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: Color(0xFF0891B2),
                            ),
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: code));
                              AppSnackbar.success(context, 'Code copied!');
                            },
                          ),
                        ],
                      ],
                    ),
                    loading: () => const AppLoadingIndicator(fullScreen: false),
                    error: (_, _) => const Text('Error loading code'),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 12),

            // Share button
            codeAsync.when(
              data: (code) => code != null
                  ? SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () => Share.share(
                          'List your restaurant on MealHub! Use my referral code $code when you sign up and get \$${EarningConfig.restaurantRefCredits.toStringAsFixed(0)} in ad credits. Download the app now.',
                        ),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text(
                          'Share with Restaurants',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0891B2),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    )
                  : const SizedBox.shrink(),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            // Stats
            statsAsync.when(
              data: (stats) => Row(
                children: [
                  _StatTile(
                    label: 'Total Referrals',
                    value: '${stats['total_referrals'] ?? 0}',
                    icon: Icons.people_outline,
                    color: const Color(0xFF0891B2),
                  ),
                  const SizedBox(width: 12),
                  _StatTile(
                    label: 'Joined',
                    value: '${stats['completed_referrals'] ?? 0}',
                    icon: Icons.check_circle_outline,
                    color: const Color(0xFF10B981),
                  ),
                  const SizedBox(width: 12),
                  _StatTile(
                    label: 'Pending',
                    value: '${stats['pending_referrals'] ?? 0}',
                    icon: Icons.hourglass_empty,
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => const SizedBox.shrink(),
            ),

            const SizedBox(height: 20),

            // How it works
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How It Works',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  const SizedBox(height: 12),
                  _HowItWorksStep(
                    step: '1',
                    text:
                        'Share your referral code with another restaurant owner',
                    color: const Color(0xFF0891B2),
                  ),
                  _HowItWorksStep(
                    step: '2',
                    text:
                        'They register their restaurant on MealHub using your code',
                    color: const Color(0xFF0891B2),
                  ),
                  _HowItWorksStep(
                    step: '3',
                    text:
                        'Both of you earn \$${EarningConfig.restaurantRefCredits.toStringAsFixed(0)} in ad credits and a ${(EarningConfig.restaurantRefCommissionDiscount * 100).toStringAsFixed(0)}% commission discount!',
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Referred restaurants list
            referredAsync.when(
              data: (users) {
                if (users.isEmpty) {
                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(32),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.store_outlined,
                          size: 48,
                          color: Colors.grey[700],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'No referrals yet',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        Text(
                          'Share your code to start earning ad credits!',
                          style: TextStyle(
                            color: Colors.grey[700],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Referred Restaurants',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...users.map((u) => _ReferralTile(data: u)),
                  ],
                );
              },
              loading: () => const AppLoadingIndicator(),
              error: (_, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatTile({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HowItWorksStep extends StatelessWidget {
  final String step;
  final String text;
  final Color color;

  const _HowItWorksStep({
    required this.step,
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: color.withValues(alpha: 0.15),
            child: Text(
              step,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}

class _ReferralTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReferralTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final userData = data['users'] as Map<String, dynamic>?;
    final status = data['status'] as String? ?? 'pending';
    final isCompleted = status == 'completed';

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: isCompleted
                ? const Color(0xFF10B981)
                : Colors.grey.shade300,
            child: Icon(
              isCompleted ? Icons.check : Icons.hourglass_empty,
              color: Colors.white,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  userData?['name'] ?? userData?['email'] ?? 'Unknown',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  isCompleted ? 'Restaurant joined!' : 'Pending sign-up',
                  style: TextStyle(
                    fontSize: 12,
                    color: isCompleted ? const Color(0xFF10B981) : Colors.grey,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

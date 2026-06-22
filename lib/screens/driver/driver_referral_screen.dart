import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../../providers/auth_provider.dart';
import '../../providers/earning_provider.dart';
import '../../providers/premium_providers.dart';
import '../../utils/app_feedback_widgets.dart';

class DriverReferralScreen extends ConsumerWidget {
  const DriverReferralScreen({super.key});

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
        title: const Text('Refer a Driver'),
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
                  colors: [Color(0xFF6366F1), Color(0xFF4F46E5)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  const Icon(
                    Icons.delivery_dining_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Invite Drivers, Earn Rewards!',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Refer a fellow driver and earn a bonus when they complete their first delivery!',
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

            // Earnings CTA
            earningAsync.when(
              data: (account) {
                if (account == null) return const SizedBox.shrink();
                return GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(context, '/driver-earnings-advanced'),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF6366F1,
                            ).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            account.tier == 'leader'
                                ? Icons.emoji_events_rounded
                                : account.tier == 'builder'
                                ? Icons.groups_rounded
                                : Icons.person_rounded,
                            color: const Color(0xFF6366F1),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${account.tierDisplayName} · \$${account.totalEarned.toStringAsFixed(2)} earned',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'Earn a bonus for each driver you refer',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF6366F1),
                        ),
                      ],
                    ),
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
                    'Your Driver Referral Code',
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
                            color: Color(0xFF6366F1),
                          ),
                        ),
                        if (code != null) ...[
                          const SizedBox(width: 12),
                          IconButton(
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: Color(0xFF6366F1),
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
                        onPressed: () => SharePlus.instance.share(ShareParams(
                          text: 'Join MealHub as a delivery driver! Use my referral code $code when you sign up and get a bonus on your first delivery. Download the app now.',
                        )),
                        icon: const Icon(Icons.share_rounded),
                        label: const Text(
                          'Share with Drivers',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6366F1),
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
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(width: 12),
                  _StatTile(
                    label: 'Completed',
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
                    text: 'Share your referral code with another driver',
                    color: const Color(0xFF6366F1),
                  ),
                  _HowItWorksStep(
                    step: '2',
                    text: 'They sign up as a driver using your code',
                    color: const Color(0xFF6366F1),
                  ),
                  _HowItWorksStep(
                    step: '3',
                    text:
                        'Once they complete their first delivery, you both earn a bonus!',
                    color: const Color(0xFF10B981),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Referred drivers list
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
                          Icons.person_add_outlined,
                          size: 48,
                          color: Colors.grey[700],
                        ),
                        SizedBox(height: 8),
                        Text(
                          'No referrals yet',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        Text(
                          'Share your code to start earning!',
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
                      'Referred Drivers',
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
                  isCompleted ? 'First delivery done!' : 'Pending',
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

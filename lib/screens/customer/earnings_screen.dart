import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/earning_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/earning_provider.dart';
import '../../providers/premium_providers.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';

class EarningsScreen extends ConsumerWidget {
  const EarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    final accountAsync = ref.watch(earningAccountProvider(userId));
    final txAsync = ref.watch(earningTransactionsProvider(userId));
    final referralsAsync = ref.watch(earningReferralsProvider(userId));
    final codeAsync = ref.watch(referralCodeProvider(userId));

    return Scaffold(
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: () async {
          ref.invalidate(earningAccountProvider(userId));
          ref.invalidate(earningTransactionsProvider(userId));
          ref.invalidate(earningReferralsProvider(userId));
        },
        child: accountAsync.when(
          loading: () => const Center(
            child: AppLoadingIndicator(message: 'Loading earnings...'),
          ),
          error: (e, _) =>
              Center(child: AppErrorState(message: friendlyError(e))),
          data: (account) {
            final a =
                account ??
                EarningAccount(
                  id: '',
                  userId: userId,
                  createdAt: DateTime.now(),
                  updatedAt: DateTime.now(),
                );
            return CustomScrollView(
              slivers: [
                // ── App bar ──────────────────────────────────────
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  backgroundColor: _tierGradient(a.tier).first,
                  foregroundColor: Colors.white,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: _tierGradient(a.tier),
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(20, 90, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _tierIcon(a.tier),
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${a.tierDisplayName} Level',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '\$${a.totalEarned.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 36,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Total earned · \$${a.monthlyEarned.toStringAsFixed(2)} this month',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.8),
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  title: const Text(
                    'My Earnings',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ── Tier progress card ────────────────────
                        _TierCard(account: a),
                        const SizedBox(height: 16),

                        // ── Stats row ─────────────────────────────
                        Row(
                          children: [
                            _StatChip(
                              label: 'Referrals',
                              value: '${a.totalDirectRefs}',
                              icon: Icons.people_outline,
                              color: const Color(0xFF6366F1),
                            ),
                            const SizedBox(width: 10),
                            _StatChip(
                              label: 'Orders',
                              value: '${a.totalOrdersGenerated}',
                              icon: Icons.receipt_long_outlined,
                              color: const Color(0xFF10B981),
                            ),
                            const SizedBox(width: 10),
                            _StatChip(
                              label: 'This Month',
                              value: '\$${a.monthlyEarned.toStringAsFixed(2)}',
                              icon: Icons.calendar_today_outlined,
                              color: const Color(0xFFF59E0B),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // ── Monthly cap indicator ─────────────────
                        _MonthlyCap(account: a),
                        const SizedBox(height: 16),

                        // ── Share / invite card ───────────────────
                        codeAsync.when(
                          data: (code) => code != null
                              ? _InviteCard(code: code)
                              : const SizedBox.shrink(),
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 16),

                        // ── How it works ──────────────────────────
                        _HowItWorks(tier: a.tier),
                        const SizedBox(height: 20),

                        // ── Your Referrals ────────────────────────
                        const Text(
                          'Your Referrals',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        referralsAsync.when(
                          data: (refs) {
                            if (refs.isEmpty) {
                              return Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.person_add_outlined,
                                      size: 40,
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
                              children: refs
                                  .map((r) => _ReferralTile(data: r))
                                  .toList(),
                            );
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 20),

                        // ── Transaction history ───────────────────
                        const Text(
                          'Earning History',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        txAsync.when(
                          data: (txns) {
                            if (txns.isEmpty) {
                              return Padding(
                                padding: EdgeInsets.symmetric(vertical: 24),
                                child: Center(
                                  child: Text(
                                    'No earnings yet',
                                    style: TextStyle(color: Colors.grey[700]),
                                  ),
                                ),
                              );
                            }
                            return Column(
                              children: txns
                                  .map((t) => _TransactionTile(txn: t))
                                  .toList(),
                            );
                          },
                          loading: () =>
                              const AppLoadingIndicator(fullScreen: false),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  static List<Color> _tierGradient(String tier) {
    switch (tier) {
      case 'leader':
        return const [Color(0xFFD97706), Color(0xFFF59E0B)];
      case 'builder':
        return const [Color(0xFF6366F1), Color(0xFF8B5CF6)];
      default:
        return [AppTheme.primaryColor, Color(0xFFFF8C42)];
    }
  }

  static IconData _tierIcon(String tier) {
    switch (tier) {
      case 'leader':
        return Icons.emoji_events_rounded;
      case 'builder':
        return Icons.groups_rounded;
      default:
        return Icons.person_rounded;
    }
  }
}

// ── Tier card ──────────────────────────────────────────────────────────

class _TierCard extends StatelessWidget {
  final EarningAccount account;
  const _TierCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final refsNeeded = account.refsToNextTier;
    final nextTier = account.nextTierName;
    final isMax = account.tier == 'leader';
    final progress = _tierProgress();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(_tierIcon(), color: _tierColor(), size: 22),
              const SizedBox(width: 8),
              Text(
                '${account.tierDisplayName} Tier',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: _tierColor(),
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _tierColor().withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _tierBenefit(),
                  style: TextStyle(
                    color: _tierColor(),
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          if (!isMax) ...[
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.grey.shade200,
                color: _tierColor(),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '$refsNeeded more referrals to $nextTier',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(
              'Maximum tier reached! You earn on direct + indirect orders + volume bonuses.',
              style: TextStyle(
                color: _tierColor(),
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  double _tierProgress() {
    switch (account.tier) {
      case 'customer':
        return (account.totalDirectRefs / EarningConfig.builderMinRefs).clamp(
          0.0,
          1.0,
        );
      case 'builder':
        return (account.totalDirectRefs / EarningConfig.leaderMinRefs).clamp(
          0.0,
          1.0,
        );
      default:
        return 1.0;
    }
  }

  Color _tierColor() {
    switch (account.tier) {
      case 'leader':
        return const Color(0xFFD97706);
      case 'builder':
        return const Color(0xFF6366F1);
      default:
        return AppTheme.primaryColor;
    }
  }

  IconData _tierIcon() {
    switch (account.tier) {
      case 'leader':
        return Icons.emoji_events_rounded;
      case 'builder':
        return Icons.groups_rounded;
      default:
        return Icons.person_rounded;
    }
  }

  String _tierBenefit() {
    switch (account.tier) {
      case 'leader':
        return '\$0.30 + \$0.10 + bonuses';
      case 'builder':
        return '\$0.30 + \$0.10/order';
      default:
        return '\$0.30/order';
    }
  }
}

// ── Monthly cap bar ────────────────────────────────────────────────────

class _MonthlyCap extends StatelessWidget {
  final EarningAccount account;
  const _MonthlyCap({required this.account});

  @override
  Widget build(BuildContext context) {
    final cap = EarningConfig.monthlyCap;
    final used = account.monthlyEarned;
    final pct = cap > 0 ? (used / cap).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.savings_outlined, size: 16, color: Colors.grey[700]),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'Monthly Cap',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
              Text(
                '\$${used.toStringAsFixed(2)} / \$${cap.toStringAsFixed(0)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              backgroundColor: Colors.grey.shade200,
              color: pct > 0.9
                  ? Colors.red
                  : pct > 0.7
                  ? Colors.orange
                  : const Color(0xFF10B981),
              minHeight: 5,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Invite card ────────────────────────────────────────────────────────

class _InviteCard extends StatelessWidget {
  final String code;
  const _InviteCard({required this.code});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.primaryColor.withValues(alpha: 0.08),
            const Color(0xFFF59E0B).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.primaryColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                Icons.card_giftcard_rounded,
                color: AppTheme.primaryColor,
                size: 20,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Invite & Earn',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              GestureDetector(
                onTap: () {
                  Clipboard.setData(ClipboardData(text: code));
                  AppSnackbar.success(context, 'Code copied!');
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        code,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          letterSpacing: 2,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.copy_rounded,
                        color: Colors.white,
                        size: 14,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'You get \$${EarningConfig.referrerSignupBonus.toStringAsFixed(0)} credit when a friend signs up. '
            'They get \$${EarningConfig.referredFirstOrderBonus.toStringAsFixed(0)} off their first order. '
            'Plus \$${EarningConfig.directOrderRate.toStringAsFixed(2)} every time they order!',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => Share.share(
                'Join MealHub with my code $code and get \$${EarningConfig.referredFirstOrderBonus.toStringAsFixed(0)} off your first order! Download: https://mealhubcayman.com',
              ),
              icon: const Icon(Icons.share_rounded, size: 16),
              label: const Text('Share with Friends'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── How it works ───────────────────────────────────────────────────────

class _HowItWorks extends StatelessWidget {
  final String tier;
  const _HowItWorks({required this.tier});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFF59E0B)),
              SizedBox(width: 6),
              Text(
                'How Earnings Work',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _step('1', 'Invite friends with your referral code'),
          _step(
            '2',
            'You get \$${EarningConfig.referrerSignupBonus.toStringAsFixed(0)} when they sign up & order',
          ),
          _step(
            '3',
            'Earn \$${EarningConfig.directOrderRate.toStringAsFixed(2)} every time they order',
          ),
          if (tier == 'builder' || tier == 'leader')
            _step(
              '4',
              'Earn \$${EarningConfig.indirectOrderRate.toStringAsFixed(2)} from your referrals\' referrals',
            ),
          if (tier == 'leader')
            _step(
              '5',
              'Unlock volume bonuses: \$25 at 300, \$100 at 1K, \$250 at 3K orders/mo',
            ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline,
                  size: 14,
                  color: Color(0xFFF59E0B),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Credits expire in ${EarningConfig.creditExpiryDays} days. '
                    'Usable on orders \$${EarningConfig.minOrderToUse.toStringAsFixed(0)}+. '
                    'Max ${(EarningConfig.maxCreditPct * 100).toInt()}% of order can be paid with credits.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _step(String num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: AppTheme.primaryColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                num,
                style: TextStyle(
                  color: AppTheme.primaryColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 13, height: 1.3),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Stat chip ──────────────────────────────────────────────────────────

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 4,
            ),
          ],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Referral tile ──────────────────────────────────────────────────────

class _ReferralTile extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReferralTile({required this.data});

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String? ?? 'User';
    final email = data['email'] as String? ?? '';
    final orderCount = data['order_count'] as int? ?? 0;
    final joinedRaw = data['joined_at'] as String?;
    final joined = joinedRaw != null
        ? DateFormat.yMMMd().format(DateTime.parse(joinedRaw))
        : '';
    final initial = name.isNotEmpty
        ? name[0].toUpperCase()
        : email[0].toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
            child: Text(
              initial,
              style: TextStyle(
                color: AppTheme.primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  joined,
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '$orderCount orders',
              style: const TextStyle(
                color: Color(0xFF10B981),
                fontWeight: FontWeight.w600,
                fontSize: 11,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Transaction tile ───────────────────────────────────────────────────

class _TransactionTile extends StatelessWidget {
  final EarningTransaction txn;
  const _TransactionTile({required this.txn});

  @override
  Widget build(BuildContext context) {
    final isCredit = txn.isCredit;
    final color = isCredit ? const Color(0xFF10B981) : Colors.red;
    final icon = _typeIcon();
    final date = DateFormat.MMMd().add_jm().format(txn.createdAt.toLocal());
    final expiryInfo = txn.expiresAt != null && !txn.isExpired
        ? ' · Expires ${DateFormat.MMMd().format(txn.expiresAt!)}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 3),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  txn.typeLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '$date$expiryInfo',
                  style: TextStyle(fontSize: 10, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          Text(
            '${isCredit ? '+' : ''}\$${txn.amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  IconData _typeIcon() {
    switch (txn.type) {
      case 'signup_bonus':
        return Icons.person_add_rounded;
      case 'referred_first_order':
        return Icons.card_giftcard_rounded;
      case 'direct_order':
        return Icons.shopping_bag_outlined;
      case 'indirect_order':
        return Icons.groups_rounded;
      case 'volume_bonus':
        return Icons.emoji_events_rounded;
      case 'restaurant_referral':
        return Icons.store_rounded;
      case 'expired':
        return Icons.timer_off_outlined;
      case 'adjustment':
        return Icons.tune_rounded;
      default:
        return Icons.monetization_on_outlined;
    }
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/earning_model.dart';
import '../../providers/earning_provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../config/app_constants.dart';

class AdminEarningsScreen extends ConsumerStatefulWidget {
  const AdminEarningsScreen({super.key});

  @override
  ConsumerState<AdminEarningsScreen> createState() =>
      _AdminEarningsScreenState();
}

class _AdminEarningsScreenState extends ConsumerState<AdminEarningsScreen> {
  bool _isExpiring = false;

  Future<void> _refresh() async {
    ref.invalidate(allEarningAccountsProvider);
  }

  Future<void> _expireCredits() async {
    setState(() => _isExpiring = true);
    try {
      final count = await ref.read(earningServiceProvider).expireOldCredits();
      if (mounted) {
        AppSnackbar.success(context, 'Expired $count credit(s)');
        ref.invalidate(allEarningAccountsProvider);
      }
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _isExpiring = false);
    }
  }

  void _showAdjustDialog(EarningAccount account) {
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Adjust Credits'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'User: ${account.userName ?? account.userId.substring(0, 8)}',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            Text(
              'Current tier: ${account.tierDisplayName}',
              style: TextStyle(fontSize: 13, color: Colors.grey[700]),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: 'Amount (${AppConstants.currencySymbol})',
                hintText: 'e.g. 5.00',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: InputDecoration(
                labelText: 'Reason',
                hintText: 'e.g. Compensation, correction',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                AppSnackbar.warning(ctx, 'Enter a valid amount');
                return;
              }
              Navigator.pop(ctx);
              try {
                await ref
                    .read(earningServiceProvider)
                    .adminAdjustCredit(
                      userId: account.userId,
                      amount: amount,
                      description: descCtrl.text.trim().isEmpty
                          ? 'Admin adjustment'
                          : descCtrl.text.trim(),
                    );
                if (mounted) {
                  AppSnackbar.success(
                    context,
                    'Credited ${AppConstants.currencySymbol}${amount.toStringAsFixed(2)}',
                  );
                  ref.invalidate(allEarningAccountsProvider);
                }
              } catch (e) {
                if (mounted) AppSnackbar.error(context, friendlyError(e));
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColor,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Credit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final accountsAsync = ref.watch(allEarningAccountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Earnings Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: _isExpiring
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.timer_off_rounded),
            tooltip: 'Expire old credits',
            onPressed: _isExpiring ? null : _expireCredits,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppTheme.primaryColor,
        onRefresh: _refresh,
        child: accountsAsync.when(
          loading: () =>
              const Center(child: AppLoadingIndicator(message: 'Loading...')),
          error: (e, _) =>
              Center(child: AppErrorState(message: friendlyError(e))),
          data: (accounts) {
            if (accounts.isEmpty) {
              return Center(
                child: Text(
                  'No earning accounts yet',
                  style: TextStyle(color: Colors.grey[700]),
                ),
              );
            }

            // Summary stats
            final totalEarned = accounts.fold<double>(
              0,
              (s, a) => s + a.totalEarned,
            );
            final totalRefs = accounts.fold<int>(
              0,
              (s, a) => s + a.totalDirectRefs,
            );
            final leaders = accounts.where((a) => a.tier == 'leader').length;
            final builders = accounts.where((a) => a.tier == 'builder').length;

            return CustomScrollView(
              slivers: [
                // ── Summary header ──────────────────────────────
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppTheme.primaryColor,
                          AppTheme.primaryColor.withValues(alpha: 0.8),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            _SummaryTile(
                              label: 'Total Paid Out',
                              value: '${AppConstants.currencySymbol}${totalEarned.toStringAsFixed(2)}',
                              icon: Icons.payments_outlined,
                            ),
                            _SummaryTile(
                              label: 'Total Referrals',
                              value: '$totalRefs',
                              icon: Icons.people_outline,
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            _SummaryTile(
                              label: 'Leaders',
                              value: '$leaders',
                              icon: Icons.emoji_events_outlined,
                            ),
                            _SummaryTile(
                              label: 'Builders',
                              value: '$builders',
                              icon: Icons.groups_outlined,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Config overview ─────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Current Config',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              _ConfigChip(
                                'Direct',
                                '${AppConstants.currencySymbol}${EarningConfig.directOrderRate}',
                              ),
                              _ConfigChip(
                                'Indirect',
                                '${AppConstants.currencySymbol}${EarningConfig.indirectOrderRate}',
                              ),
                              _ConfigChip(
                                'Signup',
                                '${AppConstants.currencySymbol}${EarningConfig.referrerSignupBonus}',
                              ),
                              _ConfigChip(
                                'Monthly Cap',
                                '${AppConstants.currencySymbol}${EarningConfig.monthlyCap.toInt()}',
                              ),
                              _ConfigChip(
                                'Expiry',
                                '${EarningConfig.creditExpiryDays}d',
                              ),
                              _ConfigChip(
                                'Builder',
                                '${EarningConfig.builderMinRefs} refs',
                              ),
                              _ConfigChip(
                                'Leader',
                                '${EarningConfig.leaderMinRefs} refs',
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),

                // ── Account list ────────────────────────────────
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      '${accounts.length} Earning Accounts',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 8)),
                SliverList(
                  delegate: SliverChildBuilderDelegate((context, index) {
                    final a = accounts[index];
                    return _AccountTile(
                      account: a,
                      onAdjust: () => _showAdjustDialog(a),
                    );
                  }, childCount: accounts.length),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 40)),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Summary tile ───────────────────────────────────────────────────────

class _SummaryTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _SummaryTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Row(
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              Text(
                label,
                style: const TextStyle(color: Colors.white70, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Config chip ────────────────────────────────────────────────────────

class _ConfigChip extends StatelessWidget {
  final String label;
  final String value;
  const _ConfigChip(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppTheme.primaryColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ── Account tile ───────────────────────────────────────────────────────

class _AccountTile extends StatelessWidget {
  final EarningAccount account;
  final VoidCallback onAdjust;
  const _AccountTile({required this.account, required this.onAdjust});

  @override
  Widget build(BuildContext context) {
    final a = account;
    final tierColor = a.tier == 'leader'
        ? const Color(0xFFD97706)
        : a.tier == 'builder'
        ? const Color(0xFF6366F1)
        : AppTheme.primaryColor;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
          // Tier badge
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tierColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              a.tier == 'leader'
                  ? Icons.emoji_events_rounded
                  : a.tier == 'builder'
                  ? Icons.groups_rounded
                  : Icons.person_rounded,
              color: tierColor,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        a.userName ?? a.userId.substring(0, 8),
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: tierColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        a.tierDisplayName,
                        style: TextStyle(
                          color: tierColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${a.totalDirectRefs} refs · ${a.totalOrdersGenerated} orders · ${AppConstants.currencySymbol}${a.monthlyEarned.toStringAsFixed(2)} this mo',
                  style: TextStyle(fontSize: 11, color: Colors.grey[700]),
                ),
              ],
            ),
          ),
          // Total earned
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${AppConstants.currencySymbol}${a.totalEarned.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Color(0xFF10B981),
                ),
              ),
              Text(
                'earned',
                style: TextStyle(fontSize: 10, color: Colors.grey[700]),
              ),
            ],
          ),
          const SizedBox(width: 8),
          // Adjust button
          GestureDetector(
            onTap: onAdjust,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.tune_rounded,
                size: 16,
                color: Colors.grey[700],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

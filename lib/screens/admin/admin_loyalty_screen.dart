import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

// ── Providers ────────────────────────────────────────────────────────────────

final _adminLoyaltyStatsProvider = FutureProvider<Map<String, dynamic>>((
  ref,
) async {
  final client = Supabase.instance.client;

  // Get all loyalty accounts
  final accounts = await client.from('loyalty_accounts').select();
  final accountList = accounts as List;

  // Get all loyalty transactions (recent 200)
  final txns = await client
      .from('loyalty_transactions')
      .select('*, users:user_id(name)')
      .order('created_at', ascending: false)
      .limit(200);
  final txnList = txns as List;

  // Global stats
  int totalPoints = 0, totalEarned = 0, totalRedeemed = 0;
  int bronze = 0, silver = 0, gold = 0, platinum = 0;

  for (final a in accountList) {
    totalPoints += (a['points'] as num?)?.toInt() ?? 0;
    totalEarned += (a['total_earned'] as num?)?.toInt() ?? 0;
    totalRedeemed += (a['total_redeemed'] as num?)?.toInt() ?? 0;
    switch (a['tier'] ?? 'bronze') {
      case 'platinum':
        platinum++;
        break;
      case 'gold':
        gold++;
        break;
      case 'silver':
        silver++;
        break;
      default:
        bronze++;
    }
  }

  // Config values
  final configRows = await client
      .from('app_config')
      .select()
      .like('key', 'loyalty_%');
  final config = <String, String>{};
  for (final row in (configRows as List)) {
    config[row['key'] as String] = row['value'] as String? ?? '';
  }

  return {
    'totalAccounts': accountList.length,
    'totalPointsCirculation': totalPoints,
    'totalEarned': totalEarned,
    'totalRedeemed': totalRedeemed,
    'bronze': bronze,
    'silver': silver,
    'gold': gold,
    'platinum': platinum,
    'recentTransactions': txnList,
    'config': config,
  };
});

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminLoyaltyScreen extends ConsumerWidget {
  const AdminLoyaltyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_adminLoyaltyStatsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      body: CustomScrollView(
        slivers: [
          // ── Header ─────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF1E293B), Color(0xFF334155)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 16, 24),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Loyalty Program',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Master Admin Controls',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.admin_panel_settings_rounded,
                          color: Colors.white,
                          size: 22,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Body ───────────────────────────────────────────
          SliverToBoxAdapter(
            child: statsAsync.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 80),
                child: AppLoadingIndicator(
                  message: 'Loading loyalty program...',
                ),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(24),
                child: AppErrorState(
                  message: friendlyError(e),
                  onRetry: () => ref.invalidate(_adminLoyaltyStatsProvider),
                ),
              ),
              data: (stats) => _AdminLoyaltyBody(stats: stats),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Body ─────────────────────────────────────────────────────────────────────

class _AdminLoyaltyBody extends StatelessWidget {
  final Map<String, dynamic> stats;
  const _AdminLoyaltyBody({required this.stats});

  @override
  Widget build(BuildContext context) {
    final totalAccounts = stats['totalAccounts'] as int;
    final circulating = stats['totalPointsCirculation'] as int;
    final totalEarned = stats['totalEarned'] as int;
    final totalRedeemed = stats['totalRedeemed'] as int;
    final bronze = stats['bronze'] as int;
    final silver = stats['silver'] as int;
    final gold = stats['gold'] as int;
    final platinum = stats['platinum'] as int;
    final recentTxns = stats['recentTransactions'] as List;
    final config = stats['config'] as Map<String, String>;

    final circulatingValue = circulating * AppConstants.loyaltyPointValue;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Points Economy Banner ──────────────────────────
          Transform.translate(
            offset: const Offset(0, -16),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF7C3AED), Color(0xFF9333EA)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF7C3AED).withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.toll_rounded,
                        color: Colors.white70,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Points Economy',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_fmtNum(circulating)} pts in circulation',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Worth ${AppConstants.currencySymbol}${circulatingValue.toStringAsFixed(2)} in potential discounts',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.75),
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _BannerStat(
                        label: 'Accounts',
                        value: _fmtNum(totalAccounts),
                      ),
                      const SizedBox(width: 20),
                      _BannerStat(label: 'Earned', value: _fmtNum(totalEarned)),
                      const SizedBox(width: 20),
                      _BannerStat(
                        label: 'Redeemed',
                        value: _fmtNum(totalRedeemed),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Tier Distribution ───────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.emoji_events_rounded,
                        color: Color(0xFFF59E0B),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Tier Distribution',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _TierCard(
                        label: 'Platinum',
                        count: platinum,
                        color: const Color(0xFF7C3AED),
                        icon: Icons.diamond_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TierCard(
                        label: 'Gold',
                        count: gold,
                        color: const Color(0xFFF59E0B),
                        icon: Icons.workspace_premium_rounded,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _TierCard(
                        label: 'Silver',
                        count: silver,
                        color: const Color(0xFF94A3B8),
                        icon: Icons.military_tech_rounded,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TierCard(
                        label: 'Bronze',
                        count: bronze,
                        color: const Color(0xFFD97706),
                        icon: Icons.shield_rounded,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Program Configuration ──────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF6366F1).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.tune_rounded,
                        color: Color(0xFF6366F1),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Program Configuration',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _ConfigRow(
                  label: 'Point Value',
                  value:
                      '${AppConstants.currencySymbol}${config['loyalty_point_value'] ?? AppConstants.loyaltyPointValue.toString()}/pt',
                  icon: Icons.monetization_on_rounded,
                ),
                const Divider(height: 20),
                _ConfigRow(
                  label: 'Points per ${AppConstants.currencySymbol}100',
                  value:
                      config['loyalty_points_per_100'] ??
                      '${AppConstants.loyaltyPointsPer100}',
                  icon: Icons.calculate_rounded,
                ),
                const Divider(height: 20),
                _ConfigRow(
                  label: 'Max Redemption',
                  value:
                      '${((double.tryParse(config['loyalty_max_redemption_percent'] ?? '') ?? AppConstants.loyaltyMaxRedemptionPercent) * 100).toStringAsFixed(0)}% of order',
                  icon: Icons.percent_rounded,
                ),
                const Divider(height: 20),
                _ConfigRow(
                  label: 'Silver Threshold',
                  value:
                      '${config['loyalty_tier_silver_threshold'] ?? AppConstants.loyaltyTierSilverThreshold} pts',
                  icon: Icons.military_tech_rounded,
                ),
                const Divider(height: 20),
                _ConfigRow(
                  label: 'Gold Threshold',
                  value:
                      '${config['loyalty_tier_gold_threshold'] ?? AppConstants.loyaltyTierGoldThreshold} pts',
                  icon: Icons.workspace_premium_rounded,
                ),
                const Divider(height: 20),
                _ConfigRow(
                  label: 'Platinum Threshold',
                  value:
                      '${config['loyalty_tier_platinum_threshold'] ?? AppConstants.loyaltyTierPlatinumThreshold} pts',
                  icon: Icons.diamond_rounded,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showEditConfigDialog(context),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Edit Configuration'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6366F1),
                      side: const BorderSide(color: Color(0xFF6366F1)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ── Recent Transactions ─────────────────────────────
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      'Recent Transactions',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (recentTxns.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'No loyalty transactions yet',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  )
                else
                  ...recentTxns.take(30).map((t) {
                    final type = t['type'] as String? ?? 'earn';
                    final pts = (t['points'] as num?)?.toInt() ?? 0;
                    final desc = t['description'] as String? ?? '';
                    final usersData = t['users'];
                    final userName = usersData is Map
                        ? usersData['name'] as String?
                        : null;
                    final userId = t['user_id'] as String? ?? '';
                    final date =
                        DateTime.tryParse(t['created_at'] as String? ?? '') ??
                        DateTime.now();
                    final isEarn = type == 'earn';

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color:
                                  (isEarn
                                          ? const Color(0xFF10B981)
                                          : const Color(0xFFEF4444))
                                      .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isEarn
                                  ? Icons.add_circle_outline_rounded
                                  : Icons.remove_circle_outline_rounded,
                              color: isEarn
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                              size: 18,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  desc.isEmpty
                                      ? (isEarn
                                            ? 'Points Earned'
                                            : 'Points Redeemed')
                                      : desc,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF374151),
                                  ),
                                ),
                                Text(
                                  'User: ${userName ?? (userId.length > 8 ? '${userId.substring(0, 8)}...' : userId)} · ${date.month}/${date.day}/${date.year}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${isEarn ? '+' : '-'}${pts.abs()} pts',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: isEarn
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFFEF4444),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  void _showEditConfigDialog(BuildContext context) {
    showDialog(context: context, builder: (_) => const _EditConfigDialog());
  }

  static String _fmtNum(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Edit Config Dialog ───────────────────────────────────────────────────────

class _EditConfigDialog extends ConsumerStatefulWidget {
  const _EditConfigDialog();

  @override
  ConsumerState<_EditConfigDialog> createState() => _EditConfigDialogState();
}

class _EditConfigDialogState extends ConsumerState<_EditConfigDialog> {
  final _pointValueCtrl = TextEditingController(
    text: AppConstants.loyaltyPointValue.toString(),
  );
  final _per100Ctrl = TextEditingController(
    text: AppConstants.loyaltyPointsPer100.toString(),
  );
  final _maxRedemptionCtrl = TextEditingController(
    text: (AppConstants.loyaltyMaxRedemptionPercent * 100).toStringAsFixed(0),
  );
  final _silverCtrl = TextEditingController(
    text: AppConstants.loyaltyTierSilverThreshold.toString(),
  );
  final _goldCtrl = TextEditingController(
    text: AppConstants.loyaltyTierGoldThreshold.toString(),
  );
  final _platCtrl = TextEditingController(
    text: AppConstants.loyaltyTierPlatinumThreshold.toString(),
  );
  bool _saving = false;

  @override
  void dispose() {
    _pointValueCtrl.dispose();
    _per100Ctrl.dispose();
    _maxRedemptionCtrl.dispose();
    _silverCtrl.dispose();
    _goldCtrl.dispose();
    _platCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final updates = {
        'loyalty_point_value': _pointValueCtrl.text.trim(),
        'loyalty_points_per_100': _per100Ctrl.text.trim(),
        'loyalty_max_redemption_percent':
            (double.parse(_maxRedemptionCtrl.text.trim()) / 100).toString(),
        'loyalty_tier_silver_threshold': _silverCtrl.text.trim(),
        'loyalty_tier_gold_threshold': _goldCtrl.text.trim(),
        'loyalty_tier_platinum_threshold': _platCtrl.text.trim(),
      };

      for (final entry in updates.entries) {
        await client
            .from('app_config')
            .update({'value': entry.value})
            .eq('key', entry.key);
      }

      if (mounted) {
        ref.invalidate(_adminLoyaltyStatsProvider);
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Configuration updated'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${friendlyError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: const Row(
        children: [
          Icon(Icons.tune_rounded, color: Color(0xFF6366F1), size: 22),
          SizedBox(width: 8),
          Text(
            'Edit Loyalty Config',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ConfigField(
              label: 'Point Value (\$)',
              controller: _pointValueCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
            ),
            const SizedBox(height: 12),
            _ConfigField(
              label: 'Points per \$100 spent',
              controller: _per100Ctrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _ConfigField(
              label: 'Max Redemption %',
              controller: _maxRedemptionCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _ConfigField(
              label: 'Silver Threshold (pts)',
              controller: _silverCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _ConfigField(
              label: 'Gold Threshold (pts)',
              controller: _goldCtrl,
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 12),
            _ConfigField(
              label: 'Platinum Threshold (pts)',
              controller: _platCtrl,
              keyboardType: TextInputType.number,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6366F1),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Save', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}

class _ConfigField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _ConfigField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(fontSize: 13),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 10,
        ),
        isDense: true,
      ),
    );
  }
}

// ── Widgets ──────────────────────────────────────────────────────────────────

class _BannerStat extends StatelessWidget {
  final String label;
  final String value;
  const _BannerStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

class _TierCard extends StatelessWidget {
  final String label;
  final int count;
  final Color color;
  final IconData icon;

  const _TierCard({
    required this.label,
    required this.count,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
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

class _ConfigRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _ConfigRow({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: const Color(0xFF6366F1), size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

final _webLoyaltyStatsProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final client = Supabase.instance.client;
  final accounts = await client.from('loyalty_accounts').select();
  final txns = await client.from('loyalty_transactions').select('*, users:user_id(name)').order('created_at', ascending: false).limit(100);

  int totalPoints = 0, totalEarned = 0, totalRedeemed = 0;
  int bronze = 0, silver = 0, gold = 0, platinum = 0;
  for (final a in accounts as List) {
    totalPoints += (a['points'] as num?)?.toInt() ?? 0;
    totalEarned += (a['total_earned'] as num?)?.toInt() ?? 0;
    totalRedeemed += (a['total_redeemed'] as num?)?.toInt() ?? 0;
    switch (a['tier'] ?? 'bronze') {
      case 'platinum': platinum++; break;
      case 'gold': gold++; break;
      case 'silver': silver++; break;
      default: bronze++;
    }
  }

  return {
    'totalAccounts': (accounts as List).length,
    'totalPointsCirculation': totalPoints,
    'totalEarned': totalEarned,
    'totalRedeemed': totalRedeemed,
    'bronze': bronze, 'silver': silver, 'gold': gold, 'platinum': platinum,
    'recentTransactions': txns as List,
  };
});

class WebAdminLoyaltyPage extends ConsumerWidget {
  const WebAdminLoyaltyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_webLoyaltyStatsProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Loyalty Program', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Points circulation, tier distribution, and recent transactions', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () => ref.invalidate(_webLoyaltyStatsProvider)),
            ],
          ),
          const SizedBox(height: 24),

          statsAsync.when(
            loading: () => const SizedBox(height: 300, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webLoyaltyStatsProvider)),
            data: (stats) {
              final txns = stats['recentTransactions'] as List;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Stats grid ──────────────────────────────────────
                  Row(children: [
                    Expanded(child: _StatCard(label: 'Members', value: '${stats['totalAccounts']}', icon: Icons.people_rounded, color: const Color(0xFF6366F1))),
                    const SizedBox(width: 14),
                    Expanded(child: _StatCard(label: 'Points in Circulation', value: '${NumberFormat('#,###').format(stats['totalPointsCirculation'])} pts', icon: Icons.stars_rounded, color: const Color(0xFFF59E0B))),
                    const SizedBox(width: 14),
                    Expanded(child: _StatCard(label: 'Total Earned', value: '${NumberFormat('#,###').format(stats['totalEarned'])} pts', icon: Icons.add_circle_outline_rounded, color: const Color(0xFF10B981))),
                    const SizedBox(width: 14),
                    Expanded(child: _StatCard(label: 'Total Redeemed', value: '${NumberFormat('#,###').format(stats['totalRedeemed'])} pts', icon: Icons.redeem_rounded, color: const Color(0xFFEF4444))),
                  ]),
                  const SizedBox(height: 20),

                  // ── Tier distribution ──────────────────────────────
                  const Text('Tier Distribution', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: _TierCard(tier: 'Bronze', count: stats['bronze'], color: const Color(0xFFCD7F32), icon: '🥉')),
                    const SizedBox(width: 12),
                    Expanded(child: _TierCard(tier: 'Silver', count: stats['silver'], color: const Color(0xFF9E9E9E), icon: '🥈')),
                    const SizedBox(width: 12),
                    Expanded(child: _TierCard(tier: 'Gold', count: stats['gold'], color: const Color(0xFFFFD700), icon: '🥇')),
                    const SizedBox(width: 12),
                    Expanded(child: _TierCard(tier: 'Platinum', count: stats['platinum'], color: const Color(0xFF6366F1), icon: '💎')),
                  ]),
                  const SizedBox(height: 20),

                  // ── Recent transactions ────────────────────────────
                  const Text('Recent Transactions', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  const SizedBox(height: 12),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          decoration: const BoxDecoration(color: Color(0xFFF8FAFC), borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
                          child: const Row(children: [
                            SizedBox(width: 160, child: Text('USER', style: _h)),
                            SizedBox(width: 120, child: Text('TYPE', style: _h)),
                            SizedBox(width: 100, child: Text('POINTS', style: _h)),
                            SizedBox(width: 140, child: Text('BALANCE AFTER', style: _h)),
                            Expanded(child: Text('DATE', style: _h, textAlign: TextAlign.right)),
                          ]),
                        ),
                        const Divider(height: 1),
                        txns.isEmpty
                            ? const Padding(padding: EdgeInsets.all(40), child: AppEmptyState(icon: Icons.loyalty_rounded, title: 'No transactions yet'))
                            : ListView.separated(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: txns.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFF1F5F9)),
                                itemBuilder: (_, i) {
                                  final t = txns[i] as Map<String, dynamic>;
                                  final points = (t['points'] as num?)?.toInt() ?? 0;
                                  final type = t['transaction_type'] as String? ?? '';
                                  final isEarn = type == 'earn' || points > 0;
                                  final userName = (t['users'] as Map?)?['name'] as String? ?? 'Unknown';
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    child: Row(children: [
                                      SizedBox(width: 160, child: Text(userName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF374151)))),
                                      SizedBox(
                                        width: 120,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: isEarn ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(20),
                                          ),
                                          child: Text(type.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isEarn ? const Color(0xFF10B981) : const Color(0xFFEF4444))),
                                        ),
                                      ),
                                      SizedBox(
                                        width: 100,
                                        child: Text(
                                          '${isEarn ? '+' : ''}$points',
                                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isEarn ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
                                        ),
                                      ),
                                      SizedBox(width: 140, child: Text('${(t['balance_after'] as num?)?.toInt() ?? 0} pts', style: const TextStyle(fontSize: 13, color: Color(0xFF374151)))),
                                      Expanded(
                                        child: Text(
                                          t['created_at'] != null ? DateFormat('MMM d, y').format(DateTime.parse(t['created_at'] as String)) : '—',
                                          style: const TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                                          textAlign: TextAlign.right,
                                        ),
                                      ),
                                    ]),
                                  );
                                },
                              ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  static const _h = TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF64748B), letterSpacing: 0.5);
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
    ),
    child: Row(children: [
      Container(width: 42, height: 42, decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: color, size: 20)),
      const SizedBox(width: 14),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B))),
        Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
      ])),
    ]),
  );
}

class _TierCard extends StatelessWidget {
  final String tier;
  final int count;
  final Color color;
  final String icon;
  const _TierCard({required this.tier, required this.count, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: color.withValues(alpha: 0.3), width: 1.5),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 6, offset: const Offset(0, 2))],
    ),
    child: Column(children: [
      Text(icon, style: const TextStyle(fontSize: 28)),
      const SizedBox(height: 8),
      Text('$count', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: color)),
      Text(tier, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
    ]),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/loyalty_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebCustomerLoyaltyPage extends ConsumerWidget {
  const WebCustomerLoyaltyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userId = ref.watch(currentUserIdProvider);
    if (userId == null) return const AppLoadingIndicator();

    final accountAsync = ref.watch(loyaltyAccountProvider(userId));
    final txAsync = ref.watch(loyaltyTransactionsProvider(userId));

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Loyalty Points', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
              Text('Earn points and unlock exclusive rewards', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
            ])),
            IconButton(icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)), onPressed: () {
              ref.invalidate(loyaltyAccountProvider(userId));
              ref.invalidate(loyaltyTransactionsProvider(userId));
            }),
          ]),
          const SizedBox(height: 20),

          // Account card
          accountAsync.when(
            loading: () => const SizedBox(height: 130, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e)),
            data: (account) {
              if (account == null) {
                return const Center(child: Text('No loyalty account found', style: TextStyle(color: Color(0xFF94A3B8))));
              }
              return _LoyaltyCard(account: account);
            },
          ),
          const SizedBox(height: 24),

          // Transaction list
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  ),
                  child: const Text('Points History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Expanded(
                  child: txAsync.when(
                    loading: () => const AppLoadingIndicator(),
                    error: (e, _) => AppErrorState(message: friendlyError(e)),
                    data: (txs) {
                      if (txs.isEmpty) return const Center(child: Text('No transactions yet', style: TextStyle(color: Color(0xFF94A3B8))));
                      return ListView.separated(
                        itemCount: txs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        itemBuilder: (_, i) {
                          final tx = txs[i];
                          final isEarn = tx.type == 'earn';
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: isEarn ? const Color(0xFFF59E0B).withValues(alpha: 0.1) : const Color(0xFF6366F1).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(isEarn ? Icons.star_rounded : Icons.redeem_rounded,
                                    color: isEarn ? const Color(0xFFF59E0B) : const Color(0xFF6366F1), size: 18),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tx.description, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                Text(_formatDate(tx.createdAt), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                              ])),
                              Text(
                                '${isEarn ? "+" : "-"}${tx.points} pts',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isEarn ? const Color(0xFFF59E0B) : const Color(0xFF6366F1)),
                              ),
                            ]),
                          );
                        },
                      );
                    },
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime dt) {
    final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }
}

class _LoyaltyCard extends StatelessWidget {
  final dynamic account;
  const _LoyaltyCard({required this.account});

  @override
  Widget build(BuildContext context) {
    final tier = account.tier as String;
    final (tierColor, tierIcon) = switch (tier) {
      'platinum' => (const Color(0xFF8B5CF6), Icons.diamond_rounded),
      'gold'     => (const Color(0xFFF59E0B), Icons.military_tech_rounded),
      'silver'   => (const Color(0xFF94A3B8), Icons.workspace_premium_rounded),
      _          => (const Color(0xFFCD7F32), Icons.emoji_events_rounded),
    };

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [tierColor, tierColor.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: tierColor.withValues(alpha: 0.3), blurRadius: 20, offset: const Offset(0, 6))],
      ),
      child: Row(children: [
        Icon(tierIcon, color: Colors.white, size: 52),
        const SizedBox(width: 20),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tier.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
          Text('${account.points} pts', style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('${account.totalEarned} earned · ${account.totalRedeemed} redeemed', style: const TextStyle(color: Colors.white70, fontSize: 13)),
        ])),
      ]),
    );
  }
}

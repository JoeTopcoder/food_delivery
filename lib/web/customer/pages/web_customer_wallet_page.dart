import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/app_constants.dart';
import '../../../providers/wallet_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';

class WebCustomerWalletPage extends ConsumerWidget {
  const WebCustomerWalletPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final walletAsync = ref.watch(walletBalanceStreamProvider);
    final txAsync = ref.watch(walletTransactionsStreamProvider);

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('My Wallet', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Text('Manage your wallet balance and transactions', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          const SizedBox(height: 20),

          // Balance cards row
          walletAsync.when(
            loading: () => const SizedBox(height: 120, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e)),
            data: (wallet) => Row(children: [
              Expanded(child: _BalanceCard(
                label: 'Available Balance',
                amount: wallet?.balance ?? 0,
                color: const Color(0xFFFF6B35),
                icon: Icons.account_balance_wallet_rounded,
              )),
              const SizedBox(width: 16),
              Expanded(child: _BalanceCard(
                label: 'Cashback Balance',
                amount: wallet?.cashbackBalance ?? 0,
                color: const Color(0xFF10B981),
                icon: Icons.redeem_rounded,
              )),
              const SizedBox(width: 16),
              Expanded(child: _BalanceCard(
                label: 'Outstanding Debt',
                amount: wallet?.debtBalance ?? 0,
                color: const Color(0xFFEF4444),
                icon: Icons.warning_amber_rounded,
              )),
            ]),
          ),
          const SizedBox(height: 24),

          // Transaction history
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
                  ),
                  child: const Row(children: [
                    Text('Transaction History', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                  ]),
                ),
                const Divider(height: 1, color: Color(0xFFE2E8F0)),
                Expanded(
                  child: txAsync.when(
                    loading: () => const AppLoadingIndicator(),
                    error: (e, _) => AppErrorState(message: friendlyError(e)),
                    data: (txs) {
                      if (txs.isEmpty) {
                        return const Center(child: Text('No transactions yet', style: TextStyle(color: Color(0xFF94A3B8))));
                      }
                      return ListView.separated(
                        itemCount: txs.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFE2E8F0)),
                        itemBuilder: (_, i) {
                          final tx = txs[i];
                          final isCredit = tx.amount > 0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            child: Row(children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: isCredit ? const Color(0xFF10B981).withValues(alpha: 0.1) : const Color(0xFFEF4444).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(
                                  isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
                                  color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444),
                                  size: 18,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(tx.description ?? (isCredit ? 'Credit' : 'Debit'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
                                Text(_formatDate(tx.createdAt), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                              ])),
                              Text(
                                '${isCredit ? "+" : ""}${AppConstants.currencySymbol}${tx.amount.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isCredit ? const Color(0xFF10B981) : const Color(0xFFEF4444)),
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

class _BalanceCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _BalanceCard({required this.label, required this.amount, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
          child: Icon(icon, color: color, size: 24),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
          const SizedBox(height: 4),
          Text('${AppConstants.currencySymbol}${amount.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
        ])),
      ]),
    );
  }
}

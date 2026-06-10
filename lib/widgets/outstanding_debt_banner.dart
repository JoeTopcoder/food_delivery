import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/app_constants.dart';
import '../providers/wallet_provider.dart';

/// Reads the current user's outstanding debt from the wallet stream and
/// exposes it as a [double] provider — 0 when there is no debt.
final outstandingDebtProvider = Provider.autoDispose<double>((ref) {
  final wallet = ref.watch(walletBalanceStreamProvider).valueOrNull;
  return wallet?.debtBalance ?? 0;
});

/// Orange warning banner shown on every checkout screen when the customer
/// has an outstanding admin-recorded debt.  The debt amount is included in
/// the checkout grand-total and cleared automatically after payment.
class OutstandingDebtBanner extends ConsumerWidget {
  /// The outstanding debt amount to display.  Pass the value you already
  /// read from [outstandingDebtProvider] so the widget stays pure.
  final double debtAmount;

  const OutstandingDebtBanner({super.key, required this.debtAmount});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (debtAmount <= 0) return const SizedBox.shrink();

    final c = AppConstants.currencySymbol;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFB923C).withValues(alpha: 0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFEA580C),
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontSize: 13,
                  color: Color(0xFF7C2D12),
                  height: 1.4,
                ),
                children: [
                  const TextSpan(
                    text: 'Outstanding balance: ',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  TextSpan(
                    text: '$c${debtAmount.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFEA580C),
                    ),
                  ),
                  const TextSpan(
                    text: ' will be added to your total and cleared with this payment.',
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

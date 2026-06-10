import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../../config/app_constants.dart';
import '../../config/supabase_config.dart';
import '../../utils/app_feedback_widgets.dart';
import '../../utils/friendly_error.dart';

/// Shared bottom-sheet for admin wallet credit / debt adjustments.
/// Used from both AdminUsersScreen and AdminLookupScreen.
class AdminWalletAdjustSheet extends ConsumerStatefulWidget {
  final String userId;
  final String customerName;
  /// Called after a successful adjustment so the caller can refresh its state.
  final VoidCallback? onDone;

  const AdminWalletAdjustSheet({
    super.key,
    required this.userId,
    required this.customerName,
    this.onDone,
  });

  /// Convenience helper: show the sheet and await completion.
  static Future<void> show(
    BuildContext context, {
    required String userId,
    required String customerName,
    VoidCallback? onDone,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => AdminWalletAdjustSheet(
        userId: userId,
        customerName: customerName,
        onDone: onDone,
      ),
    );
  }

  @override
  ConsumerState<AdminWalletAdjustSheet> createState() =>
      _AdminWalletAdjustSheetState();
}

class _AdminWalletAdjustSheetState
    extends ConsumerState<AdminWalletAdjustSheet> {
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  bool _isDebt = false;
  bool _loading = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    if (amount == null || amount <= 0) {
      AppSnackbar.warning(context, 'Enter a valid positive amount');
      return;
    }
    if (_descCtrl.text.trim().isEmpty) {
      AppSnackbar.warning(context, 'Enter a reason / description');
      return;
    }

    setState(() => _loading = true);
    try {
      final adminId = SupabaseConfig.client.auth.currentUser?.id ?? '';
      if (adminId.isEmpty) throw Exception('Not signed in as admin');

      final adjustedAmount = _isDebt ? -amount : amount;
      final c = AppConstants.currencySymbol;

      final result = await SupabaseConfig.client.rpc(
        'admin_wallet_adjust',
        params: {
          'p_user_id': widget.userId,
          'p_amount': adjustedAmount,
          'p_description': _descCtrl.text.trim(),
          'p_admin_id': adminId,
        },
      );

      if (mounted) {
        Navigator.pop(context);

        String message;
        if (!_isDebt) {
          message =
              'Credit of $c${amount.toStringAsFixed(2)} added to wallet';
        } else {
          final data = result as Map<String, dynamic>? ?? {};
          final deducted =
              (data['deducted_now'] as num?)?.toDouble() ?? 0;
          final pending =
              (data['pending_debt'] as num?)?.toDouble() ?? 0;

          if (pending == 0) {
            // Full amount was covered by existing balance
            message =
                '$c${amount.toStringAsFixed(2)} deducted from wallet balance';
          } else if (deducted > 0) {
            // Partial: some deducted now, rest is pending debt
            message =
                '$c${deducted.toStringAsFixed(2)} deducted now · '
                '$c${pending.toStringAsFixed(2)} pending (clears on next top-up)';
          } else {
            // No balance — full amount recorded as pending debt
            message =
                '$c${amount.toStringAsFixed(2)} outstanding — clears on next top-up';
          }
        }

        AppSnackbar.success(context, message);
        widget.onDone?.call();
      }
    } on PostgrestException catch (e) {
      // Show the actual Supabase/Postgres message so admins know exactly what failed.
      if (mounted) AppSnackbar.error(context, e.message);
    } catch (e) {
      if (mounted) AppSnackbar.error(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppConstants.currencySymbol;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          const Text(
            'Wallet Adjustment',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(
            widget.customerName,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 20),

          // Credit / Debt toggle
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isDebt = false),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: !_isDebt
                            ? const Color(0xFF10B981)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.add_circle_rounded,
                            size: 16,
                            color: !_isDebt ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Credit (add funds)',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: !_isDebt ? Colors.white : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _isDebt = true),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      decoration: BoxDecoration(
                        color: _isDebt
                            ? const Color(0xFFEF4444)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.remove_circle_rounded,
                            size: 16,
                            color: _isDebt ? Colors.white : Colors.grey,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Deduct / Outstanding',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: _isDebt ? Colors.white : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Amount field
          TextField(
            controller: _amountCtrl,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Amount',
              prefixText: c,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Description
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Reason / Description',
              hintText: 'e.g. Compensation for service issue',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),

          // Debt info banner
          if (_isDebt) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: Colors.orange.shade700, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Any available balance will be deducted immediately. '
                      'If the balance is insufficient, the remainder is recorded '
                      'as outstanding and cleared on their next top-up.',
                      style: TextStyle(
                          fontSize: 12, color: Colors.orange.shade800),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _loading ? null : _apply,
              style: ElevatedButton.styleFrom(
                backgroundColor: _isDebt
                    ? const Color(0xFFEF4444)
                    : const Color(0xFF10B981),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isDebt
                          ? 'Deduct / Record Outstanding'
                          : 'Add Credit to Wallet',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

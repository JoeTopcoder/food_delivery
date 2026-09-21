import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:food_driver/config/app_constants.dart';

/// Ledger of every movement in a driver's cash float
/// (driver_float_transactions), newest first.
final _floatHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
      ref,
      driverId,
    ) async {
      final rows = await Supabase.instance.client
          .from('driver_float_transactions')
          .select('type, amount, balance_after, note, order_id, created_at')
          .eq('driver_id', driverId)
          .order('created_at', ascending: false)
          .limit(200);
      return (rows as List).cast<Map<String, dynamic>>();
    });

class DriverFloatHistoryScreen extends ConsumerWidget {
  final String driverId;
  final double currentFloat;
  const DriverFloatHistoryScreen({
    super.key,
    required this.driverId,
    required this.currentFloat,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_floatHistoryProvider(driverId));
    final owedToDriver = currentFloat < -0.005;
    final owesPlatform = currentFloat > 0.005;
    final headColor = owesPlatform
        ? const Color(0xFFEF4444)
        : owedToDriver
        ? const Color(0xFF3B82F6)
        : const Color(0xFF22C55E);

    return Scaffold(
      backgroundColor: const Color(0xFF0F1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1117),
        foregroundColor: Colors.white,
        title: const Text('Float History'),
        elevation: 0,
      ),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(_floatHistoryProvider(driverId)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Current balance header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1E2030),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: headColor.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    owedToDriver
                        ? 'HotBite Owes You'
                        : owesPlatform
                        ? 'Cash to Hand Admin'
                        : 'Float Settled',
                    style: TextStyle(
                      color: headColor,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${AppConstants.currencySymbol}${currentFloat.abs().toStringAsFixed(2)}',
                    style: TextStyle(
                      color: headColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 30,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            async.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(
                  child: Text(
                    'Could not load history',
                    style: TextStyle(color: Colors.grey[400]),
                  ),
                ),
              ),
              data: (rows) {
                if (rows.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Center(
                      child: Text(
                        'No float activity yet',
                        style: TextStyle(color: Colors.grey[500]),
                      ),
                    ),
                  );
                }
                return Column(children: _buildGrouped(rows));
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Groups the (newest-first) ledger by calendar day, prefixing each day with
  /// its starting balance (the float before that day's first transaction).
  List<Widget> _buildGrouped(List<Map<String, dynamic>> rows) {
    String dayKey(Map<String, dynamic> tx) {
      final dt = DateTime.tryParse(tx['created_at']?.toString() ?? '')?.toLocal();
      return dt != null ? DateFormat('yyyy-MM-dd').format(dt) : '';
    }

    final widgets = <Widget>[];
    String? currentDay;
    for (int i = 0; i < rows.length; i++) {
      final tx = rows[i];
      final key = dayKey(tx);
      if (key != currentDay) {
        currentDay = key;
        // The day's oldest tx is the LAST row with this key (list is newest-first).
        double startBal = 0;
        DateTime? day;
        for (int j = rows.length - 1; j >= 0; j--) {
          if (dayKey(rows[j]) == key) {
            final bal = (rows[j]['balance_after'] as num?)?.toDouble() ?? 0;
            final amt = (rows[j]['amount'] as num?)?.toDouble() ?? 0;
            startBal = bal - amt;
            day = DateTime.tryParse(rows[j]['created_at']?.toString() ?? '')
                ?.toLocal();
            break;
          }
        }
        widgets.add(_dayHeader(day, startBal));
      }
      widgets.add(_row(tx));
    }
    return widgets;
  }

  Widget _dayHeader(DateTime? day, double startBalance) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Row(
        children: [
          Text(
            day != null ? DateFormat('EEE, MMM d').format(day) : 'Earlier',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const Spacer(),
          Text(
            'Start: ${AppConstants.currencySymbol}${startBalance.toStringAsFixed(2)}',
            style: TextStyle(color: Colors.grey[400], fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _row(Map<String, dynamic> tx) {
    final amount = (tx['amount'] as num?)?.toDouble() ?? 0.0;
    final balanceAfter = (tx['balance_after'] as num?)?.toDouble() ?? 0.0;
    final type = (tx['type'] as String?) ?? '';
    final note = tx['note'] as String?;
    final orderId = tx['order_id']?.toString();
    final orderRef = (orderId != null && orderId.length >= 8)
        ? 'Order #${orderId.substring(0, 8).toUpperCase()}'
        : null;
    final createdAt = DateTime.tryParse(tx['created_at']?.toString() ?? '');
    final positive = amount >= 0;
    final amountColor = positive
        ? const Color(0xFF22C55E)
        : const Color(0xFFF59E0B);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E2030),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF2A2D3E)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(_iconFor(type), color: amountColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _labelFor(type),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (orderRef != null) orderRef,
                    if (createdAt != null)
                      DateFormat('MMM d, h:mm a').format(createdAt.toLocal())
                    else if (note != null)
                      note,
                  ].join('  ·  '),
                  style: TextStyle(color: Colors.grey[500], fontSize: 11),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${positive ? '+' : '-'}${AppConstants.currencySymbol}${amount.abs().toStringAsFixed(2)}',
                style: TextStyle(
                  color: amountColor,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Bal ${AppConstants.currencySymbol}${balanceAfter.toStringAsFixed(2)}',
                style: TextStyle(color: Colors.grey[500], fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String type) {
    switch (type) {
      case 'restaurant_payment':
        return Icons.storefront_rounded;
      case 'cod_collection':
        return Icons.payments_rounded;
      case 'settlement':
        return Icons.account_balance_rounded;
      default:
        return Icons.swap_vert_rounded;
    }
  }

  String _labelFor(String type) {
    switch (type) {
      case 'restaurant_payment':
        return 'Paid restaurant';
      case 'cod_collection':
        return 'Collected cash (COD)';
      case 'settlement':
        return 'Settlement';
      case 'admin_adjust':
        return 'Admin adjustment';
      default:
        return type;
    }
  }
}

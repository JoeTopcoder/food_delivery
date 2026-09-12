import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/app_constants.dart';
import '../../utils/friendly_error.dart';

/// One order's economics, exactly as that order recorded them.
class OrderMargin {
  const OrderMargin({
    required this.orderId,
    required this.restaurantName,
    required this.charged,
    required this.restaurantPaid,
    required this.driverPaid,
    required this.stripeFee,
    required this.netProfit,
    required this.marginPct,
    required this.dataComplete,
    required this.missingFields,
    required this.status,
  });

  final String orderId;
  final String restaurantName;
  final double charged;
  final double restaurantPaid;
  final double driverPaid;
  final double stripeFee;
  final double netProfit;
  final double? marginPct;
  final bool dataComplete;
  final String? missingFields;
  final String status;

  static double _d(dynamic v) => v is num ? v.toDouble() : 0.0;

  factory OrderMargin.fromJson(Map<String, dynamic> j) => OrderMargin(
    orderId: (j['order_id'] ?? '').toString(),
    restaurantName: (j['restaurant_name'] ?? 'Unknown').toString(),
    charged: _d(j['charged']),
    restaurantPaid: _d(j['restaurant_paid']),
    driverPaid: _d(j['driver_paid']),
    stripeFee: _d(j['stripe_fee']),
    netProfit: _d(j['net_profit']),
    marginPct: j['margin_pct'] is num
        ? (j['margin_pct'] as num).toDouble()
        : null,
    dataComplete: j['data_complete'] == true,
    missingFields: j['missing_fields']?.toString(),
    status: (j['status'] ?? '').toString(),
  );
}

final orderMarginsProvider = FutureProvider.autoDispose<List<OrderMargin>>((
  ref,
) async {
  final rows = await Supabase.instance.client.rpc(
    'admin_order_margins',
    params: {'p_limit': 100, 'p_days': 3650},
  );
  if (rows is! List) return const [];
  return rows
      .whereType<Map>()
      .map((r) => OrderMargin.fromJson(Map<String, dynamic>.from(r)))
      .toList();
});

/// Per-order profitability against the 10-25% target band.
///
/// Deliberately refuses to average orders whose payout figures were never
/// recorded. An order with no driver pay and no processor fee reports a ~67%
/// margin, and folding that into a headline number would make the business
/// look most profitable exactly where it is least measured.
class AdminMarginScreen extends ConsumerWidget {
  const AdminMarginScreen({super.key});

  static const _low = 10.0;
  static const _high = 25.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(orderMarginsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Delivery Margins'), centerTitle: true),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(friendlyError(e), textAlign: TextAlign.center),
          ),
        ),
        data: (orders) {
          if (orders.isEmpty) {
            return const Center(child: Text('No orders yet.'));
          }
          final complete = orders.where((o) => o.dataComplete).toList();
          final incomplete = orders.length - complete.length;
          final avg = complete.isEmpty
              ? null
              : complete.map((o) => o.marginPct ?? 0).reduce((a, b) => a + b) /
                    complete.length;
          final inBand = complete
              .where(
                (o) =>
                    (o.marginPct ?? 0) >= _low && (o.marginPct ?? 0) <= _high,
              )
              .length;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(orderMarginsProvider),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              children: [
                _Summary(
                  total: orders.length,
                  measurable: complete.length,
                  incomplete: incomplete,
                  avgMargin: avg,
                  inBand: inBand,
                ),
                const SizedBox(height: 16),
                Text(
                  'Per order',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                for (final o in orders) _OrderRow(order: o),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.total,
    required this.measurable,
    required this.incomplete,
    required this.avgMargin,
    required this.inBand,
  });

  final int total;
  final int measurable;
  final int incomplete;
  final double? avgMargin;
  final int inBand;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final healthy = avgMargin != null && avgMargin! >= 10 && avgMargin! <= 25;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Target 10-25% per delivery',
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 6),
              Text(
                avgMargin == null
                    ? 'Not measurable'
                    : '${avgMargin!.toStringAsFixed(1)}% average',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  height: 1.1,
                  color: avgMargin == null
                      ? scheme.onSurfaceVariant
                      : (healthy
                            ? Colors.green.shade600
                            : Colors.orange.shade700),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                avgMargin == null
                    ? 'None of the last $total orders recorded what was paid out.'
                    : '$inBand of $measurable measurable orders inside the band.',
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),

        // The most important thing on the screen when it applies: a margin from
        // an order that never recorded its payouts is not slightly off, it is
        // meaningless.
        if (incomplete > 0) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade400),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: Colors.orange.shade800,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$incomplete of $total orders cannot be measured',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.orange.shade900,
                          fontSize: 13.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'They never recorded driver pay, processor fee or commission, '
                  'so their apparent margin is far higher than reality. They are '
                  'left out of the average above. Until those fields are written '
                  'when an order is created and delivered, profitability cannot '
                  'be tracked.',
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.35,
                    color: Colors.orange.shade900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderRow extends StatelessWidget {
  const _OrderRow({required this.order});

  final OrderMargin order;

  String _m(double v) =>
      '${AppConstants.currencySymbol}${v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pct = order.marginPct;
    final ok = order.dataComplete && pct != null && pct >= 10 && pct <= 25;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.restaurantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: !order.dataComplete
                      ? Colors.orange.withValues(alpha: 0.15)
                      : (ok
                            ? Colors.green.withValues(alpha: 0.15)
                            : Colors.red.withValues(alpha: 0.12)),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  !order.dataComplete
                      ? 'unmeasurable'
                      : '${pct!.toStringAsFixed(1)}%',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: !order.dataComplete
                        ? Colors.orange.shade900
                        : (ok ? Colors.green.shade700 : Colors.red.shade700),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _line(context, 'Customer charged', _m(order.charged), bold: true),
          _line(context, 'Restaurant', '-${_m(order.restaurantPaid)}'),
          _line(context, 'Driver', '-${_m(order.driverPaid)}'),
          _line(context, 'Processor', '-${_m(order.stripeFee)}'),
          Divider(color: scheme.outlineVariant, height: 14),
          _line(context, 'You keep', _m(order.netProfit), bold: true),
          if (!order.dataComplete && order.missingFields != null) ...[
            const SizedBox(height: 6),
            Text(
              'Not recorded: ${order.missingFields}',
              style: TextStyle(fontSize: 11.5, color: Colors.orange.shade800),
            ),
          ],
        ],
      ),
    );
  }

  Widget _line(
    BuildContext context,
    String label,
    String value, {
    bool bold = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                color: bold ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

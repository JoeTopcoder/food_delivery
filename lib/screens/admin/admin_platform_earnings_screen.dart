import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import '../../utils/friendly_error.dart';
import '../../config/app_constants.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _platformCommissionProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await Supabase.instance.client.rpc('get_platform_commission_summary');
  return (res as Map<String, dynamic>);
});

// ── Screen ───────────────────────────────────────────────────────────────────

class AdminPlatformEarningsScreen extends ConsumerWidget {
  const AdminPlatformEarningsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_platformCommissionProvider);
    final c = AppConstants.currencySymbol;

    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text('Platform Earnings',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppTheme.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(_platformCommissionProvider),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => Center(child: Text(friendlyError(e))),
        data:    (data) {
          final grandTotal  = (data['grand_total']  as num?)?.toDouble() ?? 0;
          final monthTotal  = (data['month_total']  as num?)?.toDouble() ?? 0;
          final food        = data['food']    as Map<String, dynamic>? ?? {};
          final laundry     = data['laundry'] as Map<String, dynamic>? ?? {};
          final car         = data['car']     as Map<String, dynamic>? ?? {};
          final rides       = data['rides']   as Map<String, dynamic>? ?? {};

          double t(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_platformCommissionProvider),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // ── Grand Total Card ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1F2937), Color(0xFF374151)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
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
                              color: AppTheme.primaryColor.withValues(alpha: 0.3),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.account_balance_wallet_rounded,
                                color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 12),
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Total Platform Earnings',
                                  style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text('7Dash Commission — All Services',
                                  style: TextStyle(color: Colors.white54, fontSize: 11)),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '$c${grandTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.calendar_today_rounded,
                              color: Colors.white54, size: 13),
                          const SizedBox(width: 5),
                          Text(
                            'This month: $c${monthTotal.toStringAsFixed(2)}',
                            style: const TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),
                const _SectionLabel('Commission by Service'),
                const SizedBox(height: 12),

                // ── Service breakdown cards ──────────────────────────
                _ServiceCard(
                  icon: Icons.restaurant_rounded,
                  color: const Color(0xFF6366F1),
                  label: 'Food & Grocery',
                  total: t(food, 'total'),
                  month: t(food, 'month'),
                  currencySymbol: c,
                ),
                const SizedBox(height: 10),
                _ServiceCard(
                  icon: Icons.local_laundry_service_rounded,
                  color: const Color(0xFF0F4C81),
                  label: 'Laundry',
                  total: t(laundry, 'total'),
                  month: t(laundry, 'month'),
                  currencySymbol: c,
                ),
                const SizedBox(height: 10),
                _ServiceCard(
                  icon: Icons.car_repair,
                  color: const Color(0xFF7C3AED),
                  label: 'Car Services',
                  total: t(car, 'total'),
                  month: t(car, 'month'),
                  currencySymbol: c,
                ),
                const SizedBox(height: 10),
                _ServiceCard(
                  icon: Icons.directions_car_rounded,
                  color: const Color(0xFF059669),
                  label: 'Rides',
                  total: t(rides, 'total'),
                  month: t(rides, 'month'),
                  currencySymbol: c,
                ),

                const SizedBox(height: 20),
                const _SectionLabel('Share of Total'),
                const SizedBox(height: 12),

                // ── Percentage breakdown ──────────────────────────────
                if (grandTotal > 0) ...[
                  _ShareBar(
                    label: 'Food & Grocery',
                    value: t(food, 'total'),
                    total: grandTotal,
                    color: const Color(0xFF6366F1),
                  ),
                  const SizedBox(height: 8),
                  _ShareBar(
                    label: 'Laundry',
                    value: t(laundry, 'total'),
                    total: grandTotal,
                    color: const Color(0xFF0F4C81),
                  ),
                  const SizedBox(height: 8),
                  _ShareBar(
                    label: 'Car Services',
                    value: t(car, 'total'),
                    total: grandTotal,
                    color: const Color(0xFF7C3AED),
                  ),
                  const SizedBox(height: 8),
                  _ShareBar(
                    label: 'Rides',
                    value: t(rides, 'total'),
                    total: grandTotal,
                    color: const Color(0xFF059669),
                  ),
                ] else
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Center(
                      child: Text('No commission data yet',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),

                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF6B7280),
          letterSpacing: 0.5,
        ),
      );
}

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double total;
  final double month;
  final String currencySymbol;

  const _ServiceCard({
    required this.icon,
    required this.color,
    required this.label,
    required this.total,
    required this.month,
    required this.currencySymbol,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                const SizedBox(height: 2),
                Text(
                  'This month: $currencySymbol${month.toStringAsFixed(2)}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          Text(
            '$currencySymbol${total.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareBar extends StatelessWidget {
  final String label;
  final double value;
  final double total;
  final Color color;

  const _ShareBar({
    required this.label,
    required this.value,
    required this.total,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (value / total).clamp(0.0, 1.0) : 0.0;
    final pctLabel = '${(pct * 100).toStringAsFixed(1)}%';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600)),
              ),
              Text(pctLabel,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 8,
              backgroundColor: color.withValues(alpha: 0.1),
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}

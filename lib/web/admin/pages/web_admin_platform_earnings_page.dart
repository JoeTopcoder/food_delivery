import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/app_constants.dart';
import '../../../utils/app_theme.dart';
import '../../../utils/friendly_error.dart';
import '../../../utils/app_feedback_widgets.dart';

// ── Provider ─────────────────────────────────────────────────────────────────

final _webPlatformCommissionProvider = FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  final res = await Supabase.instance.client.rpc('get_platform_commission_summary');
  return (res as Map<String, dynamic>);
});

// ── Page ─────────────────────────────────────────────────────────────────────

class WebAdminPlatformEarningsPage extends ConsumerWidget {
  const WebAdminPlatformEarningsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_webPlatformCommissionProvider);
    final c = AppConstants.currencySymbol;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ─────────────────────────────────────────────────────
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Platform Earnings', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                    Text('Commission breakdown across all services', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, color: Color(0xFF64748B)),
                onPressed: () => ref.invalidate(_webPlatformCommissionProvider),
              ),
            ],
          ),
          const SizedBox(height: 28),

          async.when(
            loading: () => const SizedBox(height: 300, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(_webPlatformCommissionProvider)),
            data: (data) {
              final grandTotal = (data['grand_total'] as num?)?.toDouble() ?? 0;
              final monthTotal = (data['month_total'] as num?)?.toDouble() ?? 0;
              final food = data['food'] as Map<String, dynamic>? ?? {};
              final laundry = data['laundry'] as Map<String, dynamic>? ?? {};
              final car = data['car'] as Map<String, dynamic>? ?? {};
              final rides = data['rides'] as Map<String, dynamic>? ?? {};
              double t(Map m, String k) => (m[k] as num?)?.toDouble() ?? 0;

              return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                // ── Grand total banner ──────────────────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF1F2937), Color(0xFF374151)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))],
                  ),
                  child: Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: AppTheme.primaryColor.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(Icons.account_balance_wallet_rounded, color: Colors.white, size: 22),
                        ),
                        const SizedBox(width: 12),
                        const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Total Platform Earnings', style: TextStyle(color: Colors.white70, fontSize: 13)),
                          Text('All-time commission across all services', style: TextStyle(color: Colors.white38, fontSize: 11)),
                        ]),
                      ]),
                      const SizedBox(height: 20),
                      Text('$c${grandTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, letterSpacing: -1)),
                    ])),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(children: [
                        const Text('This Month', style: TextStyle(color: Colors.white54, fontSize: 12)),
                        const SizedBox(height: 4),
                        Text('$c${monthTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                ),

                const SizedBox(height: 28),
                const Text('Commission by Service', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
                const SizedBox(height: 16),

                // ── Service cards grid ──────────────────────────────────
                Row(children: [
                  Expanded(child: _ServiceCard(icon: Icons.restaurant_rounded, color: const Color(0xFF6366F1), label: 'Food & Grocery', total: t(food, 'total'), month: t(food, 'month'), sym: c)),
                  const SizedBox(width: 16),
                  Expanded(child: _ServiceCard(icon: Icons.local_laundry_service_rounded, color: const Color(0xFF0F4C81), label: 'Laundry', total: t(laundry, 'total'), month: t(laundry, 'month'), sym: c)),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _ServiceCard(icon: Icons.car_repair_rounded, color: const Color(0xFF7C3AED), label: 'Car Services', total: t(car, 'total'), month: t(car, 'month'), sym: c)),
                  const SizedBox(width: 16),
                  Expanded(child: _ServiceCard(icon: Icons.directions_car_rounded, color: const Color(0xFF2563EB), label: 'Rides / Taxi', total: t(rides, 'total'), month: t(rides, 'month'), sym: c)),
                ]),
              ]);
            },
          ),
        ],
      ),
    );
  }
}

// ── Service Card ─────────────────────────────────────────────────────────────

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final double total;
  final double month;
  final String sym;
  const _ServiceCard({required this.icon, required this.color, required this.label, required this.total, required this.month, required this.sym});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Color(0xFF1E293B))),
        ]),
        const SizedBox(height: 16),
        Text('$sym${total.toStringAsFixed(2)}', style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: color, letterSpacing: -0.5)),
        const SizedBox(height: 4),
        Row(children: [
          const Icon(Icons.calendar_today_rounded, size: 12, color: Color(0xFF94A3B8)),
          const SizedBox(width: 4),
          Text('This month: $sym${month.toStringAsFixed(2)}', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
        ]),
      ]),
    );
  }
}

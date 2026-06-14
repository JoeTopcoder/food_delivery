import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../providers/admin_provider.dart';
import '../../../utils/app_feedback_widgets.dart';
import '../../../utils/friendly_error.dart';
import '../../../config/app_constants.dart';

class WebAdminDashboardPage extends ConsumerWidget {
  const WebAdminDashboardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(adminNewOrderRealtimeProvider);
    ref.watch(adminPendingRealtimeProvider);
    final dashAsync = ref.watch(dashboardSummaryProvider);
    final pendingRestAsync = ref.watch(pendingRestaurantsProvider);
    final pendingDriversAsync = ref.watch(pendingDriversProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────
          const Text('Dashboard', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
          const Text('Platform overview', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
          const SizedBox(height: 28),

          // ── KPI cards ─────────────────────────────────────────────
          dashAsync.when(
            loading: () => const SizedBox(height: 120, child: AppLoadingIndicator()),
            error: (e, _) => AppErrorState(message: friendlyError(e), onRetry: () => ref.invalidate(dashboardSummaryProvider)),
            data: (d) => Column(
              children: [
                Row(children: [
                  Expanded(child: _KpiCard(label: 'Total Users', value: '${d['total_users'] ?? 0}', icon: Icons.people_rounded, color: const Color(0xFF6366F1))),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(label: 'Restaurants', value: '${d['total_restaurants'] ?? 0}', icon: Icons.storefront_rounded, color: const Color(0xFF0EA5E9))),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(label: 'Drivers', value: '${d['total_drivers'] ?? 0}', icon: Icons.delivery_dining_rounded, color: const Color(0xFF10B981))),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(label: 'Total Orders', value: '${d['total_orders'] ?? 0}', icon: Icons.receipt_long_rounded, color: const Color(0xFFF59E0B))),
                ]),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _KpiCard(
                    label: 'Total Revenue',
                    value: '${AppConstants.currencySymbol}${((d['total_revenue'] ?? 0.0) as num).toStringAsFixed(2)}',
                    icon: Icons.attach_money_rounded,
                    color: const Color(0xFF8B5CF6),
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(
                    label: 'Platform Fees',
                    value: '${AppConstants.currencySymbol}${((d['total_platform_fees'] ?? 0.0) as num).toStringAsFixed(2)}',
                    icon: Icons.account_balance_rounded,
                    color: const Color(0xFFEC4899),
                  )),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(label: 'Active Orders', value: '${d['active_orders'] ?? 0}', icon: Icons.pending_actions_rounded, color: const Color(0xFFEF4444))),
                  const SizedBox(width: 16),
                  Expanded(child: _KpiCard(label: 'Delivered Today', value: '${d['delivered_today'] ?? 0}', icon: Icons.check_circle_outline_rounded, color: const Color(0xFF14B8A6))),
                ]),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // ── Needs Attention ───────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Pending restaurants
              Expanded(
                child: _AttentionCard(
                  title: 'Pending Restaurants',
                  icon: Icons.storefront_rounded,
                  color: const Color(0xFFF59E0B),
                  asyncData: pendingRestAsync,
                  emptyText: 'No pending restaurants',
                  itemBuilder: (item) => _AttentionRow(
                    title: item.name,
                    subtitle: item.cuisineType ?? 'No cuisine',
                    badge: 'PENDING',
                    badgeColor: const Color(0xFFF59E0B),
                  ),
                  onRefresh: () => ref.invalidate(pendingRestaurantsProvider),
                ),
              ),
              const SizedBox(width: 20),
              // Pending drivers
              Expanded(
                child: _AttentionCard(
                  title: 'Pending Drivers',
                  icon: Icons.delivery_dining_rounded,
                  color: const Color(0xFF6366F1),
                  asyncData: pendingDriversAsync,
                  emptyText: 'No pending drivers',
                  itemBuilder: (item) => _AttentionRow(
                    title: item.userId,
                    subtitle: item.vehicleType ?? 'No vehicle',
                    badge: 'PENDING',
                    badgeColor: const Color(0xFF6366F1),
                  ),
                  onRefresh: () => ref.invalidate(pendingDriversProvider),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── KPI Card ─────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _KpiCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Color(0xFF1E293B))),
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Attention card ───────────────────────────────────────────────────────────

class _AttentionCard<T> extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final AsyncValue<List<T>> asyncData;
  final String emptyText;
  final Widget Function(T) itemBuilder;
  final VoidCallback onRefresh;

  const _AttentionCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.asyncData,
    required this.emptyText,
    required this.itemBuilder,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: color, size: 18),
              ),
              const SizedBox(width: 10),
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
              const Spacer(),
              IconButton(icon: const Icon(Icons.refresh_rounded, size: 18, color: Color(0xFF94A3B8)), onPressed: onRefresh),
            ],
          ),
          const SizedBox(height: 12),
          asyncData.when(
            loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
            error: (e, _) => Text(friendlyError(e), style: const TextStyle(color: Colors.red, fontSize: 13)),
            data: (items) => items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(child: Text(emptyText, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13))),
                  )
                : Column(children: items.take(5).map(itemBuilder).toList()),
          ),
        ],
      ),
    );
  }
}

class _AttentionRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  final Color badgeColor;

  const _AttentionRow({required this.title, required this.subtitle, required this.badge, required this.badgeColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(badge, style: TextStyle(fontSize: 10, color: badgeColor, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

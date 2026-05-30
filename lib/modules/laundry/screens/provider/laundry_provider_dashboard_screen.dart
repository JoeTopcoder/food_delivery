import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';
import '../../../../config/app_constants.dart';
import 'laundry_provider_orders_screen.dart';
import 'laundry_provider_settings_screen.dart';

class LaundryProviderDashboardScreen extends ConsumerStatefulWidget {
  const LaundryProviderDashboardScreen({super.key});

  @override
  ConsumerState<LaundryProviderDashboardScreen> createState() =>
      _LaundryProviderDashboardScreenState();
}

class _LaundryProviderDashboardScreenState
    extends ConsumerState<LaundryProviderDashboardScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  int _tab = 0;

  static const _kBlue = Color(0xFF0F4C81);

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 5, vsync: this);
    _tabCtrl.addListener(() {
      if (_tabCtrl.indexIsChanging) return;
      setState(() => _tab = _tabCtrl.index);
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(myLaundryProviderProvider);

    return profileAsync.when(
      loading: () => const Scaffold(body: AppLoadingIndicator(message: 'Loading…')),
      error: (e, _) => Scaffold(
        body: AppErrorState(
          message: friendlyError(e),
          onRetry: () => ref.invalidate(myLaundryProviderProvider),
        ),
      ),
      data: (provider) {
        if (provider == null) {
          return _OnboardingPrompt(
            onStart: () => Navigator.pushNamed(context, '/laundry/provider-onboarding'),
          );
        }

        if (provider.status == LaundryProviderStatus.pending) {
          return _PendingApprovalScreen(provider: provider);
        }

        return Scaffold(
          appBar: AppBar(
            backgroundColor: _kBlue,
            foregroundColor: Colors.white,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(provider.businessName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                Text(
                  provider.isActive ? '● Open for orders' : '● Closed',
                  style: TextStyle(
                    fontSize: 11,
                    color: provider.isActive ? Colors.greenAccent : Colors.redAccent,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.settings_rounded),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => LaundryProviderSettingsScreen(provider: provider),
                  ),
                ),
              ),
            ],
            bottom: TabBar(
              controller: _tabCtrl,
              tabs: const [
                Tab(text: 'Overview'),
                Tab(text: 'New'),
                Tab(text: 'Active'),
                Tab(text: 'Completed'),
                Tab(text: 'Earnings'),
              ],
              labelColor: Colors.white,
              unselectedLabelColor: Colors.white60,
              indicatorColor: Colors.white,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
            ),
          ),
          body: IndexedStack(
            index: _tab,
            children: [
              _ProviderOverview(provider: provider),
              LaundryProviderOrdersScreen(
                provider: provider,
                statuses: const ['new_request'],
              ),
              LaundryProviderOrdersScreen(
                provider: provider,
                statuses: const [
                  'accepted', 'pickup_driver_searching', 'pickup_driver_assigned',
                  'waiting_for_pickup', 'picked_up_from_customer',
                  'received_at_laundry', 'weighed', 'price_confirmed',
                  'washing_cleaning', 'quality_check', 'ready_for_delivery',
                  'return_payment_required', 'return_driver_searching',
                  'return_driver_assigned', 'picked_up_for_return', 'out_for_delivery',
                ],
              ),
              LaundryProviderOrdersScreen(
                provider: provider,
                statuses: const ['completed', 'cancelled'],
              ),
              _ProviderEarningsTab(providerId: provider.id),
            ],
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Overview tab
// ─────────────────────────────────────────────────────────────────────────────

class _ProviderOverview extends ConsumerWidget {
  final LaundryProvider provider;
  const _ProviderOverview({required this.provider});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final allAsync = ref.watch(providerLaundryBookingsProvider(
      LaundryProviderBookingParams(provider.id),
    ));

    return allAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e)),
      data: (all) {
        final newCount      = all.where((b) => b.status == LaundryBookingStatus.newRequest).length;
        final activeCount   = all.where((b) => b.status.isActive && b.status != LaundryBookingStatus.newRequest).length;
        final doneCount     = all.where((b) => b.status == LaundryBookingStatus.completed).length;
        final revenue       = all
            .where((b) => b.status == LaundryBookingStatus.completed)
            .fold(0.0, (s, b) => s + (b.actualTotal ?? 0));

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _KpiRow(kpis: [
                _Kpi('New Requests', '$newCount', Icons.inbox_rounded, Colors.orange),
                _Kpi('Active',       '$activeCount', Icons.local_laundry_service_rounded, AppTheme.primaryColor),
              ]),
              const SizedBox(height: 12),
              _KpiRow(kpis: [
                _Kpi('Completed', '$doneCount', Icons.check_circle_rounded, AppTheme.successColor),
                _Kpi('Revenue',
                    '${AppConstants.currencySymbol}${revenue.toStringAsFixed(2)}',
                    Icons.attach_money_rounded, Colors.purple),
              ]),
              const SizedBox(height: 16),
              _StatsCard(
                rating:      provider.rating,
                reviewCount: provider.reviewCount,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _KpiRow extends StatelessWidget {
  final List<_Kpi> kpis;
  const _KpiRow({required this.kpis});

  @override
  Widget build(BuildContext context) => Row(
        children: kpis
            .map((k) => Expanded(child: Padding(
                  padding: EdgeInsets.only(left: kpis.indexOf(k) > 0 ? 8 : 0),
                  child: _KpiCard(kpi: k),
                )))
            .toList(),
      );
}

class _Kpi {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _Kpi(this.label, this.value, this.icon, this.color);
}

class _KpiCard extends StatelessWidget {
  final _Kpi kpi;
  const _KpiCard({required this.kpi});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: kpi.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kpi.color.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(kpi.icon, color: kpi.color, size: 22),
            const SizedBox(height: 8),
            Text(kpi.value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 22, color: kpi.color)),
            Text(kpi.label,
                style: TextStyle(
                    fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
      );
}

class _StatsCard extends StatelessWidget {
  final double rating;
  final int reviewCount;
  const _StatsCard({required this.rating, required this.reviewCount});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
        width: double.infinity,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: [
            const Icon(Icons.star_rounded, color: Colors.amber, size: 28),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rating > 0 ? rating.toStringAsFixed(1) : 'No ratings yet',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
                if (reviewCount > 0)
                  Text('$reviewCount review${reviewCount == 1 ? '' : 's'}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Onboarding / Pending screens
// ─────────────────────────────────────────────────────────────────────────────

class _OnboardingPrompt extends StatelessWidget {
  final VoidCallback onStart;
  const _OnboardingPrompt({required this.onStart});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.local_laundry_service_rounded,
                    size: 80, color: Color(0xFF0F4C81)),
                const SizedBox(height: 24),
                const Text('Become a Laundry Provider',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                const Text(
                  'Register your laundromat to start receiving bookings.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.grey),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: onStart,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F4C81),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Get Started',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}

class _PendingApprovalScreen extends StatelessWidget {
  final LaundryProvider provider;
  const _PendingApprovalScreen({required this.provider});

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(provider.businessName)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.hourglass_top_rounded, size: 72, color: Colors.orange),
                const SizedBox(height: 24),
                const Text('Application Under Review',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                Text(
                  provider.status == LaundryProviderStatus.rejected
                      ? 'Your application was rejected.\n${provider.rejectionReason ?? ''}'
                      : 'Our team is reviewing your application. You\'ll be notified once approved.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Earnings Tab
// ─────────────────────────────────────────────────────────────────────────────

class _ProviderEarningsTab extends ConsumerWidget {
  final String providerId;
  const _ProviderEarningsTab({required this.providerId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final earningsAsync = ref.watch(laundryProviderEarningsProvider(providerId));
    final splitsAsync   = ref.watch(laundryProviderSplitsProvider(providerId));

    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(laundryProviderEarningsProvider(providerId));
        ref.invalidate(laundryProviderSplitsProvider(providerId));
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            earningsAsync.when(
              loading: () => const AppLoadingIndicator(),
              error:   (e, _) => AppErrorState(message: friendlyError(e)),
              data: (data) {
                if (data == null) {
                  return const AppEmptyState(
                    icon: Icons.payments_outlined,
                    title: 'No earnings yet',
                    subtitle: 'Completed bookings will appear here',
                  );
                }
                final c = AppConstants.currencySymbol;
                double v(String k) => (data[k] as num?)?.toDouble() ?? 0;
                return Column(
                  children: [
                    _EarningSummaryCard(
                      label: 'Gross Revenue',
                      value: '$c${v('gross_revenue').toStringAsFixed(2)}',
                      subtitle: '${data['total_orders'] ?? 0} completed orders',
                      color: Colors.blue,
                      icon: Icons.attach_money_rounded,
                    ),
                    const SizedBox(height: 10),
                    _EarningSummaryCard(
                      label: 'Commission Deducted',
                      value: '$c${v('total_commission_deducted').toStringAsFixed(2)}',
                      subtitle: '${((v('effective_commission_rate')) * 100).toStringAsFixed(1)}% rate',
                      color: Colors.orange,
                      icon: Icons.percent_rounded,
                    ),
                    const SizedBox(height: 10),
                    _EarningSummaryCard(
                      label: 'Net Earnings',
                      value: '$c${v('net_earnings').toStringAsFixed(2)}',
                      subtitle: 'After 7Dash commission',
                      color: Colors.green,
                      icon: Icons.account_balance_wallet_rounded,
                    ),
                    const SizedBox(height: 10),
                    _EarningSummaryCard(
                      label: 'Pending Payout',
                      value: '$c${v('pending_payout').toStringAsFixed(2)}',
                      subtitle: 'Awaiting disbursement',
                      color: Colors.purple,
                      icon: Icons.schedule_rounded,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            const Text('Recent Payment Splits',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 12),
            splitsAsync.when(
              loading: () => const AppLoadingIndicator(),
              error:   (e, _) => AppErrorState(message: friendlyError(e)),
              data: (splits) {
                if (splits.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No settled payments yet',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  );
                }
                return ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: splits.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (ctx, i) => _ProviderSplitRow(split: splits[i]),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _EarningSummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;
  const _EarningSummaryCard({
    required this.label, required this.value,
    required this.subtitle, required this.color, required this.icon,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: color)),
          ],
        ),
      );
}

class _ProviderSplitRow extends StatelessWidget {
  final LaundryPaymentSplit split;
  const _ProviderSplitRow({required this.split});

  @override
  Widget build(BuildContext context) {
    final c = AppConstants.currencySymbol;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle_outline_rounded,
                color: Colors.green, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  split.bookingId.substring(0, 8).toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
                Text(
                  'Gross: $c${split.providerGrossAmount.toStringAsFixed(2)}  '
                  'Commission: $c${split.platformCommission.toStringAsFixed(2)}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$c${split.providerNetEarning.toStringAsFixed(2)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14, color: Colors.green)),
              const Text('net', style: TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ],
      ),
    );
  }
}

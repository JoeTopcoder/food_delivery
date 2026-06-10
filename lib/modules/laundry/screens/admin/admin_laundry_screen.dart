import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/index.dart';
import '../../providers/laundry_providers.dart';
import '../../../../utils/app_theme.dart';
import '../../../../utils/app_feedback_widgets.dart';
import '../../../../utils/friendly_error.dart';
import '../../../../config/app_constants.dart';

class AdminLaundryScreen extends ConsumerStatefulWidget {
  const AdminLaundryScreen({super.key});

  @override
  ConsumerState<AdminLaundryScreen> createState() => _AdminLaundryScreenState();
}

class _AdminLaundryScreenState extends ConsumerState<AdminLaundryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laundry Management'),
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Providers'),
            Tab(text: 'Orders'),
            Tab(text: 'Analytics'),
            Tab(text: 'Commission'),
            Tab(text: 'Earnings'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _ProvidersTab(),
          _OrdersTab(),
          _AnalyticsTab(),
          _CommissionTab(),
          _EarningsTab(),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers Tab
// ─────────────────────────────────────────────────────────────────────────────

class _ProvidersTab extends ConsumerStatefulWidget {
  const _ProvidersTab();

  @override
  ConsumerState<_ProvidersTab> createState() => _ProvidersTabState();
}

class _ProvidersTabState extends ConsumerState<_ProvidersTab> {
  LaundryProviderStatus? _filter;

  @override
  Widget build(BuildContext context) {
    final providersAsync = ref.watch(adminLaundryProvidersProvider(_filter));

    return Column(
      children: [
        // Filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              _FilterChip(
                label: 'All',
                selected: _filter == null,
                onTap: () => setState(() => _filter = null),
              ),
              const SizedBox(width: 8),
              ...LaundryProviderStatus.values.map((s) => Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _FilterChip(
                      label: s.displayLabel,
                      selected: _filter == s,
                      onTap: () => setState(() => _filter = s),
                    ),
                  )),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: providersAsync.when(
            loading: () => const AppLoadingIndicator(),
            error: (e, _) => AppErrorState(message: friendlyError(e),
                onRetry: () => ref.invalidate(adminLaundryProvidersProvider(_filter))),
            data: (providers) {
              if (providers.isEmpty) {
                return const AppEmptyState(
                  icon: Icons.local_laundry_service_outlined,
                  title: 'No providers',
                );
              }
              return RefreshIndicator(
                onRefresh: () async =>
                    ref.invalidate(adminLaundryProvidersProvider(_filter)),
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: providers.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) => _AdminProviderTile(
                    provider: providers[i],
                    onApprove: () => _approve(providers[i]),
                    onReject: () => _reject(providers[i]),
                    onSuspend: () => _suspend(providers[i]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _approve(LaundryProvider p) async {
    await ref.read(laundryServiceProvider).approveProvider(p.id);
    ref.invalidate(adminLaundryProvidersProvider(_filter));
    if (mounted) AppSnackbar.success(context, '${p.businessName} approved');
  }

  Future<void> _reject(LaundryProvider p) async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject Provider'),
        content: TextField(
          controller: reasonCtrl,
          decoration: const InputDecoration(labelText: 'Reason'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Reject', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await ref.read(laundryServiceProvider).rejectProvider(p.id, reasonCtrl.text);
      ref.invalidate(adminLaundryProvidersProvider(_filter));
    }
  }

  Future<void> _suspend(LaundryProvider p) async {
    await ref.read(laundryServiceProvider).suspendProvider(p.id);
    ref.invalidate(adminLaundryProvidersProvider(_filter));
    if (mounted) AppSnackbar.success(context, '${p.businessName} suspended');
  }
}

class _AdminProviderTile extends StatelessWidget {
  final LaundryProvider provider;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onSuspend;

  const _AdminProviderTile({
    required this.provider,
    required this.onApprove,
    required this.onReject,
    required this.onSuspend,
  });

  Color get _statusColor {
    switch (provider.status) {
      case LaundryProviderStatus.active:    return AppTheme.successColor;
      case LaundryProviderStatus.pending:   return Colors.orange;
      case LaundryProviderStatus.rejected:  return Colors.red;
      case LaundryProviderStatus.suspended: return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(provider.businessName,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(provider.status.displayLabel,
                    style: TextStyle(fontSize: 11, color: _statusColor, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          if (provider.email != null) ...[
            const SizedBox(height: 4),
            Text(provider.email!, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
          if (provider.address != null) ...[
            const SizedBox(height: 2),
            Text(provider.address!, style: const TextStyle(fontSize: 12, color: Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              if (provider.status == LaundryProviderStatus.pending) ...[
                _ActionBtn('Approve', Colors.green, onApprove),
                const SizedBox(width: 8),
                _ActionBtn('Reject', Colors.red, onReject),
              ],
              if (provider.status == LaundryProviderStatus.active) ...[
                _ActionBtn('Suspend', Colors.orange, onSuspend),
              ],
              if (provider.status == LaundryProviderStatus.suspended) ...[
                _ActionBtn('Re-Approve', Colors.green, onApprove),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(this.label, this.color, this.onTap);

  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.5)),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.primaryColor : Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Orders Tab
// ─────────────────────────────────────────────────────────────────────────────

class _OrdersTab extends ConsumerWidget {
  const _OrdersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bookingsAsync = ref.watch(adminLaundryBookingsProvider);

    return bookingsAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e),
          onRetry: () => ref.invalidate(adminLaundryBookingsProvider)),
      data: (bookings) {
        if (bookings.isEmpty) {
          return const AppEmptyState(
            icon: Icons.inbox_outlined,
            title: 'No laundry orders yet',
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminLaundryBookingsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: bookings.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (ctx, i) {
              final b = bookings[i];
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                leading: Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F4C81).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.local_laundry_service_rounded,
                      color: Color(0xFF0F4C81), size: 20),
                ),
                title: Text(b.bookingNumber,
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                subtitle: Text(
                  '${b.providerName ?? "Provider"}  •  ${b.customerName ?? "Customer"}',
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (b.displayTotal != null)
                      Text('${AppConstants.currencySymbol}${b.displayTotal!.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                    Text(b.status.displayLabel,
                        style: const TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Analytics Tab
// ─────────────────────────────────────────────────────────────────────────────

class _AnalyticsTab extends ConsumerWidget {
  const _AnalyticsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(adminLaundryAnalyticsProvider);

    return analyticsAsync.when(
      loading: () => const AppLoadingIndicator(),
      error: (e, _) => AppErrorState(message: friendlyError(e),
          onRetry: () => ref.invalidate(adminLaundryAnalyticsProvider)),
      data: (data) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(adminLaundryAnalyticsProvider),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _AnalyticCard(
                'Orders Today',
                '${data['orders_today'] ?? 0}',
                Icons.today_rounded,
                Colors.blue,
              ),
              const SizedBox(height: 12),
              _AnalyticCard(
                'Orders This Month',
                '${data['orders_month'] ?? 0}',
                Icons.calendar_month_rounded,
                Colors.purple,
              ),
              const SizedBox(height: 12),
              _AnalyticCard(
                'Revenue This Month',
                '${AppConstants.currencySymbol}${(data['revenue_month'] as double? ?? 0.0).toStringAsFixed(2)}',
                Icons.attach_money_rounded,
                AppTheme.successColor,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnalyticCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _AnalyticCard(this.label, this.value, this.icon, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        width: double.infinity,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26, color: color)),
                Text(label,
                    style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Commission Tab
// ─────────────────────────────────────────────────────────────────────────────

class _CommissionTab extends ConsumerStatefulWidget {
  const _CommissionTab();

  @override
  ConsumerState<_CommissionTab> createState() => _CommissionTabState();
}

class _CommissionTabState extends ConsumerState<_CommissionTab> {
  final _rateCtrl = TextEditingController();
  final _feeCtr   = TextEditingController();
  bool _appliesToDelivery = false;
  bool _saving = false;

  @override
  void dispose() {
    _rateCtrl.dispose();
    _feeCtr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commAsync = ref.watch(laundryDefaultCommissionProvider);

    return commAsync.when(
      loading: () => const AppLoadingIndicator(message: 'Loading commission settings…'),
      error:   (e, _) => AppErrorState(message: friendlyError(e)),
      data: (settings) {
        // Pre-fill once
        if (_rateCtrl.text.isEmpty && settings != null) {
          final v = (settings['commission_value'] as num?)?.toDouble() ?? 0.15;
          _rateCtrl.text = (v * 100).toStringAsFixed(1);
          _feeCtr.text   = (settings['customer_service_fee'] as num?)?.toDouble().toStringAsFixed(2) ?? '1.50';
          _appliesToDelivery = settings['applies_to_delivery_fee'] as bool? ?? false;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Global Laundry Commission',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
              const SizedBox(height: 4),
              Text('These rates apply to all laundry providers unless overridden.',
                  style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),

              // Rate field
              _Label('Commission Rate (%)'),
              const SizedBox(height: 6),
              TextField(
                controller: _rateCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  suffixText: '%',
                  hintText: '15.0',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Service fee
              _Label('Customer Service Fee (${AppConstants.currencySymbol})'),
              const SizedBox(height: 6),
              TextField(
                controller: _feeCtr,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  prefixText: AppConstants.currencySymbol,
                  hintText: '1.50',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                ),
              ),
              const SizedBox(height: 16),

              // Delivery fee toggle
              SwitchListTile.adaptive(
                value: _appliesToDelivery,
                onChanged: (v) => setState(() => _appliesToDelivery = v),
                title: const Text('Commission applies to delivery fees',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('If on, pickup + return fees are also commissionable'),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: const Color(0xFF1565C0),
              ),
              const SizedBox(height: 24),

              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _saving
                      ? const SizedBox(width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                      : const Text('Save Commission Settings',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _save() async {
    final rate = double.tryParse(_rateCtrl.text);
    final fee  = double.tryParse(_feeCtr.text);
    if (rate == null || fee == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enter valid numbers')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(laundryServiceProvider).upsertCommissionSettings(
        commissionType:       'percentage',
        commissionValue:      rate / 100,
        customerServiceFee:   fee,
        appliesToDeliveryFee: _appliesToDelivery,
        isDefault:            true,
      );
      ref.invalidate(laundryDefaultCommissionProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Commission settings saved')));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Earnings Tab
// ─────────────────────────────────────────────────────────────────────────────

class _EarningsTab extends ConsumerWidget {
  const _EarningsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(laundryAdminCommissionAnalyticsProvider);

    return analyticsAsync.when(
      loading: () => const AppLoadingIndicator(message: 'Loading earnings…'),
      error:   (e, _) => AppErrorState(
        message: friendlyError(e),
        onRetry: () => ref.invalidate(laundryAdminCommissionAnalyticsProvider),
      ),
      data: (data) {
        final c = AppConstants.currencySymbol;
        double v(String k) => (data[k] as num?)?.toDouble() ?? 0;

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(laundryAdminCommissionAnalyticsProvider),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _EarningsCard(
                  label: 'Total Gross Sales',
                  value: '$c${v('gross_sales').toStringAsFixed(2)}',
                  icon: Icons.shopping_bag_rounded,
                  color: Colors.blue,
                ),
                const SizedBox(height: 12),
                _EarningsCard(
                  label: '7Dash Commission',
                  value: '$c${v('total_commission').toStringAsFixed(2)}',
                  icon: Icons.percent_rounded,
                  color: Colors.purple,
                ),
                const SizedBox(height: 12),
                _EarningsCard(
                  label: 'Service Fees Collected',
                  value: '$c${v('total_service_fees').toStringAsFixed(2)}',
                  icon: Icons.layers_rounded,
                  color: Colors.teal,
                ),
                const SizedBox(height: 12),
                _EarningsCard(
                  label: 'Total Platform Revenue',
                  value: '$c${v('total_platform_revenue').toStringAsFixed(2)}',
                  icon: Icons.account_balance_rounded,
                  color: Colors.green,
                ),
                const SizedBox(height: 12),
                _EarningsCard(
                  label: 'Provider Payouts',
                  value: '$c${v('total_provider_payouts').toStringAsFixed(2)}',
                  icon: Icons.store_rounded,
                  color: Colors.orange,
                ),
                const SizedBox(height: 12),
                _EarningsCard(
                  label: 'Driver Payouts',
                  value: '$c${v('total_driver_payouts').toStringAsFixed(2)}',
                  icon: Icons.directions_car_rounded,
                  color: Colors.indigo,
                ),
                const SizedBox(height: 12),
                _EarningsCard(
                  label: 'Avg Commission Rate',
                  value: '${((v('avg_commission_rate')) * 100).toStringAsFixed(1)}%',
                  icon: Icons.analytics_rounded,
                  color: Colors.red,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _EarningsCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _EarningsCard({
    required this.label, required this.value,
    required this.icon,  required this.color,
  });

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(16),
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
            const SizedBox(width: 14),
            Expanded(
              child: Text(label,
                  style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
            ),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800, fontSize: 17, color: color)),
          ],
        ),
      );
}

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13));
}

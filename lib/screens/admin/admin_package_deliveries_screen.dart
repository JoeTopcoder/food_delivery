import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../modules/packages/providers/package_providers.dart';

const _kPurple = Color(0xFF7C3AED);

// ── Providers ─────────────────────────────────────────────────────────────────

final _packageOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = Supabase.instance.client;
  final todayMidnight = DateTime.now();
  final midnight = DateTime(todayMidnight.year, todayMidnight.month, todayMidnight.day)
      .toIso8601String();

  final activeRes = await client
      .from('package_delivery_requests')
      .select('id')
      .not('delivery_status', 'in', '("delivered","cancelled","failed")');
  final activeCount = (activeRes as List).length;

  final deliveredTodayRes = await client
      .from('package_delivery_requests')
      .select('id')
      .eq('delivery_status', 'delivered')
      .gte('delivered_at', midnight);
  final deliveredToday = (deliveredTodayRes as List).length;

  int pendingVerification = 0;
  try {
    final verifyRes = await client
        .from('package_records')
        .select('id')
        .eq('verified', false);
    pendingVerification = (verifyRes as List).length;
  } catch (_) {}

  final revenueRes = await client
      .from('package_delivery_requests')
      .select('delivery_fee')
      .eq('delivery_status', 'delivered')
      .gte('delivered_at', midnight);
  double revenueToday = 0.0;
  for (final row in (revenueRes as List)) {
    revenueToday += ((row['delivery_fee'] as num?) ?? 0).toDouble();
  }

  final recentRes = await client
      .from('package_delivery_requests')
      .select('*, shipping_companies(name)')
      .not('delivery_status', 'in', '("delivered","cancelled","failed")')
      .order('created_at', ascending: false)
      .limit(5);
  final recentActive = List<Map<String, dynamic>>.from(recentRes as List);

  return {
    'active_count': activeCount,
    'delivered_today': deliveredToday,
    'pending_verification': pendingVerification,
    'revenue_today': revenueToday,
    'recent_active': recentActive,
  };
});

final _allPackageDeliveriesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, _PackageQuery>((ref, q) async {
  final client = Supabase.instance.client;
  if (q.statusFilter != null) {
    final data = await client
        .from('package_delivery_requests')
        .select('*, shipping_companies(name)')
        .eq('delivery_status', q.statusFilter!)
        .order('created_at', ascending: false)
        .range(q.offset, q.offset + q.limit - 1);
    return List<Map<String, dynamic>>.from(data as List);
  }
  final data = await client
      .from('package_delivery_requests')
      .select('*, shipping_companies(name)')
      .order('created_at', ascending: false)
      .range(q.offset, q.offset + q.limit - 1);
  return List<Map<String, dynamic>>.from(data as List);
});

final _packageRecordsProvider =
    FutureProvider.family<List<Map<String, dynamic>>, bool?>((ref, verifiedFilter) async {
  final client = Supabase.instance.client;
  if (verifiedFilter != null) {
    final data = await client
        .from('package_records')
        .select('*, shipping_companies(name)')
        .eq('verified', verifiedFilter)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(data as List);
  }
  final data = await client
      .from('package_records')
      .select('*, shipping_companies(name)')
      .order('created_at', ascending: false);
  return List<Map<String, dynamic>>.from(data as List);
});

// ── Query value object ────────────────────────────────────────────────────────

class _PackageQuery {
  final int offset;
  final int limit;
  final String? statusFilter;
  const _PackageQuery({this.offset = 0, this.limit = 30, this.statusFilter});

  @override
  bool operator ==(Object other) =>
      other is _PackageQuery &&
      other.offset == offset &&
      other.limit == limit &&
      other.statusFilter == statusFilter;

  @override
  int get hashCode => Object.hash(offset, limit, statusFilter);
}

// ── Hub screen ────────────────────────────────────────────────────────────────

class AdminPackageDeliveriesScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const AdminPackageDeliveriesScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<AdminPackageDeliveriesScreen> createState() =>
      _AdminPackageDeliveriesScreenState();
}

class _AdminPackageDeliveriesScreenState
    extends ConsumerState<AdminPackageDeliveriesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this, initialIndex: widget.initialTab);
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
        title: const Text('Package Deliveries', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'All Deliveries'),
            Tab(text: 'Package Records'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _PkgOverviewTab(),
          _PkgAllDeliveriesTab(),
          _PkgRecordsTab(),
        ],
      ),
    );
  }
}

// ── Tab 1: Overview ───────────────────────────────────────────────────────────

class _PkgOverviewTab extends ConsumerWidget {
  const _PkgOverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_packageOverviewProvider);
    return RefreshIndicator(
      color: _kPurple,
      onRefresh: () async => ref.invalidate(_packageOverviewProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
        error: (e, _) => _PkgErrorRetry(
          message: e.toString(),
          onRetry: () => ref.invalidate(_packageOverviewProvider),
        ),
        data: (data) {
          final recentActive =
              data['recent_active'] as List<Map<String, dynamic>>;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MetricCard(
                    label: 'Active Deliveries',
                    value: '${data['active_count']}',
                    icon: Icons.local_shipping_rounded,
                    color: _kPurple,
                  ),
                  _MetricCard(
                    label: 'Delivered Today',
                    value: '${data['delivered_today']}',
                    icon: Icons.check_circle_rounded,
                    color: Colors.green,
                  ),
                  _MetricCard(
                    label: 'Pending Verify',
                    value: '${data['pending_verification']}',
                    icon: Icons.pending_actions_rounded,
                    color: Colors.orange,
                  ),
                  _MetricCard(
                    label: 'Revenue Today',
                    value: 'J\$${(data['revenue_today'] as double).toStringAsFixed(0)}',
                    icon: Icons.attach_money_rounded,
                    color: const Color(0xFFF59E0B),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (recentActive.isNotEmpty) ...[
                const Text(
                  'Recent Active Deliveries',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 10),
                ...recentActive.map((d) => _ActiveDeliveryRow(delivery: d)),
              ] else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text('No active deliveries.', style: TextStyle(color: Colors.grey)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActiveDeliveryRow extends StatelessWidget {
  final Map<String, dynamic> delivery;
  const _ActiveDeliveryRow({required this.delivery});

  @override
  Widget build(BuildContext context) {
    final companyName = (delivery['shipping_companies'] as Map?)?['name'] as String? ?? 'Unknown';
    final status = delivery['delivery_status'] as String? ?? 'unknown';
    final dest = _truncate(delivery['destination_address'] as String? ?? '', 35);
    final createdAt = _relativeTime(delivery['created_at'] as String?);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _kPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.inventory_2_rounded, color: _kPurple, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(companyName,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 8),
                      _PkgStatusChip(status: status),
                      const SizedBox(width: 8),
                      Text(createdAt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    dest,
                    style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tab 2: All Deliveries ─────────────────────────────────────────────────────

class _PkgAllDeliveriesTab extends ConsumerStatefulWidget {
  const _PkgAllDeliveriesTab();

  @override
  ConsumerState<_PkgAllDeliveriesTab> createState() => _PkgAllDeliveriesTabState();
}

class _PkgAllDeliveriesTabState extends ConsumerState<_PkgAllDeliveriesTab> {
  String? _filterStatus;
  int _loadedCount = 30;
  String? _expandedId;

  static const _filters = [null, 'active', 'delivered', 'cancelled'];
  static const _filterLabels = ['All', 'Active', 'Delivered', 'Cancelled'];

  @override
  Widget build(BuildContext context) {
    final query = _PackageQuery(
      offset: 0,
      limit: _loadedCount,
      statusFilter: _filterStatus == 'active' ? null : _filterStatus,
    );
    final async = ref.watch(_allPackageDeliveriesProvider(query));

    return RefreshIndicator(
      color: _kPurple,
      onRefresh: () async => ref.invalidate(_allPackageDeliveriesProvider(query)),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: _filters.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final selected = _filterStatus == _filters[i];
                return FilterChip(
                  label: Text(_filterLabels[i]),
                  selected: selected,
                  selectedColor: _kPurple.withValues(alpha: 0.15),
                  checkmarkColor: _kPurple,
                  labelStyle: TextStyle(
                    color: selected ? _kPurple : Colors.grey.shade700,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() {
                    _filterStatus = _filters[i];
                    _loadedCount = 30;
                    _expandedId = null;
                  }),
                );
              },
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
              error: (e, _) => _PkgErrorRetry(
                message: e.toString(),
                onRetry: () => ref.invalidate(_allPackageDeliveriesProvider(query)),
              ),
              data: (deliveries) {
                final filtered = _filterStatus == 'active'
                    ? deliveries.where((d) {
                        final s = d['delivery_status'] as String? ?? '';
                        return !['delivered', 'cancelled', 'failed'].contains(s);
                      }).toList()
                    : deliveries;

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No deliveries found.', style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: filtered.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    if (i == filtered.length) {
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: OutlinedButton(
                          onPressed: () => setState(() => _loadedCount += 30),
                          style: OutlinedButton.styleFrom(foregroundColor: _kPurple),
                          child: const Text('Load more'),
                        ),
                      );
                    }
                    final d = filtered[i];
                    return _DeliveryRow(
                      delivery: d,
                      expanded: _expandedId == d['id'],
                      onTap: () => setState(() {
                        _expandedId = _expandedId == d['id'] ? null : d['id'] as String?;
                      }),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _DeliveryRow extends StatelessWidget {
  final Map<String, dynamic> delivery;
  final bool expanded;
  final VoidCallback onTap;
  const _DeliveryRow({required this.delivery, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final companyName = (delivery['shipping_companies'] as Map?)?['name'] as String? ?? 'Unknown';
    final status = delivery['delivery_status'] as String? ?? 'unknown';
    final dest = _truncate(delivery['destination_address'] as String? ?? '', 35);
    final fee = 'J\$${((delivery['delivery_fee'] as num?) ?? 0).toStringAsFixed(2)}';
    final createdAt = _formatDate(delivery['created_at'] as String?);

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(companyName,
                        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ),
                  const SizedBox(width: 6),
                  _PkgStatusChip(status: status),
                  const SizedBox(width: 6),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      dest,
                      style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(fee, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _kPurple)),
                  const SizedBox(width: 8),
                  Text(createdAt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
              if (expanded) ...[
                const Divider(height: 16),
                _PkgDetailRow(label: 'Pickup', value: delivery['pickup_address'] as String? ?? '—'),
                _PkgDetailRow(label: 'Destination', value: delivery['destination_address'] as String? ?? '—'),
                _PkgDetailRow(label: 'Driver ID', value: _shortId(delivery['driver_id'] as String?)),
                _PkgDetailRow(label: 'Fee', value: fee),
                _PkgDetailRow(label: 'Payment', value: delivery['payment_status'] as String? ?? '—'),
                _PkgDetailRow(label: 'Created', value: _formatDate(delivery['created_at'] as String?)),
                if (delivery['delivered_at'] != null)
                  _PkgDetailRow(label: 'Delivered', value: _formatDate(delivery['delivered_at'] as String?)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tab 3: Package Records ────────────────────────────────────────────────────

class _PkgRecordsTab extends ConsumerStatefulWidget {
  const _PkgRecordsTab();

  @override
  ConsumerState<_PkgRecordsTab> createState() => _PkgRecordsTabState();
}

class _PkgRecordsTabState extends ConsumerState<_PkgRecordsTab> {
  // null = all, true = verified, false = unverified
  bool? _verifiedFilter;
  String? _expandedId;
  // Track optimistic verified state changes while re-fetching
  final Map<String, bool> _pendingToggles = {};

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_packageRecordsProvider(_verifiedFilter));

    return RefreshIndicator(
      color: _kPurple,
      onRefresh: () async => ref.invalidate(_packageRecordsProvider(_verifiedFilter)),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              itemCount: 3,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final filters = [null, true, false];
                final labels = ['All', 'Verified', 'Unverified'];
                final selected = _verifiedFilter == filters[i];
                return FilterChip(
                  label: Text(labels[i]),
                  selected: selected,
                  selectedColor: _kPurple.withValues(alpha: 0.15),
                  checkmarkColor: _kPurple,
                  labelStyle: TextStyle(
                    color: selected ? _kPurple : Colors.grey.shade700,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    fontSize: 12,
                  ),
                  onSelected: (_) => setState(() {
                    _verifiedFilter = filters[i];
                    _expandedId = null;
                  }),
                );
              },
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
              error: (e, _) => _PkgErrorRetry(
                message: e.toString(),
                onRetry: () => ref.invalidate(_packageRecordsProvider(_verifiedFilter)),
              ),
              data: (records) {
                if (records.isEmpty) {
                  return const Center(
                    child: Text('No package records found.', style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: records.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final rec = records[i];
                    final id = rec['id'] as String?;
                    final isVerified = _pendingToggles.containsKey(id)
                        ? _pendingToggles[id]!
                        : (rec['verified'] as bool? ?? false);
                    return _PackageRecordRow(
                      record: rec,
                      isVerified: isVerified,
                      expanded: _expandedId == id,
                      onTap: () => setState(() {
                        _expandedId = _expandedId == id ? null : id;
                      }),
                      onToggleVerified: () => _toggleVerified(rec, isVerified),
                      onRetryFetch: () => _retryFetchTracking(rec),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _retryFetchTracking(Map<String, dynamic> record) async {
    final id = record['id'] as String?;
    final companyId = record['shipping_company_id'] as String?;
    if (id == null || companyId == null) return;
    try {
      await ref.read(packageServiceProvider).fetchTrackingNumber(
            shippingCompanyId: companyId,
            packageRecordId: id,
          );
      ref.invalidate(_packageRecordsProvider(_verifiedFilter));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tracking number fetched successfully'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      ref.invalidate(_packageRecordsProvider(_verifiedFilter));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fetch failed: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleVerified(Map<String, dynamic> record, bool currentValue) async {
    final id = record['id'] as String?;
    if (id == null) return;
    final newValue = !currentValue;
    setState(() => _pendingToggles[id] = newValue);
    try {
      await Supabase.instance.client
          .from('package_records')
          .update({'verified': newValue})
          .eq('id', id);
      ref.invalidate(_packageRecordsProvider(_verifiedFilter));
    } catch (e) {
      // Revert on failure
      setState(() => _pendingToggles.remove(id));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _PackageRecordRow extends StatelessWidget {
  final Map<String, dynamic> record;
  final bool isVerified;
  final bool expanded;
  final VoidCallback onTap;
  final VoidCallback onToggleVerified;
  final VoidCallback? onRetryFetch;

  const _PackageRecordRow({
    required this.record,
    required this.isVerified,
    required this.expanded,
    required this.onTap,
    required this.onToggleVerified,
    this.onRetryFetch,
  });

  @override
  Widget build(BuildContext context) {
    final trackingNumber = record['tracking_number'] as String? ?? '—';
    final companyName = (record['shipping_companies'] as Map?)?['name'] as String? ?? 'Unknown';
    final customerName = record['customer_name'] as String? ?? 'Unknown';
    final status = record['package_status'] as String? ?? 'unknown';

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          trackingNumber,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, fontFamily: 'monospace'),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '$companyName · $customerName',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  _PkgStatusChip(status: status),
                  const SizedBox(width: 8),
                  // Verified badge
                  Icon(
                    isVerified ? Icons.verified_rounded : Icons.cancel_rounded,
                    color: isVerified ? Colors.green : Colors.red,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, size: 18, color: Colors.grey),
                ],
              ),
              if (expanded) ...[
                const Divider(height: 16),
                _PkgDetailRow(label: 'Tracking #', value: trackingNumber),
                _PkgDetailRow(label: 'Company', value: companyName),
                _PkgDetailRow(label: 'Customer', value: customerName),
                _PkgDetailRow(label: 'Status', value: status),
                _PkgDetailRow(label: 'Address', value: record['delivery_address'] as String? ?? '—'),
                _PkgDetailRow(label: 'Created', value: _formatDate(record['created_at'] as String?)),
                // ── Tracking fields ────────────────────────────────────────
                if (record['tracking_status'] != null)
                  _PkgDetailRow(
                    label: 'Tracking Status',
                    value: (record['tracking_status'] as String).replaceAll('_', ' ').toUpperCase(),
                    valueColor: _trackingStatusColor(record['tracking_status'] as String),
                  ),
                if (record['tracking_url'] != null)
                  _PkgDetailRow(label: 'Tracking URL', value: record['tracking_url'] as String),
                if (record['external_shipment_id'] != null)
                  _PkgDetailRow(label: 'Shipment ID', value: record['external_shipment_id'] as String),
                if (record['tracking_last_synced_at'] != null)
                  _PkgDetailRow(
                    label: 'Last Synced',
                    value: _formatDate(record['tracking_last_synced_at'] as String?),
                  ),
                if (record['tracking_error_message'] != null) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(
                      record['tracking_error_message'] as String,
                      style: TextStyle(fontSize: 12, color: Colors.red.shade800),
                    ),
                  ),
                ],
                // ── Admin retry button ─────────────────────────────────────
                if (onRetryFetch != null) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onRetryFetch,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: const Text('Retry Fetch Tracking Number',
                          style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _kPurple,
                        side: const BorderSide(color: _kPurple),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Verified',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                        color: isVerified ? Colors.green : Colors.grey.shade700,
                      ),
                    ),
                    Switch(
                      value: isVerified,
                      activeThumbColor: Colors.green,
                      onChanged: (_) => onToggleVerified(),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Shared widgets ─────────────────────────────────────────────────────────────

class _MetricCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  const _MetricCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 22),
            const Spacer(),
            Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

class _PkgStatusChip extends StatelessWidget {
  final String status;
  const _PkgStatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'delivered':
        return Colors.green;
      case 'cancelled':
      case 'failed':
        return Colors.red;
      case 'picked_up':
      case 'in_transit':
      case 'out_for_delivery':
        return const Color(0xFF0EA5E9);
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status,
        style: TextStyle(color: _color, fontSize: 10, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _PkgDetailRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _PkgDetailRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 12,
                    color: valueColor ?? const Color(0xFF1E293B))),
          ),
        ],
      ),
    );
  }
}

Color _trackingStatusColor(String status) {
  switch (status) {
    case 'tracking_active':
      return Colors.green;
    case 'tracking_error':
      return Colors.red;
    case 'tracking_delivered':
      return Colors.blueGrey;
    default:
      return Colors.orange;
  }
}

class _PkgErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _PkgErrorRetry({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: _kPurple, foregroundColor: Colors.white),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _truncate(String s, int max) => s.length > max ? '${s.substring(0, max)}…' : s;

String _shortId(String? id) {
  if (id == null) return '—';
  return id.length > 8 ? id.substring(0, 8) : id;
}

String _relativeTime(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  } catch (_) {
    return '—';
  }
}

String _formatDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day} · $h:$m $ampm';
  } catch (_) {
    return '—';
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:food_driver/config/app_constants.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ── Accent colour used throughout this module ─────────────────────────────────
const _kPurple = Color(0xFF7C3AED);

// ── Providers ─────────────────────────────────────────────────────────────────

final _ridesOverviewProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  final client = Supabase.instance.client;
  final todayStart = DateTime.now();
  final todayMidnight = DateTime(todayStart.year, todayStart.month, todayStart.day)
      .toIso8601String();

  final totalTodayRes = await client
      .from('ride_requests')
      .select('id')
      .gte('created_at', todayMidnight);
  final totalToday = (totalTodayRes as List).length;

  final activeRes = await client
      .from('ride_requests')
      .select('id')
      .not('ride_status', 'in', '("completed","cancelled","failed")');
  final activeCount = (activeRes as List).length;

  final driversOnlineRes = await client
      .from('drivers')
      .select('id')
      .eq('is_available', true);
  final driversOnline = (driversOnlineRes as List).length;

  final revenueRes = await client
      .from('ride_requests')
      .select('fare_amount')
      .eq('ride_status', 'completed')
      .gte('completed_at', todayMidnight);
  double revenueToday = 0.0;
  for (final row in (revenueRes as List)) {
    revenueToday += ((row['fare_amount'] as num?) ?? 0).toDouble();
  }

  final recentActiveRes = await client
      .from('ride_requests')
      .select()
      .not('ride_status', 'in', '("completed","cancelled","failed")')
      .order('created_at', ascending: false)
      .limit(5);
  final recentActive = List<Map<String, dynamic>>.from(recentActiveRes as List);

  return {
    'total_today': totalToday,
    'active_count': activeCount,
    'drivers_online': driversOnline,
    'revenue_today': revenueToday,
    'recent_active': recentActive,
  };
});

final _allRidesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, _RidesQuery>((ref, q) async {
  final client = Supabase.instance.client;
  var query = client
      .from('ride_requests')
      .select('*, users!ride_requests_customer_id_fkey(name)')
      .order('created_at', ascending: false)
      .range(q.offset, q.offset + q.limit - 1);

  if (q.statusFilter != null) {
    query = client
        .from('ride_requests')
        .select('*, users!ride_requests_customer_id_fkey(name)')
        .eq('ride_status', q.statusFilter!)
        .order('created_at', ascending: false)
        .range(q.offset, q.offset + q.limit - 1);
  }

  final data = await query;
  return List<Map<String, dynamic>>.from(data as List);
});

final _ridePricingProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    final data = await Supabase.instance.client
        .from('ride_config')
        .select()
        .eq('id', 'default')
        .maybeSingle();
    if (data == null) {
      return _defaultRideConfig();
    }
    return Map<String, dynamic>.from(data as Map);
  } catch (_) {
    return _defaultRideConfig();
  }
});

Map<String, dynamic> _defaultRideConfig() => {
      'id': 'default',
      'base_fare': 250.0,
      'per_km_rate': 80.0,
      'per_minute_rate': 15.0,
      'minimum_fare': 300.0,
      'peak_multiplier': 1.5,
      'night_surcharge': 1.25,
    };

// ── Query param value object ───────────────────────────────────────────────────

class _RidesQuery {
  final int offset;
  final int limit;
  final String? statusFilter;
  const _RidesQuery({this.offset = 0, this.limit = 30, this.statusFilter});

  @override
  bool operator ==(Object other) =>
      other is _RidesQuery &&
      other.offset == offset &&
      other.limit == limit &&
      other.statusFilter == statusFilter;

  @override
  int get hashCode => Object.hash(offset, limit, statusFilter);
}

// ── Hub screen ────────────────────────────────────────────────────────────────

class AdminRidesScreen extends ConsumerStatefulWidget {
  final int initialTab;
  const AdminRidesScreen({super.key, this.initialTab = 0});

  @override
  ConsumerState<AdminRidesScreen> createState() => _AdminRidesScreenState();
}

class _AdminRidesScreenState extends ConsumerState<AdminRidesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 4, vsync: this, initialIndex: widget.initialTab);
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
        title: const Text('Rides Hub', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: const [
            Tab(text: 'Overview'),
            Tab(text: 'All Rides'),
            Tab(text: 'Pricing'),
            Tab(text: 'Promos'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: const [
          _OverviewTab(),
          _AllRidesTab(),
          _PricingTab(),
          _PromosTab(),
        ],
      ),
    );
  }
}

// ── Tab 1: Overview ───────────────────────────────────────────────────────────

class _OverviewTab extends ConsumerWidget {
  const _OverviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_ridesOverviewProvider);
    return RefreshIndicator(
      color: _kPurple,
      onRefresh: () async => ref.invalidate(_ridesOverviewProvider),
      child: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
        error: (e, _) => _ErrorRetry(message: e.toString(), onRetry: () => ref.invalidate(_ridesOverviewProvider)),
        data: (data) {
          final recentActive = data['recent_active'] as List<Map<String, dynamic>>;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Metrics grid
              GridView.count(
                crossAxisCount: 2,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.6,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MetricCard(
                    label: 'Rides Today',
                    value: '${data['total_today']}',
                    icon: Icons.directions_car_rounded,
                    color: _kPurple,
                  ),
                  _MetricCard(
                    label: 'Active Now',
                    value: '${data['active_count']}',
                    icon: Icons.radio_button_checked_rounded,
                    color: Colors.green,
                  ),
                  _MetricCard(
                    label: 'Drivers Online',
                    value: '${data['drivers_online']}',
                    icon: Icons.person_pin_rounded,
                    color: const Color(0xFF0EA5E9),
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
                  'Recent Active Rides',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 10),
                ...recentActive.map((ride) => _ActiveRideRow(ride: ride)),
              ] else
                const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 24),
                    child: Text('No active rides right now.', style: TextStyle(color: Colors.grey)),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ActiveRideRow extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _ActiveRideRow({required this.ride});

  @override
  Widget build(BuildContext context) {
    final id = (ride['id'] as String?)?.substring(0, 8) ?? '—';
    final status = ride['ride_status'] as String? ?? 'unknown';
    final pickup = _truncate(ride['pickup_address'] as String? ?? '', 35);
    final dest = _truncate(ride['destination_address'] as String? ?? '', 35);
    final createdAt = _relativeTime(ride['created_at'] as String?);
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
              child: const Icon(Icons.directions_car, color: _kPurple, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('#$id', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                      const SizedBox(width: 8),
                      _StatusChip(status: status),
                      const Spacer(),
                      Text(createdAt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '$pickup → $dest',
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

// ── Tab 2: All Rides ──────────────────────────────────────────────────────────

class _AllRidesTab extends ConsumerStatefulWidget {
  const _AllRidesTab();

  @override
  ConsumerState<_AllRidesTab> createState() => _AllRidesTabState();
}

class _AllRidesTabState extends ConsumerState<_AllRidesTab> {
  String? _filterStatus;
  int _loadedCount = 30;
  String? _expandedId;

  static const _filters = [null, 'active', 'completed', 'cancelled'];
  static const _filterLabels = ['All', 'Active', 'Completed', 'Cancelled'];

  @override
  Widget build(BuildContext context) {
    final query = _RidesQuery(
      offset: 0,
      limit: _loadedCount,
      statusFilter: _filterStatus == 'active' ? null : _filterStatus,
    );
    final async = ref.watch(_allRidesProvider(query));

    return RefreshIndicator(
      color: _kPurple,
      onRefresh: () async => ref.invalidate(_allRidesProvider(query)),
      child: Column(
        children: [
          // Filter chips
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
                  onSelected: (_) {
                    setState(() {
                      _filterStatus = _filters[i];
                      _loadedCount = 30;
                      _expandedId = null;
                    });
                  },
                );
              },
            ),
          ),
          Expanded(
            child: async.when(
              loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
              error: (e, _) => _ErrorRetry(
                message: e.toString(),
                onRetry: () => ref.invalidate(_allRidesProvider(query)),
              ),
              data: (rides) {
                // Client-side "active" filter (NOT IN completed/cancelled/failed)
                final filtered = _filterStatus == 'active'
                    ? rides.where((r) {
                        final s = r['ride_status'] as String? ?? '';
                        return !['completed', 'cancelled', 'failed'].contains(s);
                      }).toList()
                    : rides;

                if (filtered.isEmpty) {
                  return const Center(
                    child: Text('No rides found.', style: TextStyle(color: Colors.grey)),
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
                    return _RideRow(
                      ride: filtered[i],
                      expanded: _expandedId == filtered[i]['id'],
                      onTap: () => setState(() {
                        _expandedId = _expandedId == filtered[i]['id']
                            ? null
                            : filtered[i]['id'] as String?;
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

class _RideRow extends StatelessWidget {
  final Map<String, dynamic> ride;
  final bool expanded;
  final VoidCallback onTap;
  const _RideRow({required this.ride, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id = (ride['id'] as String?)?.substring(0, 8) ?? '—';
    final status = ride['ride_status'] as String? ?? 'unknown';
    final customerName = (ride['users'] as Map?)?['name'] as String? ?? 'Unknown';
    final pickup = _truncate(ride['pickup_address'] as String? ?? '', 35);
    final createdAt = _formatDate(ride['created_at'] as String?);

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
                  Text('#$id', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(width: 8),
                  _StatusChip(status: status),
                  const Spacer(),
                  Text(createdAt, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 4),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '$customerName · $pickup',
                style: const TextStyle(fontSize: 12, color: Color(0xFF475569)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (expanded) ...[
                const Divider(height: 16),
                _DetailRow(label: 'Pickup', value: ride['pickup_address'] as String? ?? '—'),
                _DetailRow(label: 'Destination', value: ride['destination_address'] as String? ?? '—'),
                _DetailRow(label: 'Driver ID', value: _shortId(ride['driver_id'] as String?)),
                _DetailRow(label: 'Fare', value: 'J\$${((ride['fare_amount'] as num?) ?? 0).toStringAsFixed(2)}'),
                _DetailRow(label: 'Payment', value: ride['payment_status'] as String? ?? '—'),
                if (ride['accepted_at'] != null)
                  _DetailRow(label: 'Accepted', value: _formatDate(ride['accepted_at'] as String?)),
                if (ride['completed_at'] != null)
                  _DetailRow(label: 'Completed', value: _formatDate(ride['completed_at'] as String?)),
                if (ride['cancelled_at'] != null)
                  _DetailRow(label: 'Cancelled', value: _formatDate(ride['cancelled_at'] as String?)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tab 3: Pricing ────────────────────────────────────────────────────────────

class _PricingTab extends ConsumerStatefulWidget {
  const _PricingTab();

  @override
  ConsumerState<_PricingTab> createState() => _PricingTabState();
}

class _PricingTabState extends ConsumerState<_PricingTab> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, TextEditingController> _ctrl = {};
  bool _saving = false;
  bool _loaded = false;

  static const _fields = [
    ('base_fare', 'Base Fare (JMD)', Icons.flag_rounded),
    ('per_km_rate', 'Per KM Rate (JMD)', Icons.straighten_rounded),
    ('per_minute_rate', 'Per Minute Rate (JMD)', Icons.timer_rounded),
    ('minimum_fare', 'Minimum Fare (JMD)', Icons.price_check_rounded),
    ('peak_multiplier', 'Peak Hour Multiplier', Icons.trending_up_rounded),
    ('night_surcharge', 'Night Surcharge Multiplier', Icons.nightlight_rounded),
  ];

  @override
  void dispose() {
    for (final c in _ctrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _populateFrom(Map<String, dynamic> data) {
    if (_loaded) return;
    _loaded = true;
    for (final field in _fields) {
      final key = field.$1;
      final val = data[key];
      _ctrl[key] = TextEditingController(
        text: val != null ? (val as num).toDouble().toStringAsFixed(2) : '',
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{'id': 'default'};
      for (final field in _fields) {
        payload[field.$1] = double.parse(_ctrl[field.$1]!.text);
      }
      await Supabase.instance.client
          .from('ride_config')
          .upsert(payload, onConflict: 'id');
      ref.invalidate(_ridePricingProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pricing saved'), backgroundColor: _kPurple),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_ridePricingProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
      error: (e, _) => _ErrorRetry(
        message: e.toString(),
        onRetry: () => ref.invalidate(_ridePricingProvider),
      ),
      data: (data) {
        _populateFrom(data);
        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Ride Pricing Configuration',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 4),
                Text(
                  'Changes apply to all new ride fare calculations.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 20),
                ..._fields.map((field) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: TextFormField(
                      controller: _ctrl[field.$1],
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: field.$2,
                        prefixIcon: Icon(field.$3, color: _kPurple, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: const BorderSide(color: _kPurple, width: 2),
                        ),
                      ),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Required';
                        if (double.tryParse(v) == null) return 'Enter a valid number';
                        return null;
                      },
                    ),
                  );
                }),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kPurple,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                          )
                        : const Text('Save Pricing', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Tab 4: Promos ─────────────────────────────────────────────────────────────

class _PromosTab extends ConsumerStatefulWidget {
  const _PromosTab();

  @override
  ConsumerState<_PromosTab> createState() => _PromosTabState();
}

class _PromosTabState extends ConsumerState<_PromosTab> {
  bool _saving = false;
  bool _firstRideEnabled = true;

  final _firstTitleCtrl    = TextEditingController();
  final _firstSubtitleCtrl = TextEditingController();
  final _firstCodeCtrl     = TextEditingController();
  final _firstCtaCtrl      = TextEditingController();
  final _retTitleCtrl      = TextEditingController();
  final _retSubtitleCtrl   = TextEditingController();
  final _retCtaCtrl        = TextEditingController();

  bool _initialized = false;

  @override
  void dispose() {
    _firstTitleCtrl.dispose();
    _firstSubtitleCtrl.dispose();
    _firstCodeCtrl.dispose();
    _firstCtaCtrl.dispose();
    _retTitleCtrl.dispose();
    _retSubtitleCtrl.dispose();
    _retCtaCtrl.dispose();
    super.dispose();
  }

  void _init() {
    if (_initialized) return;
    _initialized = true;
    _firstRideEnabled  = AppConstants.ridePromoFirstRideEnabled;
    _firstTitleCtrl.text    = AppConstants.ridePromoFirstRideTitle;
    _firstSubtitleCtrl.text = AppConstants.ridePromoFirstRideSubtitle;
    _firstCodeCtrl.text     = AppConstants.ridePromoFirstRideCode;
    _firstCtaCtrl.text      = AppConstants.ridePromoFirstRideCta;
    _retTitleCtrl.text      = AppConstants.ridePromoReturningTitle;
    _retSubtitleCtrl.text   = AppConstants.ridePromoReturningSubtitle;
    _retCtaCtrl.text        = AppConstants.ridePromoReturningCta;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final client = Supabase.instance.client;
      final updates = {
        'ride_promo_first_ride_enabled':  _firstRideEnabled ? 'true' : 'false',
        'ride_promo_first_ride_title':    _firstTitleCtrl.text.trim(),
        'ride_promo_first_ride_subtitle': _firstSubtitleCtrl.text.trim(),
        'ride_promo_first_ride_code':     _firstCodeCtrl.text.trim(),
        'ride_promo_first_ride_cta':      _firstCtaCtrl.text.trim(),
        'ride_promo_returning_title':     _retTitleCtrl.text.trim(),
        'ride_promo_returning_subtitle':  _retSubtitleCtrl.text.trim(),
        'ride_promo_returning_cta':       _retCtaCtrl.text.trim(),
      };

      for (final entry in updates.entries) {
        if (entry.value.isEmpty) continue;
        await client
            .from('app_config')
            .update({'value': entry.value, 'updated_at': DateTime.now().toIso8601String()})
            .eq('key', entry.key);
      }

      // Update in-memory constants immediately
      AppConstants.ridePromoFirstRideEnabled  = _firstRideEnabled;
      AppConstants.ridePromoFirstRideTitle    = _firstTitleCtrl.text.trim();
      AppConstants.ridePromoFirstRideSubtitle = _firstSubtitleCtrl.text.trim();
      AppConstants.ridePromoFirstRideCode     = _firstCodeCtrl.text.trim();
      AppConstants.ridePromoFirstRideCta      = _firstCtaCtrl.text.trim();
      AppConstants.ridePromoReturningTitle    = _retTitleCtrl.text.trim();
      AppConstants.ridePromoReturningSubtitle = _retSubtitleCtrl.text.trim();
      AppConstants.ridePromoReturningCta      = _retCtaCtrl.text.trim();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Promo banners saved'), backgroundColor: _kPurple),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _init();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        // ── First-ride banner ────────────────────────────────────────────
        _sectionHeader(
          icon: Icons.celebration_outlined,
          title: 'First-Ride Banner',
          subtitle: 'Shown to customers who have never booked a ride',
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          value: _firstRideEnabled,
          onChanged: (v) => setState(() => _firstRideEnabled = v),
          title: const Text('Enable first-ride promo'),
          subtitle: Text(
            _firstRideEnabled ? 'Banner is visible to new customers' : 'Banner is hidden',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
          contentPadding: EdgeInsets.zero,
        ),
        if (_firstRideEnabled) ...[
          const SizedBox(height: 8),
          _field(_firstTitleCtrl,    'Title',    Icons.title),
          _field(_firstSubtitleCtrl, 'Subtitle', Icons.subtitles_outlined),
          _field(_firstCodeCtrl,     'Promo Code (shown on banner)', Icons.local_offer_outlined),
          _field(_firstCtaCtrl,      'Button Text', Icons.touch_app_outlined),
        ],

        const SizedBox(height: 24),

        // ── Returning-rider banner ───────────────────────────────────────
        _sectionHeader(
          icon: Icons.replay_rounded,
          title: 'Returning-Rider Banner',
          subtitle: 'Shown to customers who have already completed a ride',
        ),
        const SizedBox(height: 12),
        _field(_retTitleCtrl,    'Title',       Icons.title),
        _field(_retSubtitleCtrl, 'Subtitle',    Icons.subtitles_outlined),
        _field(_retCtaCtrl,      'Button Text', Icons.touch_app_outlined),

        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            onPressed: _saving ? null : _save,
            style: ElevatedButton.styleFrom(
              backgroundColor: _kPurple,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    height: 20, width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text('Save Banners', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          ),
        ),
      ],
    );
  }

  Widget _sectionHeader({required IconData icon, required String title, required String subtitle}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: _kPurple, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _field(TextEditingController ctrl, String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          filled: true,
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

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'completed':
        return Colors.green;
      case 'cancelled':
      case 'failed':
        return Colors.red;
      case 'accepted':
      case 'en_route':
      case 'arrived':
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

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;
  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
          ),
        ],
      ),
    );
  }
}

class _ErrorRetry extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorRetry({required this.message, required this.onRetry});

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

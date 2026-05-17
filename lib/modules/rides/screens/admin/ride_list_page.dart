import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const _kPurple = Color(0xFF7C3AED);

// ── Query value object ────────────────────────────────────────────────────────

class _ListQuery {
  final int limit;
  final String? statusFilter;
  const _ListQuery({this.limit = 30, this.statusFilter});

  @override
  bool operator ==(Object other) =>
      other is _ListQuery &&
      other.limit == limit &&
      other.statusFilter == statusFilter;

  @override
  int get hashCode => Object.hash(limit, statusFilter);
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _rideListProvider =
    FutureProvider.family<List<Map<String, dynamic>>, _ListQuery>((ref, q) async {
  final client = Supabase.instance.client;

  if (q.statusFilter != null && q.statusFilter != 'active') {
    final data = await client
        .from('ride_requests')
        .select('*, users!ride_requests_customer_id_fkey(name)')
        .eq('ride_status', q.statusFilter!)
        .order('created_at', ascending: false)
        .limit(q.limit);
    return List<Map<String, dynamic>>.from(data as List);
  }

  final data = await client
      .from('ride_requests')
      .select('*, users!ride_requests_customer_id_fkey(name)')
      .order('created_at', ascending: false)
      .limit(q.limit);
  return List<Map<String, dynamic>>.from(data as List);
});

// ── Screen ────────────────────────────────────────────────────────────────────

class RideListPage extends ConsumerStatefulWidget {
  const RideListPage({super.key});

  @override
  ConsumerState<RideListPage> createState() => _RideListPageState();
}

class _RideListPageState extends ConsumerState<RideListPage> {
  String? _filterStatus;
  int _loadedCount = 30;
  String? _expandedId;

  static const _filters = [null, 'active', 'completed', 'cancelled'];
  static const _filterLabels = ['All', 'Active', 'Completed', 'Cancelled'];

  @override
  Widget build(BuildContext context) {
    final query = _ListQuery(
      limit: _loadedCount,
      statusFilter: _filterStatus,
    );
    final async = ref.watch(_rideListProvider(query));

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Rides', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_rideListProvider(query)),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _kPurple,
        onRefresh: () async => ref.invalidate(_rideListProvider(query)),
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
                    onSelected: (_) => setState(() {
                      _filterStatus = _filters[i];
                      _loadedCount = 30;
                      _expandedId = null;
                    }),
                  );
                },
              ),
            ),
            // List
            Expanded(
              child: async.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(color: _kPurple),
                ),
                error: (e, _) => _ErrorRetry(
                  message: e.toString(),
                  onRetry: () => ref.invalidate(_rideListProvider(query)),
                ),
                data: (rides) {
                  // Client-side "active" filter — exclude terminal statuses
                  final displayed = _filterStatus == 'active'
                      ? rides.where((r) {
                          final s = r['ride_status'] as String? ?? '';
                          return !['completed', 'cancelled', 'failed'].contains(s);
                        }).toList()
                      : rides;

                  if (displayed.isEmpty) {
                    return const Center(
                      child: Text(
                        'No rides found.',
                        style: TextStyle(color: Colors.grey),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: displayed.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      if (i == displayed.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton(
                            onPressed: () => setState(() => _loadedCount += 30),
                            style: OutlinedButton.styleFrom(foregroundColor: _kPurple),
                            child: const Text('Load more'),
                          ),
                        );
                      }
                      final ride = displayed[i];
                      return _RideRow(
                        ride: ride,
                        expanded: _expandedId == ride['id'],
                        onTap: () => setState(() {
                          _expandedId = _expandedId == ride['id']
                              ? null
                              : ride['id'] as String?;
                        }),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _RideRow extends StatelessWidget {
  final Map<String, dynamic> ride;
  final bool expanded;
  final VoidCallback onTap;
  const _RideRow({required this.ride, required this.expanded, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final id = (ride['id'] as String?)?.substring(0, 8) ?? '—';
    final status = ride['ride_status'] as String? ?? 'unknown';
    final customerName =
        (ride['users'] as Map?)?['name'] as String? ?? 'Unknown';
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
                  Text(
                    '#$id',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                  ),
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
                _DetailRow(
                  label: 'Fare',
                  value: 'J\$${((ride['fare_amount'] as num?) ?? 0).toStringAsFixed(2)}',
                ),
                _DetailRow(label: 'Payment', value: ride['payment_status'] as String? ?? '—'),
                if (ride['accepted_at'] != null)
                  _DetailRow(
                    label: 'Accepted',
                    value: _formatDate(ride['accepted_at'] as String?),
                  ),
                if (ride['completed_at'] != null)
                  _DetailRow(
                    label: 'Completed',
                    value: _formatDate(ride['completed_at'] as String?),
                  ),
                if (ride['cancelled_at'] != null)
                  _DetailRow(
                    label: 'Cancelled',
                    value: _formatDate(ride['cancelled_at'] as String?),
                  ),
              ],
            ],
          ),
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
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B)),
            ),
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
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPurple,
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

String _truncate(String s, int max) =>
    s.length > max ? '${s.substring(0, max)}…' : s;

String _shortId(String? id) {
  if (id == null) return '—';
  return id.length > 8 ? id.substring(0, 8) : id;
}

String _formatDate(String? iso) {
  if (iso == null) return '—';
  try {
    final dt = DateTime.parse(iso).toLocal();
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final m = dt.minute.toString().padLeft(2, '0');
    final ampm = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day} · $h:$m $ampm';
  } catch (_) {
    return '—';
  }
}

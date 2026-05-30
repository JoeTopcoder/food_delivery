import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

const _kPurple = Color(0xFF7C3AED);

// ── Provider ──────────────────────────────────────────────────────────────────

final _rideDetailProvider =
    FutureProvider.autoDispose.family<Map<String, dynamic>, String>((ref, rideId) async {
  final client = Supabase.instance.client;
  final data = await client
      .from('ride_requests')
      .select('*, users!ride_requests_customer_id_fkey(name, email, phone)')
      .eq('id', rideId)
      .single();
  return Map<String, dynamic>.from(data as Map);
});

// ── Screen ────────────────────────────────────────────────────────────────────

class RideDetailPage extends ConsumerWidget {
  final String rideId;
  const RideDetailPage({super.key, required this.rideId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_rideDetailProvider(rideId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride Details', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: _kPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(_rideDetailProvider(rideId)),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: _kPurple)),
        error: (e, _) => _ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(_rideDetailProvider(rideId)),
        ),
        data: (ride) => _RideDetailBody(ride: ride),
      ),
    );
  }
}

// ── Body ──────────────────────────────────────────────────────────────────────

class _RideDetailBody extends StatelessWidget {
  final Map<String, dynamic> ride;
  const _RideDetailBody({required this.ride});

  @override
  Widget build(BuildContext context) {
    final status = ride['ride_status'] as String? ?? 'unknown';
    final shortId = (ride['id'] as String? ?? '').substring(0, 8);
    final customer = ride['users'] as Map?;
    final fare = ((ride['final_fare'] as num?) ?? (ride['estimated_fare'] as num?) ?? 0).toDouble();
    final platformFee = ((ride['platform_fee'] as num?) ?? 0).toDouble();
    final driverEarning = ((ride['driver_earning'] as num?) ?? 0).toDouble();
    final distanceKm = ((ride['distance_km'] as num?) ?? 0).toDouble();
    final durationMin = ride['estimated_duration_minutes'] as int?;
    final rating = ride['rating'] as int?;
    final review = ride['review'] as String?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header chip
        Row(
          children: [
            Text(
              '#$shortId',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: Color(0xFF1E293B)),
            ),
            const SizedBox(width: 10),
            _StatusChip(status: status),
          ],
        ),
        const SizedBox(height: 16),

        // Route card
        _Section(
          title: 'Route',
          icon: Icons.route_rounded,
          children: [
            _Row(label: 'Pickup', value: ride['pickup_address'] as String? ?? '—'),
            _Row(label: 'Destination', value: ride['destination_address'] as String? ?? '—'),
            if (distanceKm > 0)
              _Row(label: 'Distance', value: '${distanceKm.toStringAsFixed(2)} km'),
            if (durationMin != null)
              _Row(label: 'Est. Duration', value: '$durationMin min'),
            if (ride['is_airport_pickup'] == true)
              _Row(label: 'Airport Pickup', value: ride['terminal_info'] as String? ?? 'Yes'),
            if (ride['is_airport_dropoff'] == true)
              _Row(label: 'Airport Drop-off', value: 'Yes'),
          ],
        ),

        // Customer card
        _Section(
          title: 'Customer',
          icon: Icons.person_rounded,
          children: [
            _Row(label: 'Name', value: customer?['name'] as String? ?? '—'),
            _Row(label: 'Email', value: customer?['email'] as String? ?? '—'),
            if (customer?['phone'] != null)
              _Row(label: 'Phone', value: customer!['phone'] as String),
            _Row(label: 'Customer ID', value: _shortId(ride['customer_id'] as String?)),
          ],
        ),

        // Driver card
        _Section(
          title: 'Driver',
          icon: Icons.drive_eta_rounded,
          children: [
            _Row(label: 'Driver ID', value: _shortId(ride['driver_id'] as String?)),
          ],
        ),

        // Fare card
        _Section(
          title: 'Fare & Payment',
          icon: Icons.attach_money_rounded,
          children: [
            _Row(label: 'Final Fare', value: 'J\$${fare.toStringAsFixed(2)}'),
            _Row(label: 'Platform Fee', value: 'J\$${platformFee.toStringAsFixed(2)}'),
            _Row(label: 'Driver Earning', value: 'J\$${driverEarning.toStringAsFixed(2)}'),
            _Row(label: 'Payment Method', value: ride['payment_method'] as String? ?? '—'),
            _Row(label: 'Payment Status', value: ride['payment_status'] as String? ?? '—'),
            if (ride['cancellation_fee'] != null)
              _Row(
                label: 'Cancellation Fee',
                value: 'J\$${((ride['cancellation_fee'] as num)).toStringAsFixed(2)}',
              ),
          ],
        ),

        // Timeline card
        _Section(
          title: 'Timeline',
          icon: Icons.schedule_rounded,
          children: [
            _Row(label: 'Requested', value: _fmt(ride['requested_at'] as String?)),
            if (ride['accepted_at'] != null)
              _Row(label: 'Accepted', value: _fmt(ride['accepted_at'] as String?)),
            if (ride['driver_arrived_at'] != null)
              _Row(label: 'Driver Arrived', value: _fmt(ride['driver_arrived_at'] as String?)),
            if (ride['started_at'] != null)
              _Row(label: 'Started', value: _fmt(ride['started_at'] as String?)),
            if (ride['completed_at'] != null)
              _Row(label: 'Completed', value: _fmt(ride['completed_at'] as String?)),
            if (ride['scheduled_for'] != null)
              _Row(label: 'Scheduled For', value: _fmt(ride['scheduled_for'] as String?)),
          ],
        ),

        // Cancellation (if applicable)
        if (status == 'cancelled' && ride['cancellation_reason'] != null)
          _Section(
            title: 'Cancellation',
            icon: Icons.cancel_rounded,
            children: [
              _Row(label: 'Reason', value: ride['cancellation_reason'] as String? ?? '—'),
              _Row(label: 'Cancelled By', value: ride['cancelled_by'] as String? ?? '—'),
            ],
          ),

        // Rating (if available)
        if (rating != null)
          _Section(
            title: 'Rating',
            icon: Icons.star_rounded,
            children: [
              _Row(
                label: 'Stars',
                value: '$rating / 5',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(
                    5,
                    (i) => Icon(
                      i < rating ? Icons.star_rounded : Icons.star_border_rounded,
                      color: const Color(0xFFF59E0B),
                      size: 16,
                    ),
                  ),
                ),
              ),
              if (review != null && review.isNotEmpty)
                _Row(label: 'Review', value: review),
            ],
          ),
      ],
    );
  }
}

// ── Widgets ───────────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _Section({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: _kPurple),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: _kPurple,
                  ),
                ),
              ],
            ),
            const Divider(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  final String label;
  final String value;
  final Widget? trailing;

  const _Row({required this.label, required this.value, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(value, style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B))),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  Color get _color {
    switch (status) {
      case 'ride_completed':
      case 'completed':
        return Colors.green;
      case 'cancelled':
      case 'failed':
        return Colors.red;
      case 'ride_started':
      case 'driver_arriving':
      case 'driver_arrived':
        return const Color(0xFF0EA5E9);
      case 'scheduled':
        return Colors.orange;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _color.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.replaceAll('_', ' '),
        style: TextStyle(color: _color, fontSize: 11, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorView({required this.message, required this.onRetry});

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

String _shortId(String? id) {
  if (id == null) return '—';
  return id.length > 8 ? '#${id.substring(0, 8)}' : '#$id';
}

String _fmt(String? iso) {
  if (iso == null) return '—';
  try {
    return DateFormat('MMM d, yyyy · h:mm a').format(DateTime.parse(iso).toLocal());
  } catch (_) {
    return '—';
  }
}
